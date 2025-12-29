#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Script Name : build-tools.sh
# Description : Builds toolchain inside UBI9 container.
# Author      : Lorenzo Biosa - lorenzo@biosa-labs.com
# -----------------------------------------------------------------------------
set -Eeuo pipefail

# ----------------------------- Params & Defaults ------------------------------
OS="${1:-linux}"
ARCH="${2:-amd64}" # target arch (amd64|arm64)
GO_VERSION_INPUT="${3:-}"

# ----------------------------- Logging & Errors -------------------------------
log() { printf '[build] %s\n' "$*"; }
warn() { printf '[build][WARN] %s\n' "$*" >&2; }
fail() {
    printf '[build][ERROR] %s\n' "$*" >&2
    exit 1
}
trap 'fail "unhandled error at line $LINENO"' ERR

# ----------------------------- Workspace & Cleanup ----------------------------
WORKDIR="$(mktemp -d)"
SMOKE_DIR=""
cleanup() {
    rm -rf "${WORKDIR}" || true
    [ -n "${SMOKE_DIR}" ] && rm -rf "${SMOKE_DIR}" || true
}
trap cleanup EXIT

# ----------------------------- Base System Deps -------------------------------
for cmd in git jq make gcc g++ tar xz gzip; do
    command -v "$cmd" >/dev/null 2>&1 || fail "missing dependency: $cmd"
done
# For ARM64 cross we also rely on clang/ld.lld inside builder
if [ "${ARCH}" = "arm64" ]; then
    command -v clang >/dev/null 2>&1 || fail "missing dependency: clang"
    command -v ld.lld >/dev/null 2>&1 || fail "missing dependency: ld.lld (LLD)"
fi

# ----------------------------- Load JSON Pins (optional) ----------------------
VERSIONS_JSON="/build/config/tool-versions.json"
KUBECTL_VERSION_PIN=""
OCREF_PIN=""
RANCHER_VERSION_PIN=""
FULCIO_VERSION_PIN=""
GO_VERSION_PIN=""
if [ -f "${VERSIONS_JSON}" ]; then
    KUBECTL_VERSION_PIN="$(jq -r '.kubectl // empty' "${VERSIONS_JSON}")"
    OCREF_PIN="$(jq -r '.oc // empty' "${VERSIONS_JSON}")"
    RANCHER_VERSION_PIN="$(jq -r '.rancher // empty' "${VERSIONS_JSON}")"
    FULCIO_VERSION_PIN="$(jq -r '.fulcio // empty' "${VERSIONS_JSON}")"
    GO_VERSION_PIN="$(jq -r '.go // empty' "${VERSIONS_JSON}")"
fi

# ----------------------------- Resolve Final Versions -------------------------
KUBECTL_VERSION="${KUBECTL_VERSION_OVERRIDE:-${KUBECTL_VERSION_PIN:-}}"
OCREF="${OCREF_OVERRIDE:-${OCREF_PIN:-}}"
RANCHER_VERSION="${RANCHER_VERSION_OVERRIDE:-${RANCHER_VERSION_PIN:-}}"
FULCIO_VERSION="${FULCIO_VERSION_OVERRIDE:-${FULCIO_VERSION_PIN:-}}"
GO_VERSION="${GO_VERSION_INPUT:-${GO_VERSION_PIN:-1.25.5}}"

log "Pins → kubectl=${KUBECTL_VERSION}, oc=${OCREF}, rancher=${RANCHER_VERSION:-<latest>}, fulcio=${FULCIO_VERSION}, go=${GO_VERSION}"

# ----------------------------- Fast-path: prebuilt ----------------------------
PREBUILT_DIR="/opt/prebuilt/linux-${ARCH}/bin"
if [ -d "${PREBUILT_DIR}" ] &&
    [ -f "${PREBUILT_DIR}/kubectl" ] &&
    [ -f "${PREBUILT_DIR}/oc" ] &&
    [ -f "${PREBUILT_DIR}/rancher" ]; then
    install -m0755 "${PREBUILT_DIR}/kubectl" /opt/tools/bin/kubectl
    install -m0755 "${PREBUILT_DIR}/oc" /opt/tools/bin/oc
    install -m0755 "${PREBUILT_DIR}/rancher" /opt/tools/bin/rancher
    log "Using prebuilt binaries from ${PREBUILT_DIR}"
    goto_package=true
