# syntax=docker/dockerfile:1.7
FROM registry.access.redhat.com/ubi9/ubi:latest

LABEL org.opencontainers.image.title="container-toolchain builder" \
    org.opencontainers.image.vendor="Lorenzo Biosa" \
    org.opencontainers.image.source="https://github.com/lorenzobiosa/container-toolchain"

# ------------------------------------------------------------------------------
# Base toolchain + LLD + dnf plugins
# ------------------------------------------------------------------------------
RUN set -euo pipefail; \
    echo ">>> Enable EPEL and update system"; \
    rpm -Uvh https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm; \
    yum -y --disablerepo='epel*' update; \
    yum -y --disablerepo='epel*' upgrade; \
    echo ">>> Install core development tools (UBI)"; \
    dnf -y --disablerepo='epel*' install \
    ca-certificates \
    make gcc gcc-c++ glibc-devel glibc-headers \
    gpgme-devel libassuan-devel krb5-devel \
    jq git tar xz gzip gnupg2 \
    clang llvm lld binutils \
    pkgconf pkgconf-pkg-config \
    rpm-build rpmdevtools cpio \
    dnf-plugins-core \
    --setopt=install_weak_deps=0 --nodocs; \
    echo ">>> Install ccache from EPEL"; \
    dnf -y --enablerepo='epel*' install ccache --setopt=install_weak_deps=0 --nodocs; \
    dnf config-manager --disable epel || true; \
    echo ">>> Prepare ARM64 sysroot"; \
    SYSROOT="/opt/sysroot/arm64"; \
    mkdir -p "$SYSROOT" /tmp/rpms; \
    \
    # Scarica RPM aarch64 necessari per lo sysroot (glibc + librerie + GCC runtime/start files)
    dnf download --forcearch=aarch64 --arch=aarch64 --resolve --alldeps \
    glibc glibc-devel \
    gpgme gpgme-devel \
    libassuan libassuan-devel \
    krb5-libs krb5-devel \
    libgcc gcc \
    libstdc++ libstdc++-devel \
    --destdir /tmp/rpms; \
    \
    echo ">>> Extract RPMs into sysroot"; \
    for rpm in /tmp/rpms/*.rpm; do \
    rpm2cpio "$rpm" | (cd "$SYSROOT" && cpio -idmv); \
    done; \
    \
    # Trova la directory GCC del target (contiene crtbegin/crtend) e crea symlink in usr/lib
    echo ">>> Link GCC start files (crtbegin/crtend) into sysroot usr/lib"; \
    GCC_DIR="$(find "$SYSROOT/usr/lib/gcc" -maxdepth 3 -type d -name 'aarch64*linux*' | head -n1 || true)"; \
    if [ -n "$GCC_DIR" ]; then \
    for f in crtbegin.o crtbeginS.o crtbeginT.o crtend.o crtendS.o; do \
    SRC="$(find "$GCC_DIR" -maxdepth 2 -type f -name "$f" | head -n1 || true)"; \
    [ -n "$SRC" ] && ln -sf "$(realpath --no-symlinks "$SRC")" "$SYSROOT/usr/lib/$f" || true; \
    done; \
    else \
    echo ">>> WARN: GCC_DIR not found under $SYSROOT/usr/lib/gcc (start files may be missing)"; \
    fi; \
    \
    # Compattta e pubblica lo sysroot
    echo ">>> Pack ARM64 sysroot tarball"; \
    tar -C "$SYSROOT" -czf /opt/sysroot/sysroot-arm64.tar.gz .; \
    \
    echo ">>> Cleanup temporary files"; \
    rm -rf /tmp/rpms; \
    dnf -y clean all; \
    rm -rf /var/cache/dnf /var/cache/yum /var/tmp/*

# ------------------------------------------------------------------------------
# Prebuilt stash and output directories
# ------------------------------------------------------------------------------
RUN mkdir -p /opt/prebuilt/linux-amd64 /opt/prebuilt/linux-arm64 /out

# ------------------------------------------------------------------------------
# Working directory
# ------------------------------------------------------------------------------
WORKDIR /workspace

# ------------------------------------------------------------------------------
# Default CMD
# ------------------------------------------------------------------------------
CMD ["/bin/bash", "-lc", "echo 'builder ready'"]
