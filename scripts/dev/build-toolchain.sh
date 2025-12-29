#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Script Name : build-toolchain.sh
# Description : Local test script - ARM64 cross-build followed by AMD64 native build.
#               Writes artifacts to <repo_root>/out, mirroring the CI pipeline order.
# Author      : Lorenzo Biosa - lorenzo@biosa-labs.com
# -----------------------------------------------------------------------------
set -euo pipefail

# --- Resolve repository root --------------------------------------------------
if REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    : # REPO_ROOT from git
else
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
fi

# --- Config -------------------------------------------------------------------
BUILDER_IMAGE="localhost/container-toolchain-builder:latest" # change to GHCR if needed
GO_VERSION="1.25.5"

# --- Prepare output dir -------------------------------------------------------
mkdir -p "${REPO_ROOT}/out"

echo "[local] Repo root: ${REPO_ROOT}"
echo "[local] Builder image: ${BUILDER_IMAGE}"
echo "[local] Go version: ${GO_VERSION}"

# -----------------------------------------------------------------------------
# ARM64 (cross) — CGO with Clang+LLD and builder's ARM64 sysroot
# -----------------------------------------------------------------------------
echo "============================================================"
echo "[local] ▶ Starting ARM64 cross-build"
echo "============================================================"

podman run -u 0 --rm --platform=linux/amd64 \
    -v "${REPO_ROOT}/out:/out" \
    -v "${REPO_ROOT}/build:/build" \
    "${BUILDER_IMAGE}" \
    bash -lc '
    set -euo pipefail

    # Configure Go target and enable CGO
    export GOOS=linux GOARCH=arm64 CGO_ENABLED=1

    # Cross toolchain: clang/clang++ + lld
    export CC=clang
    export CXX=clang++
    export AR=llvm-ar
    export LD=ld.lld

    # Sysroot and pkg-config for aarch64
    export PKG_CONFIG_SYSROOT_DIR=/opt/sysroot/arm64
    export PKG_CONFIG_LIBDIR=/opt/sysroot/arm64/usr/lib64/pkgconfig:/opt/sysroot/arm64/usr/lib/pkgconfig

    # CGO flags (Clang cross)
    export CGO_CFLAGS="--target=aarch64-linux-gnu --sysroot=/opt/sysroot/arm64"
    export CGO_LDFLAGS="--target=aarch64-linux-gnu --sysroot=/opt/sysroot/arm64 -fuse-ld=lld"

    # Avoid ccache overriding compiler selection
    export CCACHE_DISABLE=1

    # Kick off the build: kubectl (CGO=0), oc (CGO=1 with cross tags), rancher (CGO=0)
    bash /build/build-tools.sh linux arm64 '"$GO_VERSION"'
  '

ARM_ART="${REPO_ROOT}/out/tools-linux-arm64.tar.gz"
if [[ -f "$ARM_ART" ]]; then
    echo "[local] ✅ ARM64 artifact ready: $ARM_ART"
else
    echo "[local][ERROR] ARM64 artifact missing: expected $ARM_ART" >&2
    exit 1
fi

# -----------------------------------------------------------------------------
# AMD64 (native) — CGO for oc (gcc/g++) and pure-Go for others
# -----------------------------------------------------------------------------
echo "============================================================"
echo "[local] ▶ Starting AMD64 native build"
echo "============================================================"

podman run -u 0 --rm --platform=linux/amd64 \
    -v "${REPO_ROOT}/out:/out" \
    -v "${REPO_ROOT}/build:/build" \
    "${BUILDER_IMAGE}" \
    bash -lc '
    set -euo pipefail

    # Native target amd64
    export GOOS=linux
    export GOARCH=amd64
    export CGO_ENABLED=1

    # Native compiler for oc
    export CC=gcc
    export CXX=g++

    # Build toolchain (kubectl CGO=0, oc CGO=1 full tags, rancher CGO=0)
    bash /build/build-tools.sh linux amd64 '"$GO_VERSION"'
  '

AMD_ART="${REPO_ROOT}/out/tools-linux-amd64.tar.gz"
if [[ -f "$AMD_ART" ]]; then
    echo "[local] ✅ AMD64 artifact ready: $AMD_ART"
else
    echo "[local][ERROR] AMD64 artifact missing: expected $AMD_ART" >&2
    exit 1
fi

# -----------------------------------------------------------------------------
# Final summary
# -----------------------------------------------------------------------------
echo "============================================================"
echo "[local] ▶ Build summary"
echo "ARM64 → ${ARM_ART}"
echo "AMD64 → ${AMD_ART}"
echo "============================================================"
echo "[local] ✅ All done."
