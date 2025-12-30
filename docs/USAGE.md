# USAGE — UBI‑9 Multi‑Architecture Builder Toolchain

> **Purpose:** This operational guide covers **all usage scenarios** end to end: local builds (amd64/arm64), cross‑compilation details, signing & verification (Cosign keyful/keyless + GPG), SBOM generation, release publication, SLSA provenance, pin overrides, builder prompts/banners, CI usage, consumption of produced artifacts, and troubleshooting.

---

## Table of Contents

1. Prerequisites  
2. Version Pins  
3. Local Package Builds (amd64 / arm64)  
   - 3.1 amd64 (native)  
   - 3.2 arm64 (cross‑build on amd64 host)  
   - 3.3 Outputs & Smoke Tests  
4. Signing & Verification  
   - 4.1 Keyful (BYOK) with Cosign + GPG  
   - 4.2 Keyless (OIDC/Fulcio) with Cosign + GPG  
   - 4.3 Verifying Cosign Bundles (Keyful vs Keyless)  
   - 4.4 GPG Verification Examples  
5. SBOM (SPDX) & Checksums  
6. SLSA Provenance & Attestation Consumption  
7. Builder Image — Build & Push  
8. Using Docker to Run the Builder Locally  
9. CI/CD Usage (GitHub Actions)  
10. Consuming Produced Artifacts in Other Images  
11. Prompt & Banner Configuration (Optional)  
12. Advanced Examples  
13. Troubleshooting  
14. Environment Variables — Quick Reference  
15. FAQ

---

## 1. Prerequisites

### Host / Developer Machine
- Linux with: `git`, `jq`, `make`, `gcc`, `g++`, `tar`, `xz`, `gzip`
- For **arm64** builds (cross‑compile on amd64 host): **`clang`** and **`ld.lld`**
- **Go** toolchain available (also preinstalled in the builder image)
- For **signing & verification**: `cosign`, `syft`, `gpg`

> The scripts **validate prerequisites** and fail with explicit messages if something is missing.

---

## 2. Version Pins

All pins live in:

```

build/config/tool-versions.json

````

Example:
```json
{
  "kubectl": "v1.35.0",
  "oc": "release-4.23",
  "rancher": "v2.13.1",
  "go": "1.25.5",
  "fulcio": "v1.8.4"
}
````

*   `build-tools.sh` loads pins at runtime and applies them for the build.
*   For `oc`, the script **pins** `github.com/sigstore/fulcio` in `go.mod`, runs `go mod tidy` + `vendor`, and **verifies** the vendor version matches (supply‑chain hardening).
*   CI’s **`auto-update.yml`** can bump `kubectl`/`rancher` nightly and open a PR **only when values change**, preserving other pins.

---

## 3. Local Package Builds (amd64 / arm64)

> Script: `./build-tools.sh`  
> Output tarballs: `/out/tools-linux-<arch>.tar.gz` containing `kubectl`, `oc`, `rancher`

### 3.1 amd64 (native)

```bash
# OS ARCH
./build-tools.sh linux amd64
# Output: /out/tools-linux-amd64.tar.gz
```

### 3.2 arm64 (cross‑build on amd64 host)

```bash
./build-tools.sh linux arm64
# Output: /out/tools-linux-arm64.tar.gz
```

*   For **arm64**, the script sets:
    *   `PKG_CONFIG_SYSROOT_DIR=/opt/sysroot/arm64`
    *   `PKG_CONFIG_LIBDIR=/opt/sysroot/arm64/usr/lib64/pkgconfig:/opt/sysroot/arm64/usr/lib/pkgconfig`
    *   `CC=clang`, `CXX=clang++`, `LD=ld.lld`, `AR=llvm-ar`
    *   `CGO_ENABLED=1` (for `oc`), with external link flags

### 3.3 Outputs & Smoke Tests

After packaging:

*   **Presence & executable bit** checked for `kubectl`, `oc`, `rancher`
*   **Architecture check** using ELF headers:
    *   amd64 tarball: x86‑64
    *   arm64 tarball: AArch64
*   **Client version output** (native arch only):
    *   `kubectl version --client --output=yaml` contains `gitVersion: ...`
    *   `oc version --client` prints `Client Version: ...`

