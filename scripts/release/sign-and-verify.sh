#!/usr/bin/env bash
# ==============================================================================
#  Container Toolchain — Signing & Verification Script (mandatory Cosign + GPG)
# ==============================================================================

set -euo pipefail

OUT_DIR="out"
RELEASE_TAG="<none>"

while [[ $# -gt 0 ]]; do
    case "$1" in
    --out-dir)
        OUT_DIR="${2}"
        shift 2
        ;;
    --tag)
        RELEASE_TAG="${2}"
        shift 2
        ;;
    *)
        echo "[local-release][WARN] Unknown arg: $1"
        shift 1
        ;;
    esac
done

echo "[local-release] Starting local signing & verification"
echo "[local-release] OUT_DIR=${OUT_DIR}  TAG=${RELEASE_TAG}"

command -v cosign >/dev/null 2>&1 || {
    echo "[ERROR] cosign not found in PATH"
    exit 1
}
command -v syft >/dev/null 2>&1 || {
    echo "[ERROR] syft not found in PATH"
    exit 1
}
command -v gpg >/dev/null 2>&1 || {
    echo "[ERROR] gpg not found in PATH"
    exit 1
}

AMD64_TGZ="${OUT_DIR}/tools-linux-amd64.tar.gz"
ARM64_TGZ="${OUT_DIR}/tools-linux-arm64.tar.gz"
[[ -f "${AMD64_TGZ}" && -f "${ARM64_TGZ}" ]] || {
    echo "[ERROR] Missing toolchain tarballs in ${OUT_DIR}"
    ls -la "${OUT_DIR}" || true
    exit 1
}

[[ -n "${GPG_PRIVATE_KEY:-}" ]] || {
    echo "[ERROR] GPG_PRIVATE_KEY is not set"
    exit 2
}
[[ -n "${GPG_KEY_ID:-}" ]] || {
    echo "[ERROR] GPG_KEY_ID is not set"
    exit 2
}

echo "[local-release] Generating SHA256SUMS"
pushd "${OUT_DIR}" >/dev/null
sha256sum "tools-linux-amd64.tar.gz" >SHA256SUMS
sha256sum "tools-linux-arm64.tar.gz" >>SHA256SUMS
popd >/dev/null

echo "[local-release] Generating SBOM (SPDX JSON) with Syft"
syft "dir:${OUT_DIR}" -o "spdx-json=${OUT_DIR}/sbom.spdx.json"

echo "[local-release] Cosign signing (bundle)"
if [[ -n "${COSIGN_PRIVATE_KEY:-}" ]]; then
    cosign sign-blob --yes --key env://COSIGN_PRIVATE_KEY \
        "${AMD64_TGZ}" --bundle "${OUT_DIR}/tools-linux-amd64.cosign.bundle"
    cosign sign-blob --yes --key env://COSIGN_PRIVATE_KEY \
        "${ARM64_TGZ}" --bundle "${OUT_DIR}/tools-linux-arm64.cosign.bundle"
else
    cosign sign-blob --yes \
        "${AMD64_TGZ}" --bundle "${OUT_DIR}/tools-linux-amd64.cosign.bundle"
    cosign sign-blob --yes \
        "${ARM64_TGZ}" --bundle "${OUT_DIR}/tools-linux-arm64.cosign.bundle"
fi

echo "[local-release] GPG signing (detached ASCII)"
echo "${GPG_PRIVATE_KEY}" | gpg --batch --import || {
    echo "[ERROR] Failed to import GPG private key"
    exit 2
}

GPG_ARGS=(--batch --yes --pinentry-mode loopback --armor --detach-sign -u "${GPG_KEY_ID}")
[[ -n "${GPG_PASSPHRASE:-}" ]] && GPG_ARGS+=(--passphrase "${GPG_PASSPHRASE}")

gpg "${GPG_ARGS[@]}" "${AMD64_TGZ}" || {
    echo "[ERROR] GPG signing failed (amd64)"
    exit 2
}
gpg "${GPG_ARGS[@]}" "${ARM64_TGZ}" || {
    echo "[ERROR] GPG signing failed (arm64)"
    exit 2
}
gpg "${GPG_ARGS[@]}" "${OUT_DIR}/SHA256SUMS" || {
    echo "[ERROR] GPG signing failed (SHA256SUMS)"
    exit 2
}