else
    goto_package=false
fi

# ----------------------------- Go Toolchain (HOST-based) ----------------------
if [ "${goto_package}" != "true" ]; then
    HOST_UNAME="$(uname -m)"
    case "${HOST_UNAME}" in
    x86_64) GO_HOST_TARBALL="linux-amd64" ;;
    aarch64) GO_HOST_TARBALL="linux-arm64" ;;
    *)
        GO_HOST_TARBALL="linux-amd64"
        warn "Unknown host arch '${HOST_UNAME}', defaulting to linux-amd64"
        ;;
    esac

    GO_URL="https://go.dev/dl/go${GO_VERSION}.${GO_HOST_TARBALL}.tar.gz"
    curl -fsSL "${GO_URL}" -o "${WORKDIR}/go.tgz" || fail "go: download failed (${GO_URL})"
    tar -C /usr/local -xzf "${WORKDIR}/go.tgz" || fail "go: extract failed"
    rm -f "${WORKDIR}/go.tgz"

    export GOROOT=/usr/local/go
    export GOPATH=/root/go
    export PATH="$GOROOT/bin:$GOPATH/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    export GOOS="${OS}" GOARCH="${ARCH}" GOTOOLCHAIN=local
    : "${GOMAXPROCS:=$(nproc)}"
    export GOMAXPROCS
    : "${GOFLAGS:=-trimpath}"
    export GOWORK=off
    export GOFLAGS="${GOFLAGS} -buildvcs=false"

    if command -v ccache >/dev/null 2>&1; then
        export CCACHE_DIR=/root/.ccache
        export CCACHE_MAXSIZE=5G
        if [ "${ARCH}" = "arm64" ]; then
            # Use clang/clang++ with ccache for ARM64 cross builds
            export CC="ccache clang"
            export CXX="ccache clang++"
            export AR=llvm-ar
            export LD=ld.lld
        else
            # Native builds (amd64): gcc/g++
            export CC="ccache gcc"
            export CXX="ccache g++"
        fi
        log "ccache enabled: dir=${CCACHE_DIR}, maxsize=${CCACHE_MAXSIZE}, CC=${CC}, CXX=${CXX}"
    else
        log "ccache not available; proceeding without compiler cache"
        # Ensure toolchain for ARM64 even without ccache
        if [ "${ARCH}" = "arm64" ]; then
            export CC="${CC:-clang}"
            export CXX="${CXX:-clang++}"
            export AR="${AR:-llvm-ar}"
            export LD="${LD:-ld.lld}"
        fi
    fi

    # Default pkg-config sysroot/libdir for ARM64 cross (unless provided by workflow)
    if [ "${ARCH}" = "arm64" ]; then
        export PKG_CONFIG_SYSROOT_DIR="${PKG_CONFIG_SYSROOT_DIR:-/opt/sysroot/arm64}"
        export PKG_CONFIG_LIBDIR="${PKG_CONFIG_LIBDIR:-/opt/sysroot/arm64/usr/lib64/pkgconfig:/opt/sysroot/arm64/usr/lib/pkgconfig}"
    fi
fi

mkdir -p /opt/tools/bin /out

# ----------------------------- Helpers: ldflags -------------------------------
build_date() { date -u +%Y-%m-%dT%H:%M:%SZ; }

kubectl_ldflags() {
    local version="$1" commit="$2"
    cat <<EOF
-s -w \
-X k8s.io/component-base/version.gitVersion=${version} \
-X k8s.io/component-base/version.gitCommit=${commit} \
-X k8s.io/component-base/version.gitTreeState=clean \
-X k8s.io/component-base/version.buildDate=$(build_date)
EOF
}