---

## 4. Signing & Verification

> Script: `./sign-and-verify.sh`  
> Generates: `SHA256SUMS`, `sbom.spdx.json`, Cosign bundles (`*.cosign.bundle`), GPG signatures (`*.asc`)

### 4.1 Keyful (BYOK) with Cosign + GPG

```bash
export OUT_DIR=out
export GPG_PRIVATE_KEY="$(cat ~/.gnupg/private.key)"
export GPG_KEY_ID="YOUR-GPG-KEY-ID"
export COSIGN_PRIVATE_KEY="$(cat cosign.key)"  # optional; if missing, keyless flow is used

./sign-and-verify.sh --out-dir "$OUT_DIR" --tag v1.0.0
```

### 4.2 Keyless (OIDC/Fulcio) with Cosign + GPG

```bash
export OUT_DIR=out
export GPG_PRIVATE_KEY="$(cat ~/.gnupg/private.key)"
export GPG_KEY_ID="YOUR-GPG-KEY-ID"

# Required for keyless verification:
export COSIGN_CERT_OIDC_ISSUER="https://token.actions.githubusercontent.com"
# Choose ONE:
export COSIGN_CERT_IDENTITY="your-identity@example.org"
# or use a regexp:
# export COSIGN_CERT_IDENTITY_REGEXP="^mailto:.*@example\.org$"

./sign-and-verify.sh --out-dir "$OUT_DIR" --tag v1.0.0
```

### 4.3 Verifying Cosign Bundles (Keyful vs Keyless)

**Keyful (BYOK) verification:**

```bash
# if you have COSIGN_PUBLIC_KEY exported in env
cosign verify-blob \
  --bundle out/tools-linux-amd64.cosign.bundle \
  out/tools-linux-amd64.tar.gz \
  --key env://COSIGN_PUBLIC_KEY

cosign verify-blob \
  --bundle out/tools-linux-arm64.cosign.bundle \
  out/tools-linux-arm64.tar.gz \
  --key env://COSIGN_PUBLIC_KEY
```

**Keyless (OIDC/Fulcio) verification:**

```bash
# Use certificate identity (strict) or regexp + issuer
cosign verify-blob \
  --bundle out/tools-linux-amd64.cosign.bundle \
  out/tools-linux-amd64.tar.gz \
  --certificate-identity "your-identity@example.org" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com"

cosign verify-blob \
  --bundle out/tools-linux-arm64.cosign.bundle \
  out/tools-linux-arm64.tar.gz \
  --certificate-identity-regexp "^mailto:.*@example\.org$" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com"
```

> If identity/issuer are not provided for **keyless**, verification **must fail** by design.

### 4.4 GPG Verification Examples

**Verify detached signatures for tarballs:**

```bash
gpg --verify out/tools-linux-amd64.tar.gz.asc out/tools-linux-amd64.tar.gz
gpg --verify out/tools-linux-arm64.tar.gz.asc out/tools-linux-arm64.tar.gz
```

**Verify SHA256SUMS signature:**

```bash
gpg --verify out/SHA256SUMS.asc out/SHA256SUMS
# Then check actual file hashes:
sha256sum -c out/SHA256SUMS
```

---

## 5. SBOM (SPDX) & Checksums

*   SBOM is generated with **Syft** in SPDX‑JSON format:
    *   `out/sbom.spdx.json`
*   Checksums:
    *   `out/SHA256SUMS` with `sha256sum`
    *   Detached signature `out/SHA256SUMS.asc` (GPG)

> Attach SBOM and checksums alongside tarballs in every release for auditability.

---

## 6. SLSA Provenance & Attestation Consumption

*   The CI job (in `build-toolchain.yml`) uses the **SLSA Generic Generator** to produce **in‑toto** provenance for released artifacts.
*   The attestation is uploaded as a **release asset**.

**Example: validating the attestation (generic approach):**

```bash
# Download the attestation asset (e.g., provenance.intoto.jsonl)
# Validation specifics depend on your SLSA consumer tools.
jq -c '.predicate.materials, .subject' provenance.intoto.jsonl
```

> Integrate with your internal SLSA consumer/validator to gate deployments based on provenance.