echo "[local-release] Verifying Cosign bundles"

if [[ -n "${COSIGN_PUBLIC_KEY:-}" ]]; then
    # --- KEYFUL VERIFICATION (BYOK): use public key, no identity/issuer needed ---
    cosign verify-blob \
        --bundle "${OUT_DIR}/tools-linux-amd64.cosign.bundle" \
        "${AMD64_TGZ}" \
        --key env://COSIGN_PUBLIC_KEY || {
        echo "[ERROR] Cosign verification failed (amd64, keyful)"
        exit 1
    }

    cosign verify-blob \
        --bundle "${OUT_DIR}/tools-linux-arm64.cosign.bundle" \
        "${ARM64_TGZ}" \
        --key env://COSIGN_PUBLIC_KEY || {
        echo "[ERROR] Cosign verification failed (arm64, keyful)"
        exit 1
    }

else
    # --- KEYLESS VERIFICATION: require identity + issuer for Fulcio cert in bundle ---
    : "${COSIGN_CERT_OIDC_ISSUER:?set COSIGN_CERT_OIDC_ISSUER (e.g. https://token.actions.githubusercontent.com)}"

    # Preferisci identity "strict" oppure una regexp più flessibile.
    if [[ -n "${COSIGN_CERT_IDENTITY:-}" ]]; then
        cosign verify-blob \
            --bundle "${OUT_DIR}/tools-linux-amd64.cosign.bundle" \
            "${AMD64_TGZ}" \
            --certificate-identity "${COSIGN_CERT_IDENTITY}" \
            --certificate-oidc-issuer "${COSIGN_CERT_OIDC_ISSUER}" || {
            echo "[ERROR] Cosign verification failed (amd64, keyless)"
            exit 1
        }

        cosign verify-blob \
            --bundle "${OUT_DIR}/tools-linux-arm64.cosign.bundle" \
            "${ARM64_TGZ}" \
            --certificate-identity "${COSIGN_CERT_IDENTITY}" \
            --certificate-oidc-issuer "${COSIGN_CERT_OIDC_ISSUER}" || {
            echo "[ERROR] Cosign verification failed (arm64, keyless)"
            exit 1
        }

    elif [[ -n "${COSIGN_CERT_IDENTITY_REGEXP:-}" ]]; then
        cosign verify-blob \
            --bundle "${OUT_DIR}/tools-linux-amd64.cosign.bundle" \
            "${AMD64_TGZ}" \
            --certificate-identity-regexp "${COSIGN_CERT_IDENTITY_REGEXP}" \
            --certificate-oidc-issuer "${COSIGN_CERT_OIDC_ISSUER}" || {
            echo "[ERROR] Cosign verification failed (amd64, keyless/regexp)"
            exit 1
        }

        cosign verify-blob \
            --bundle "${OUT_DIR}/tools-linux-arm64.cosign.bundle" \
            "${ARM64_TGZ}" \
            --certificate-identity-regexp "${COSIGN_CERT_IDENTITY_REGEXP}" \
            --certificate-oidc-issuer "${COSIGN_CERT_OIDC_ISSUER}" || {
            echo "[ERROR] Cosign verification failed (arm64, keyless/regexp)"
            exit 1
        }

    else
        echo "[ERROR] Keyless verification: set COSIGN_CERT_IDENTITY or COSIGN_CERT_IDENTITY_REGEXP"
        exit 1
    fi
fi

echo "[local-release] Completed successfully ✅"
echo "[local-release] Artifacts ready in: ${OUT_DIR}"
echo "  • tools-linux-amd64.tar.gz"
echo "  • tools-linux-arm64.tar.gz"
echo "  • SHA256SUMS"
echo "  • sbom.spdx.json"
echo "  • tools-linux-amd64.cosign.bundle"
echo "  • tools-linux-arm64.cosign.bundle"
echo "  • tools-linux-amd64.tar.gz.asc"
echo "  • tools-linux-arm64.tar.gz.asc"
echo "  • SHA256SUMS.asc"
