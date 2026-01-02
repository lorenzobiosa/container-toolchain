
#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Script Name : build-tools.sh
# Description : Builds (amd64/arm64) toolchain artifacts inside UBI builder.
# Author      : Lorenzo Biosa - lorenzo@biosa-labs.com
# -----------------------------------------------------------------------------
set -Eeuo pipefail

# ----------------------------- Logging & Errors -------------------------------
log()  { printf '[build] %s\n' "$*"; }
warn() { printf '[build][WARN] %s\n' "$*" >&2; }
fail() { printf '[build][ERROR] %s\n' "$*" >&2; exit 1; }
trap 'fail "unhandled error at line $LINENO"' ERR

# ----------------------------- Inputs & Defaults ------------------------------
# Positional (legacy): OS, ARCH, GO_VERSION_INPUT
OS="${1:-linux}"
ARCH_DEFAULT="${2:-amd64}"
GO_VERSION_INPUT="${3:-}"

# New: comma-separated target list (e.g., "amd64,arm64"); falls back to ARCH_DEFAULT.
TARGETS="${BUILD_TARGETS}"

# ----------------------------- Workspace & Cleanup ----------------------------
WORKDIR="$(mktemp -d)"
SMOKE_DIR=""
cleanup() {
  rm -rf "${WORKDIR}" || true
  [ -n "${SMOKE_DIR}" ] && rm -rf "${SMOKE_DIR}" || true
}
trap cleanup EXIT

# ----------------------------- Common Dependencies ----------------------------
for cmd in git jq make gcc g++ tar xz gzip; do
  command -v "$cmd" >/dev/null 2>&1 || fail "missing dependency: $cmd"
done
command -v go >/dev/null 2>&1 || fail "missing dependency: go (preinstalled in image)"

# ----------------------------- Version Pins (optional) ------------------------
VERSIONS_JSON="/usr/local/share/tool-versions.json"
KUBECTL_VERSION_PIN=""; OCREF_PIN=""; RANCHER_VERSION_PIN=""; FULCIO_VERSION_PIN=""; GO_VERSION_PIN=""
if [ -f "${VERSIONS_JSON}" ]; then
  KUBECTL_VERSION_PIN="$(jq -r '.kubectl // empty' "${VERSIONS_JSON}")"
  OCREF_PIN="$(jq -r '.oc // empty' "${VERSIONS_JSON}")"
  RANCHER_VERSION_PIN="$(jq -r '.rancher // empty' "${VERSIONS_JSON}")"
  FULCIO_VERSION_PIN="$(jq -r '.fulcio // empty' "${VERSIONS_JSON}")"
  GO_VERSION_PIN="$(jq -r '.go // empty' "${VERSIONS_JSON}")"
fi
KUBECTL_VERSION="${KUBECTL_VERSION_OVERRIDE:-${KUBECTL_VERSION_PIN:-}}"
OCREF="${OCREF_OVERRIDE:-${OCREF_PIN:-}}"
RANCHER_VERSION="${RANCHER_VERSION_OVERRIDE:-${RANCHER_VERSION_PIN:-}}"
FULCIO_VERSION="${FULCIO_VERSION_OVERRIDE:-${FULCIO_VERSION_PIN:-}}"
GO_VERSION="${GO_VERSION_INPUT:-${GO_VERSION_PIN:-}}"
log "Pins → kubectl=${KUBECTL_VERSION}, oc=${OCREF}, rancher=${RANCHER_VERSION:-<latest>}, fulcio=${FULCIO_VERSION}, go=${GO_VERSION:-<from-image>}"