---

## 7. Builder Image — Build & Push

Workflow: `build-image.yml`

*   Builds **multi‑arch** (amd64, arm64) builder image on UBI 9
*   Validates presence of prompt/banner scripts
*   Pushes to **GHCR** with `:latest` and immutable `:<sha>` tags
*   Build args allow runtime customization (colors, titles, metadata)

**Manual example (local Buildx):**

```bash
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t ghcr.io/<owner>/ubi9-toolchain-builder:latest \
  -f build/Dockerfile \
  --push \
  --build-arg GO_VERSION=1.25.5 \
  --build-arg WELCOME_ENABLE=1 \
  --build-arg PROMPT_ENABLE_COLORS=1 \
  .
```

---

## 8. Using Docker to Run the Builder Locally

> Useful when you prefer isolating builds inside the builder image.

**Cross‑build ARM64 using the builder container:**

```bash
# Prepare caches and output dir
mkdir -p out .cache/go-build .cache/go-mod .cache/dnf .cache/ccache

docker run --rm --platform linux/amd64 \
  --security-opt=no-new-privileges:true \
  --cap-drop=ALL --cap-add=DAC_OVERRIDE \
  -e TOOLCHAIN_BUILDER=1 \
  -e OS=linux \
  -e KUBECTL_VERSION=v1.35.0 \
  -e OCREF=release-4.23 \
  -e RANCHER_VERSION=v2.13.1 \
  -e FULCIO_VERSION=v1.8.4 \
  -e GO_VERSION=1.25.5 \
  -v "$PWD/out:/out" \
  -v "$PWD/build:/build" \
  -v "$PWD/.cache/go-build:/root/.cache/go-build" \
  -v "$PWD/.cache/go-mod:/go/pkg/mod" \
  -v "$PWD/.cache/dnf:/var/cache/dnf" \
  -v "$PWD/.cache/ccache:/root/.ccache" \
  ghcr.io/<owner>/ubi9-toolchain-builder:latest \
  bash -lc 'export GOOS=linux GOARCH=arm64 CGO_ENABLED=1 CC=clang CXX=clang++ \
            PKG_CONFIG_SYSROOT_DIR=/opt/sysroot/arm64 \
            PKG_CONFIG_LIBDIR=/opt/sysroot/arm64/usr/lib64/pkgconfig:/opt/sysroot/arm64/usr/lib/pkgconfig;
            bash /build/build-tools.sh linux arm64'
```

**Native amd64 build in container:**

```bash
docker run --rm --platform linux/amd64 \
  --security-opt=no-new-privileges:true \
  --cap-drop=ALL --cap-add=DAC_OVERRIDE \
  -e TOOLCHAIN_BUILDER=1 \
  -e OS=linux \
  -e KUBECTL_VERSION=v1.35.0 \
  -e OCREF=release-4.23 \
  -e RANCHER_VERSION=v2.13.1 \
  -e FULCIO_VERSION=v1.8.4 \
  -e GO_VERSION=1.25.5 \
  -v "$PWD/out:/out" \
  -v "$PWD/build:/build" \
  -v "$PWD/.cache/go-build:/root/.cache/go-build" \
  -v "$PWD/.cache/go-mod:/go/pkg/mod" \
  -v "$PWD/.cache/dnf:/var/cache/dnf" \
  -v "$PWD/.cache/ccache:/root/.ccache" \
  ghcr.io/<owner>/ubi9-toolchain-builder:latest \
  bash -lc 'export GOOS=linux GOARCH=amd64 CGO_ENABLED=1 CC=gcc CXX=g++;
            bash /build/build-tools.sh linux amd64'
```

---

## 9. CI/CD Usage (GitHub Actions)

Main workflows:

1.  **`build-toolchain.yml`**
    *   Cross‑build tools for amd64/arm64
    *   Upload artifacts
    *   **Sign & Release**: Cosign (keyful/keyless) + GPG, SBOM, draft → latest release
    *   **SLSA** attestation upload

2.  **`build-image.yml`**
    *   Build/push the builder image to GHCR (multi‑arch)

3.  **`auto-update.yml`**
    *   Nightly pin bump for `kubectl`/`rancher` with an auto PR on change