# Deriva un SemVer valido per k8s component-base da un ref di oc
derive_kube_semver() {
    local ref="$1"
    # Caso 1: già SemVer con prefisso v
    if [[ "$ref" =~ ^v([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
        echo "$ref"
        return 0
    fi
    # Caso 2: release-X.Y  → vX.Y.0
    if [[ "$ref" =~ ^release-([0-9]+)\.([0-9]+)$ ]]; then
        echo "v${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.0"
        return 0
    fi
    # Fallback (evita panic anche su formati imprevisti)
    echo "v0.0.0"
}

oc_ldflags() {
    local version="$1" commit="$2"
    # Deriva SemVer per component-base (kube) dai ref di oc
    local kube_semver
    kube_semver="$(derive_kube_semver "${version}")"
    cat <<EOF
-s -w \
-X github.com/openshift/oc/pkg/version.versionFromGit=${version} \
-X github.com/openshift/oc/pkg/version.commitFromGit=${commit} \
-X github.com/openshift/oc/pkg/version.gitTreeState=clean \
-X github.com/openshift/oc/pkg/version.buildDate=$(build_date) \
-X k8s.io/component-base/version.gitVersion=${kube_semver} \
-X k8s.io/component-base/version.gitCommit=${commit} \
-X k8s.io/component-base/version.buildDate=$(build_date) \
-X k8s.io/component-base/version.gitTreeState=clean
EOF
}

# ----------------------------- Build (if no prebuilt) -------------------------
if [ "${goto_package}" != "true" ]; then
    # -------- kubectl (CGO=0) --------
    log "kubectl: version=${KUBECTL_VERSION}"
    git -c advice.detachedHead=false clone \
        --filter=blob:none --depth 1 --branch "${KUBECTL_VERSION}" \
        https://github.com/kubernetes/kubernetes.git "${WORKDIR}/k8s" || fail "kubectl: clone failed"

    if [ "${ARCH}" = "arm64" ]; then
        # Force cross-build via go build (skip make, which produces host-arch)
        (cd "${WORKDIR}/k8s" &&
            COMMIT="$(git rev-parse --short HEAD)" &&
            GOOS=linux GOARCH=arm64 CGO_ENABLED=0 \
                go build ${GOFLAGS} \
                -ldflags "$(kubectl_ldflags "${KUBECTL_VERSION}" "${COMMIT}")" \
                -o /opt/tools/bin/kubectl ./cmd/kubectl) || fail "kubectl: go build failed (arm64)"
    else
        # Native amd64: keep 'make WHAT=cmd/kubectl' with fallback
        if command -v make >/dev/null 2>&1; then
            if (cd "${WORKDIR}/k8s" && MAKEFLAGS="-j$(nproc)" make WHAT=cmd/kubectl >/dev/null 2>&1); then
                install -m0755 "${WORKDIR}/k8s/_output/bin/kubectl" /opt/tools/bin/kubectl
            else
                warn "kubectl: make WHAT=cmd/kubectl failed → fallback to go build"
                (cd "${WORKDIR}/k8s" &&
                    COMMIT="$(git rev-parse --short HEAD)" &&
                    CGO_ENABLED=0 \
                        go build ${GOFLAGS} \
                        -ldflags "$(kubectl_ldflags "${KUBECTL_VERSION}" "${COMMIT}")" \
                        -o /opt/tools/bin/kubectl ./cmd/kubectl) || fail "kubectl: go build failed"
            fi
        else
            warn "kubectl: make not available → go build path"
            (cd "${WORKDIR}/k8s" &&
                COMMIT="$(git rev-parse --short HEAD)" &&
                CGO_ENABLED=0 \
                    go build ${GOFLAGS} \
                    -ldflags "$(kubectl_ldflags "${KUBECTL_VERSION}" "${COMMIT}")" \
                    -o /opt/tools/bin/kubectl ./cmd/kubectl) || fail "kubectl: go build failed"
        fi
    fi
    rm -rf "${WORKDIR}/k8s"

    # -------- oc (CGO=1) --------
    log "oc: ref=${OCREF}"
    git -c advice.detachedHead=false clone \
        --filter=blob:none --depth 1 --branch "${OCREF}" \
        https://github.com/openshift/oc.git "${WORKDIR}/oc" || fail "oc: clone failed"

    HAS_GOMOD="no"
    [ -f "${WORKDIR}/oc/go.mod" ] && HAS_GOMOD="yes"

    # --- Security pin: Sigstore Fulcio from versions.json (CVE fix >= 1.8.3) ---
    if [ "${HAS_GOMOD}" = "yes" ] && [ -n "${FULCIO_VERSION}" ] && [ "${FULCIO_VERSION}" != "null" ]; then
        log "oc: pinning github.com/sigstore/fulcio to ${FULCIO_VERSION}"
        (
            cd "${WORKDIR}/oc" || exit 1
            GO111MODULE=on go get "github.com/sigstore/fulcio@${FULCIO_VERSION}" || fail "oc: go get fulcio@${FULCIO_VERSION} failed"
            GO111MODULE=on go mod tidy || fail "oc: go mod tidy failed"
            GO111MODULE=on go mod vendor || fail "oc: go mod vendor failed"

            # Assicurati di aver già fatto: go mod vendor
            FULCIO_VER_EXPECTED="v${FULCIO_VERSION#v}"
            SEL_VER="$(GO111MODULE=on GOWORK=off go list -m -mod=vendor -f '{{.Version}}' github.com/sigstore/fulcio 2>/dev/null || true)"

            if [ -z "${SEL_VER}" ]; then
                fail "oc: fulcio not found in vendor (go list -mod=vendor returned empty)"
            fi
            if [ "${SEL_VER}" != "${FULCIO_VER_EXPECTED}" ]; then
                fail "oc: fulcio version mismatch (vendor): got ${SEL_VER}, expected ${FULCIO_VER_EXPECTED}"
            fi

            log "oc: fulcio pinned (vendor) → ${SEL_VER}"
        )
    else
        log "oc: fulcio pin skipped (HAS_GOMOD=${HAS_GOMOD}, FULCIO_VERSION='${FULCIO_VERSION}')"
    fi

    # --- Build 'oc' SOLO con 'go build' (niente 'make oc') ---
    if [ "${ARCH}" = "arm64" ]; then
        log "oc (ARM64): cross-build via 'go build'"
        (
            cd "${WORKDIR}/oc" &&
                COMMIT="$(git rev-parse --short HEAD || echo unknown)" &&
                GO111MODULE=on CGO_ENABLED=1 \
                    go build \
                    -mod=mod \
                    -buildvcs=false \
                    -tags "include_gcs include_oss containers_image_openpgp" \
                    -ldflags "$(oc_ldflags "${OCREF}" "${COMMIT}") -linkmode=external -extldflags '-Wl,--gc-sections -Wl,--as-needed'" \
                    -o /opt/tools/bin/oc ./cmd/oc
        ) || fail "oc: go build failed (ARM64)"
    else
        log "oc (AMD64): native build via 'go build'"
        (
            cd "${WORKDIR}/oc" &&
                COMMIT="$(git rev-parse --short HEAD || echo unknown)" &&
                GO111MODULE=on CGO_ENABLED=1 \
                    go build ${GOFLAGS} -buildvcs=false \
                    -tags "include_gcs include_oss containers_image_openpgp gssapi" \
                    -ldflags "$(oc_ldflags "${OCREF}" "${COMMIT}") -linkmode=external -extldflags '-Wl,--gc-sections -Wl,--as-needed'" \
                    -o /opt/tools/bin/oc ./cmd/oc
        ) || fail "oc: go build failed (AMD64)"
    fi

    rm -rf "${WORKDIR}/oc"

    # -------- rancher (CGO=0) --------
    if [ -z "${RANCHER_VERSION}" ] || [ "${RANCHER_VERSION}" = "latest" ]; then
        RANCHER_VERSION="$(curl -fsSL https://api.github.com/repos/rancher/cli/releases/latest | jq -r '.tag_name' || true)"
        if [ -z "${RANCHER_VERSION}" ] || [ "${RANCHER_VERSION}" = "null" ]; then
            RANCHER_VERSION="$(git ls-remote --tags --refs https://github.com/rancher/cli.git | awk -F/ '{print $NF}' | sort -Vr | head -n1)"
        fi
    fi
    [ -n "${RANCHER_VERSION}" ] || fail "rancher: cannot resolve latest release tag"
    log "rancher: version=${RANCHER_VERSION}"

    git -c advice.detachedHead=false clone \
        --filter=blob:none --depth 1 --branch "${RANCHER_VERSION}" \
        https://github.com/rancher/cli.git "${WORKDIR}/rancher-cli" || fail "rancher: clone failed"
    (cd "${WORKDIR}/rancher-cli" &&
        CGO_ENABLED=0 go build ${GOFLAGS} -ldflags "-s -w" -o /opt/tools/bin/rancher ./) || fail "rancher: build failed"
    rm -rf "${WORKDIR}/rancher-cli"
fi

# ----------------------------- Package Artifacts ------------------------------
PKG="/out/tools-${OS}-${ARCH}.tar.gz"
find /opt/tools/bin -type f -exec chmod 0755 {} \;
tar -C /opt/tools/bin -czf "${PKG}" kubectl oc rancher
log "Artifacts ready: ${PKG}"

# ----------------------------- Smoke Tests ------------------------------------
log "Smoke test: extracting and probing binaries"
SMOKE_DIR="$(mktemp -d)"
tar -xzf "${PKG}" -C "${SMOKE_DIR}"

# Presence & execute bit
for b in kubectl oc rancher; do
    if [ ! -x "${SMOKE_DIR}/${b}" ]; then
        fail "smoke: '${b}' missing or not executable"
    fi
done

# Helper: probe ELF/interpreter safely
probe_elf() {
    local bin_path="$1"
    if [ ! -e "${bin_path}" ]; then
        warn "ELF probe: '${bin_path}' does not exist"
        return 0
    fi
    log "---- ELF probe: ${bin_path} ----"
    if command -v file >/dev/null 2>&1; then
        file "${bin_path}" || true
    fi
    if command -v readelf >/dev/null 2>&1; then
        # Header (first lines)
        readelf -h "${bin_path}" | sed -n '1,30p' || true
        # Interpreter (program headers)
        readelf -l "${bin_path}" | grep -E 'Requesting program interpreter|interpreter' || true
    fi
}

# Helper: assert architecture
assert_arch() {
    local bin_path="$1"
    local expected="$2" # "AArch64" or "Advanced Micro Devices X86-64"
    if command -v readelf >/dev/null 2>&1; then
        if ! readelf -h "${bin_path}" | grep -qi "Machine:.*${expected}"; then
            fail "smoke: ${bin_path##*/} is not ${expected}"
        fi
    fi
}

if [ "${ARCH}" = "arm64" ]; then
    # Cross-arch: do NOT execute ARM64 binaries in amd64 builder.
    log "Smoke (ARM64): non-exec checks only (ELF headers & interpreter)"

    # Probe & assert architectures
    probe_elf "${SMOKE_DIR}/oc"
    assert_arch "${SMOKE_DIR}/oc" "AArch64"

    probe_elf "${SMOKE_DIR}/kubectl"
    assert_arch "${SMOKE_DIR}/kubectl" "AArch64" # kubectl deve essere arm64 nel pacchetto ARM

    probe_elf "${SMOKE_DIR}/rancher"
    assert_arch "${SMOKE_DIR}/rancher" "AArch64"

    # Interpreter tipico (dinamico) per oc
    if command -v readelf >/dev/null 2>&1; then
        if ! readelf -l "${SMOKE_DIR}/oc" | grep -q '/lib/ld-linux-aarch64.so.1'; then
            warn "smoke: oc interpreter does not reference /lib/ld-linux-aarch64.so.1 (OK if statically linked)"
        fi
    fi

    # Optional: check ldflags strings
    if command -v strings >/dev/null 2>&1; then
        strings "${SMOKE_DIR}/oc" | grep -E 'versionFromGit|buildDate' || true
    fi

    log "Smoke (ARM64): skip 'oc/kubectl/rancher' execution (foreign arch)"

else
    # Native arch (amd64): execute client versions
    log "Smoke: kubectl version (client)"
    KUBECTL_OUT="$("${SMOKE_DIR}/kubectl" version --client --output=yaml || true)"
    echo "${KUBECTL_OUT}"
    echo "${KUBECTL_OUT}" | grep -q 'gitVersion:' || fail "smoke: kubectl gitVersion missing"

    log "Smoke: oc version (client)"
    OC_OUT="$("${SMOKE_DIR}/oc" version --client || true)"
    echo "${OC_OUT}"
    echo "${OC_OUT}" | grep -q 'Client Version:' || fail "smoke: oc client version missing"

    log "Smoke: rancher --version (fallback --help)"
    if ! "${SMOKE_DIR}/rancher" --version >/dev/null 2>&1; then
        "${SMOKE_DIR}/rancher" --help >/dev/null 2>&1 || fail "smoke: rancher help failed"
    fi
fi

log "Smoke test passed ✔"