# ----------------------------- Helper ldflags ---------------------------------
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
derive_kube_semver() {
  local ref="$1"
  if [[ "$ref" =~ ^v([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then echo "$ref"; return 0; fi
  if [[ "$ref" =~ ^release-([0-9]+)\.([0-9]+)$ ]]; then echo "v${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.0"; return 0; fi
  echo "v0.0.0"
}
oc_ldflags() {
  local version="$1" commit="$2"
  local kube_semver; kube_semver="$(derive_kube_semver "${version}")"
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

# ----------------------------- Build per-target -------------------------------
for ARCH in $(printf '%s' "${BUILD_TARGETS}" | tr ',' ' '); do
  log "==== Building target: OS=${OS} ARCH=${ARCH} ===="

  # Prepare output paths
  mkdir -p /opt/tools/bin /out

  # ccache (optional) and Go env
  : "${GOMAXPROCS:=$(nproc)}"; export GOMAXPROCS
  : "${GOFLAGS:=${GOFLAGS:-} -trimpath -buildvcs=false}"; export GOFLAGS
  export GOWORK="${GOWORK:-off}"
  export GOOS="${OS}" GOARCH="${ARCH}" GOTOOLCHAIN="${GOTOOLCHAIN:-local}"

  # --- Per-target environment reset to avoid leakage across arch builds
  unset CC CXX AR LD
  unset CGO_ENABLED CGO_CFLAGS CGO_CFLAGS_ALLOW CGO_LDFLAGS
  unset PKG_CONFIG_SYSROOT_DIR PKG_CONFIG_LIBDIR

  # Compiler & pkg-config setup per-arch
  if [ "${ARCH}" = "arm64" ]; then
    # Ensure clang/ld.lld are present in builder
    command -v clang  >/dev/null 2>&1 || fail "missing dependency: clang"
    command -v ld.lld >/dev/null 2>&1 || fail "missing dependency: ld.lld (LLD)"

    # Sysroot (coerente con Dockerfile) e pkg-config per aarch64
    export PKG_CONFIG_SYSROOT_DIR="${SYSROOT_ARM64:-/opt/sysroot/aarch64}"
    export PKG_CONFIG_LIBDIR="${PKG_CONFIG_SYSROOT_DIR}/usr/lib64/pkgconfig:${PKG_CONFIG_SYSROOT_DIR}/usr/lib/pkgconfig"

    # C compiler cross (clang) e linker esterno (lld) con target+sysroot
    export CC="clang --target=${LLVM_TRIPLE_ARM64} --sysroot=${PKG_CONFIG_SYSROOT_DIR}"
    export CXX="clang++ --target=${LLVM_TRIPLE_ARM64} --sysroot=${PKG_CONFIG_SYSROOT_DIR}"
    export AR="llvm-ar"; 
    export LD="ld.lld"
    export CGO_ENABLED=1

    # Flags cgo espliciti (header e lib del sysroot)
    export CGO_CFLAGS="--sysroot=${PKG_CONFIG_SYSROOT_DIR} -I${PKG_CONFIG_SYSROOT_DIR}/usr/include -Wno-error=unused-command-line-argument"
    export CGO_CFLAGS_ALLOW='-Wno-error=unused-command-line-argument'
    export CGO_LDFLAGS="--sysroot=${PKG_CONFIG_SYSROOT_DIR} -L${PKG_CONFIG_SYSROOT_DIR}/usr/lib64 -L${PKG_CONFIG_SYSROOT_DIR}/usr/lib"
  else
    # Native amd64: cgo OK, GSSAPI requires krb5-devel headers (already installed in image)
    export CGO_ENABLED=1
    # If ccache is available, prefer it
    if command -v ccache >/dev/null 2>&1; then
      export CC="ccache gcc"; export CXX="ccache g++"
    else
      export CC="${CC:-gcc}"; export CXX="${CXX:-g++}"
    fi
  fi

  # ----------------------------- Fast-path: prebuilt --------------------------
  PREBUILT_DIR="/opt/prebuilt/linux-${ARCH}/bin"
  goto_package=false
  if [ -d "${PREBUILT_DIR}" ] && [ -f "${PREBUILT_DIR}/kubectl" ] && [ -f "${PREBUILT_DIR}/oc" ] && [ -f "${PREBUILT_DIR}/rancher" ]; then
    install -m0755 "${PREBUILT_DIR}/kubectl"  /opt/tools/bin/kubectl
    install -m0755 "${PREBUILT_DIR}/oc"       /opt/tools/bin/oc
    install -m0755 "${PREBUILT_DIR}/rancher"  /opt/tools/bin/rancher
    log "Using prebuilt binaries from ${PREBUILT_DIR}"
    goto_package=true
  fi

  if [ "${goto_package}" != "true" ]; then
    # -------- kubectl (CGO=0) --------
    log "kubectl: version=${KUBECTL_VERSION:-<branch default>}"
    git -c advice.detachedHead=false clone --filter=blob:none --depth 1 --branch "${KUBECTL_VERSION}" \
      https://github.com/kubernetes/kubernetes.git "${WORKDIR}/k8s" || fail "kubectl: clone failed"
    (
      cd "${WORKDIR}/k8s" && COMMIT="$(git rev-parse --short HEAD)"
      if [ "${ARCH}" = "arm64" ]; then
        GOOS=linux GOARCH=arm64 CGO_ENABLED=0 \
          go build ${GOFLAGS} -ldflags "$(kubectl_ldflags "${KUBECTL_VERSION}" "${COMMIT}")" \
          -o /opt/tools/bin/kubectl ./cmd/kubectl
      else
        # Prefer 'make WHAT=cmd/kubectl' then fallback to 'go build'
        if command -v make >/dev/null 2>&1 && MAKEFLAGS="-j$(nproc)" make WHAT=cmd/kubectl >/dev/null 2>&1; then
          install -m0755 "_output/bin/kubectl" /opt/tools/bin/kubectl
        else
          CGO_ENABLED=0 \
            go build ${GOFLAGS} -ldflags "$(kubectl_ldflags "${KUBECTL_VERSION}" "${COMMIT}")" \
            -o /opt/tools/bin/kubectl ./cmd/kubectl
        fi
      fi
    ) || fail "kubectl: build failed"
    rm -rf "${WORKDIR}/k8s"

    # -------- oc (CGO=1) --------
    log "oc: ref=${OCREF}"
    git -c advice.detachedHead=false clone --filter=blob:none --depth 1 --branch "${OCREF}" \
      https://github.com/openshift/oc.git "${WORKDIR}/oc" || fail "oc: clone failed"
    HAS_GOMOD="no"; [ -f "${WORKDIR}/oc/go.mod" ] && HAS_GOMOD="yes"

    if [ "${HAS_GOMOD}" = "yes" ] && [ -n "${FULCIO_VERSION}" ] && [ "${FULCIO_VERSION}" != "null" ]; then
      log "oc: pinning github.com/sigstore/fulcio to ${FULCIO_VERSION}"
      (
        cd "${WORKDIR}/oc"
        GO111MODULE=on go get "github.com/sigstore/fulcio@${FULCIO_VERSION}" || fail "fulcio pin failed"
        GO111MODULE=on go mod tidy && GO111MODULE=on go mod vendor
        FULCIO_VER_EXPECTED="v${FULCIO_VERSION#v}"
        SEL_VER="$(GO111MODULE=on GOWORK=off go list -m -mod=vendor -f '{{.Version}}' github.com/sigstore/fulcio 2>/dev/null || true)"
        [ -n "${SEL_VER}" ] || fail "fulcio not found in vendor"
        [ "${SEL_VER}" = "${FULCIO_VER_EXPECTED}" ] || fail "fulcio version mismatch: ${SEL_VER} != ${FULCIO_VER_EXPECTED}"
        log "oc: fulcio pinned (vendor) → ${SEL_VER}"
      )
    else
      log "oc: fulcio pin skipped (HAS_GOMOD=${HAS_GOMOD}, FULCIO_VERSION='${FULCIO_VERSION}')"
    fi


    # Assicura vendoring completo (silenzia build e rende deterministico)
    (
      cd "${WORKDIR}/oc"
      GO111MODULE=on go mod tidy
      GO111MODULE=on go mod vendor
    )


    (
      cd "${WORKDIR}/oc" && COMMIT="$(git rev-parse --short HEAD || echo unknown)"
      if [ "${ARCH}" = "arm64" ]; then
        # Cross-build with external link; pkg-config points to aarch64 sysroot
        export CGO_LDFLAGS="${CGO_LDFLAGS} -fuse-ld=lld -Wl,--gc-sections -Wl,--as-needed"
        GO111MODULE=on CGO_ENABLED=1 \
          go build -mod=mod -buildvcs=false \
          -tags "include_gcs include_oss containers_image_openpgp" \
          -ldflags "$(oc_ldflags "${OCREF}" "${COMMIT}") -linkmode=external" \
          -o /opt/tools/bin/oc ./cmd/oc
      else
         # Native amd64 build (GSSAPI enabled)
         unset PKG_CONFIG_SYSROOT_DIR PKG_CONFIG_LIBDIR
         export PKG_CONFIG_PATH="/usr/lib64/pkgconfig:/usr/share/pkgconfig:${PKG_CONFIG_PATH:-}"
         export CGO_LDFLAGS="${CGO_LDFLAGS:-} -Wl,--gc-sections -Wl,--as-needed"
         GO111MODULE=on CGO_ENABLED=1 \
           go build ${GOFLAGS} -mod=vendor -buildvcs=false \
           -tags "include_gcs include_oss containers_image_openpgp gssapi" \
           -ldflags "$(oc_ldflags "${OCREF}" "${COMMIT}") -linkmode=external" \
           -o /opt/tools/bin/oc ./cmd/oc
      fi
    ) || fail "oc: build failed"
    rm -rf "${WORKDIR}/oc"

    # -------- rancher (CGO=0) --------
    if [ -z "${RANCHER_VERSION}" ] || [ "${RANCHER_VERSION}" = "latest" ]; then
      RANCHER_VERSION="$(curl -fsSL https://api.github.com/repos/rancher/cli/releases/latest | jq -r '.tag_name' || true)"
      [ -n "${RANCHER_VERSION}" ] && [ "${RANCHER_VERSION}" != "null" ] || \
        RANCHER_VERSION="$(git ls-remote --tags --refs https://github.com/rancher/cli.git | awk -F/ '{print $NF}' | sort -Vr | head -n1)"
    fi
    [ -n "${RANCHER_VERSION}" ] || fail "rancher: cannot resolve latest release tag"
    log "rancher: version=${RANCHER_VERSION}"
    git -c advice.detachedHead=false clone --filter=blob:none --depth 1 --branch "${RANCHER_VERSION}" \
      https://github.com/rancher/cli.git "${WORKDIR}/rancher-cli" || fail "rancher: clone failed"
    (cd "${WORKDIR}/rancher-cli" && CGO_ENABLED=0 go build ${GOFLAGS} -ldflags "-s -w" -o /opt/tools/bin/rancher ./) \
      || fail "rancher: build failed"
    rm -rf "${WORKDIR}/rancher-cli"
  fi

  # ----------------------------- Package Artifacts ----------------------------
  PKG="/out/tools-${OS}-${ARCH}.tar.gz"
  find /opt/tools/bin -type f -exec chmod 0755 {} \;
  tar -C /opt/tools/bin -czf "${PKG}" kubectl oc rancher
  log "Artifacts ready: ${PKG}"

  # ----------------------------- Smoke Tests ----------------------------------
  log "Smoke test for ${ARCH}..."
  SMOKE_DIR="$(mktemp -d)"
  tar -xzf "${PKG}" -C "${SMOKE_DIR}"

  for b in kubectl oc rancher; do
    [ -x "${SMOKE_DIR}/${b}" ] || fail "smoke: '${b}' missing or not executable"
  done

  if [ "${ARCH}" = "arm64" ]; then
    log "Smoke (ARM64): ELF headers only"
    if command -v readelf >/dev/null 2>&1; then
      readelf -h "${SMOKE_DIR}/oc" | sed -n '1,30p' || true
      readelf -l "${SMOKE_DIR}/oc" | grep -E 'interpreter' || true
    fi
  else
    log "Smoke: kubectl/oc/rancher versions (amd64)"
    "${SMOKE_DIR}/kubectl" version --client --output=yaml >/dev/null 2>&1 || warn "kubectl version warn"
    "${SMOKE_DIR}/oc"      version --client >/dev/null 2>&1 || warn "oc version warn"
    "${SMOKE_DIR}/rancher" --version >/dev/null 2>&1 || "${SMOKE_DIR}/rancher" --help >/dev/null 2>&1 || warn "rancher help warn"
  fi

  rm -rf "${SMOKE_DIR}"
  log "Smoke test passed ✔ for ${ARCH}"

  # Clean per-target working area
  rm -rf /opt/tools/bin/*
done

log "All targets completed: ${TARGETS}"