4.  **`pr-governance.yml`**, **`codeql.yml`**, **`security.yml`**, **`dependabot.yml`**, **`releases.yml`**
    *   PR hygiene (checklist/title/labels/issue linking)
    *   Security scanning (CodeQL, Gitleaks → SARIF upload)
    *   Dependency updates & release notes categories

**Manual trigger tips:**

*   From GitHub UI → **Actions** → select workflow → **Run workflow**
*   Or use `gh` CLI:
    ```bash
    gh workflow run build-toolchain.yml -f ref=master
    gh workflow run build-image.yml
    ```

---

## 10. Consuming Produced Artifacts in Other Images

**Extract tools into a runtime image (example Dockerfile):**

```dockerfile
FROM registry.access.redhat.com/ubi9/ubi-minimal:latest
ARG TOOLS_TARBALL=/tmp/tools-linux-amd64.tar.gz

# Copy the tarball (produced by build-tools.sh) into the image
COPY tools-linux-amd64.tar.gz ${TOOLS_TARBALL}

# Verify checksum (optional, use SHA256SUMS from the release)
# RUN echo "<sha256>  ${TOOLS_TARBALL}" | sha256sum -c -

# Install tools under /usr/local/bin
RUN mkdir -p /usr/local/bin && \
    tar -C /usr/local/bin -xzf ${TOOLS_TARBALL} kubectl oc rancher && \
    chmod 0755 /usr/local/bin/kubectl /usr/local/bin/oc /usr/local/bin/rancher && \
    rm -f ${TOOLS_TARBALL}

ENTRYPOINT ["/usr/local/bin/oc"]
```

**Runtime verification examples:**

```bash
kubectl version --client --output=yaml
oc version --client
rancher --version || rancher --help
```

---

## 11. Prompt & Banner Configuration (Optional)

Files:

*   `/etc/profile.d/00-welcome.sh` (banner)
*   `/etc/profile.d/10-ps1.sh` (PS1 prompt)

**Enable banner & set metadata:**

```bash
export WELCOME_ENABLE=1
export IMAGE_TITLE="UBI9 Container Toolchain Builder"
export IMAGE_DESCRIPTION="UBI9-based builder (amd64 host, arm64 cross sysroot)"
export IMAGE_VENDOR="Your Org"
export AUTHOR_EMAIL="devops@your-org.com"
export COMPANY_NAME="Your Org"
```

**Prompt colors (or disable):**

```bash
export PROMPT_ENABLE_COLORS=1     # enable colors
# or disable:
export NO_COLOR=1
```

---

## 12. Advanced Examples

### 12.1 Temporary Pin Overrides

```bash
# Override kubectl version without editing tool-versions.json
export KUBECTL_VERSION_OVERRIDE="v1.35.1"
./build-tools.sh linux amd64
```

### 12.2 Forcing CGO behavior

```bash
# For oc on amd64: ensure CGO_ENABLED=1 (default in script)
export CGO_ENABLED=1
./build-tools.sh linux amd64
```

### 12.3 Investigating ELF and interpreter (arm64)

```bash
readelf -h /path/to/oc | sed -n '1,30p'
readelf -l /path/to/oc | grep -E 'interpreter|Requesting program interpreter' || \
  echo "OK if statically linked"
```

### 12.4 Ccache tuning

```bash
# If ccache is present, the script sets defaults. You can tune them:
export CCACHE_DIR=/root/.ccache
export CCACHE_MAXSIZE=10G
./build-tools.sh linux amd64
```

### 12.5 Cosign keyful → exporting keys to env

```bash
export COSIGN_PRIVATE_KEY="$(cat /secure/keys/cosign.key)"
export COSIGN_PUBLIC_KEY="$(cat /secure/keys/cosign.pub)"
cosign version
```

### 12.6 GPG import & list keys

```bash
# Import a private key and list it
gpg --batch --import /secure/keys/private.key
gpg --list-keys
```

### 12.7 SBOM quick grep (SPDX JSON)

```bash
jq '.packages[] | {name: .name, version: .versionInfo}' out/sbom.spdx.json | head -n 20
```

### 12.8 Validating checksums locally

```bash
cd out
sha256sum -c SHA256SUMS
```

---

## 13. Troubleshooting

**Missing dependencies (host):**  
Error indicates `git`, `jq`, `clang`, `ld.lld`, etc. are missing — install them and retry.

**`go` not found:**  
The builder expects `go` preinstalled; ensure the builder image includes it or install locally.

**Cosign / Syft / GPG missing:**  
`sign-and-verify.sh` requires these tools in `PATH`. Install them before signing/verifying.

**ARM64 cross‑build on amd64:**  
Ensure `clang` and `ld.lld` exist; the script sets `PKG_CONFIG_*` and proper `CGO` flags for `oc`.  
**Do not execute** arm64 binaries on an amd64 host — limit smoke tests to ELF header & interpreter inspection.

**Fulcio pin mismatch in `oc`:**  
Update `fulcio` version in `tool-versions.json` and rerun; the script calls `go mod tidy` + `vendor` and validates the pinned vendor version.

**Smoke test failed:**  
Check executable permissions (`chmod 0755`), architecture with `readelf -h`, and on amd64 validate `kubectl version --client`, `oc version --client`.

**CI caches not restoring:**  
Verify cache keys in workflow and runner permissions; ensure directories exist and are writable.

**Keyless verification errors (Cosign):**  
Confirm `COSIGN_CERT_OIDC_ISSUER` and identity/regexp are set correctly and match issuer claims embedded in the bundle.

---

## 14. Environment Variables — Quick Reference

### `build-tools.sh`

*   **Positional args:** `OS` `ARCH` (e.g., `linux amd64` | `linux arm64`)
*   **Overrides:**  
    `KUBECTL_VERSION_OVERRIDE`, `OCREF_OVERRIDE`, `RANCHER_VERSION_OVERRIDE`, `FULCIO_VERSION_OVERRIDE`, `GO_VERSION_INPUT`
*   **ARM64 cross compile:**  
    `PKG_CONFIG_SYSROOT_DIR`, `PKG_CONFIG_LIBDIR`, `CC`, `CXX`, `LD`, `AR` (defaults pre‑set for arm64)
*   **Go build tuning:**  
    `GOMAXPROCS`, `GOFLAGS`, `GOWORK`, `GOTOOLCHAIN`
*   **Ccache (optional):**  
    `CCACHE_DIR`, `CCACHE_MAXSIZE`, `CC`, `CXX`, `LD`, `AR`

### `sign-and-verify.sh`

*   **General:** `OUT_DIR`, `RELEASE_TAG`
*   **Cosign (keyful):** `COSIGN_PRIVATE_KEY`, `COSIGN_PUBLIC_KEY`
*   **Cosign (keyless):** `COSIGN_CERT_OIDC_ISSUER`, `COSIGN_CERT_IDENTITY` **or** `COSIGN_CERT_IDENTITY_REGEXP`
*   **GPG:** `GPG_PRIVATE_KEY`, `GPG_KEY_ID`, `GPG_PASSPHRASE`

### Banner / Prompt

*   `WELCOME_ENABLE`, `IMAGE_TITLE`, `IMAGE_DESCRIPTION`, `IMAGE_VENDOR`, `AUTHOR_EMAIL`, `COMPANY_NAME`
*   `PROMPT_ENABLE_COLORS` **or** `NO_COLOR`

---

## 15. FAQ

**Can I build additional tools with this builder?**  
Yes. The builder includes compilers and tooling; add your build script(s), produce binaries, and package them under `/out`.

**Why does `oc` use `CGO=1` with external linking?**  
To include specific tags (`containers_image_openpgp`, `gssapi` on amd64) and ensure correct linkage with system libraries; the script applies `-linkmode=external` and `-extldflags` tuning.

**Is GPG mandatory if I use Cosign keyless?**  
Not strictly; however, GPG provides **defense‑in‑depth** and lets you sign `SHA256SUMS` and tarballs with detached signatures, which many enterprises still require.

**How do I consume SBOM and SLSA in downstream compliance checks?**  
Attach both to releases; use your internal SBOM analyzer and SLSA consumer/validator to gate deployments. Examples above show how to inspect SBOM quickly and parse SLSA subjects.

---
