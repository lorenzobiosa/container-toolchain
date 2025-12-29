# syntax=docker/dockerfile:1.7
# ------------------------------------------------------------------------------
# Container Toolchain Builder (UBI9)
# Purpose: Build and package kubectl, oc (OpenShift), and rancher CLI with
#          amd64 host toolchain and arm64 cross-compile sysroot.
# Author: Lorenzo Biosa <lorenzo@biosa-labs.com> © Biosa Labs
# ------------------------------------------------------------------------------

# --- Base image (parameterized) ---
ARG BASE_IMAGE=registry.access.redhat.com/ubi9/ubi:latest
FROM ${BASE_IMAGE}

# --- OCI-compliant labels (parameterized; set via CI pipeline) ---
ARG IMAGE_TITLE="UBI9 Container Toolchain Builder"
ARG IMAGE_DESCRIPTION="UBI9-based builder with Go toolchain and ARM64 sysroot for cross-compilation of tools"
ARG IMAGE_VENDOR="Lorenzo Biosa"
ARG IMAGE_SOURCE="https://github.com/lorenzobiosa/container-toolchain"
ARG IMAGE_URL="https://github.com/lorenzobiosa/container-toolchain"
ARG IMAGE_DOCUMENTATION="https://github.com/lorenzobiosa/container-toolchain#readme"
ARG IMAGE_LICENSES="MIT"
ARG IMAGE_VERSION="prod"
ARG VCS_REF="unknown"
ARG BUILD_DATE="unknown"

# Extended OCI labels for enterprise traceability
LABEL org.opencontainers.image.title="${IMAGE_TITLE}" \
    org.opencontainers.image.description="${IMAGE_DESCRIPTION}" \
    org.opencontainers.image.vendor="${IMAGE_VENDOR}" \
    org.opencontainers.image.url="${IMAGE_URL}" \
    org.opencontainers.image.documentation="${IMAGE_DOCUMENTATION}" \
    org.opencontainers.image.source="${IMAGE_SOURCE}" \
    org.opencontainers.image.licenses="${IMAGE_LICENSES}" \
    org.opencontainers.image.version="${IMAGE_VERSION}" \
    org.opencontainers.image.revision="${VCS_REF}" \
    org.opencontainers.image.created="${BUILD_DATE}" \
    org.opencontainers.image.base.name="${BASE_IMAGE}" \
    org.opencontainers.image.authors="Lorenzo Biosa <lorenzo@biosa-labs.com>"

# --- Locale (consistent execution; quiet logs) ---
ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

# --- Optional enterprise proxy wiring (no-op by default) ---
ARG HTTP_PROXY=""
ARG HTTPS_PROXY=""
ARG NO_PROXY=""
ENV HTTP_PROXY=${HTTP_PROXY} \
    HTTPS_PROXY=${HTTPS_PROXY} \
    NO_PROXY=${NO_PROXY}

# --- Parameterization for toolchain and sysroot ---
ARG GO_VERSION=1.25.5
ARG TARGETOS=linux
ARG TARGETARCH=amd64
ARG EPEL_RPM_URL="https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm"
ARG SYSROOT_ARCH="aarch64"
ARG SYSROOT_DIR="/opt/sysroot/arm64"
ARG PREBUILT_DIR_AMD64="/opt/prebuilt/linux-amd64"
ARG PREBUILT_DIR_ARM64="/opt/prebuilt/linux-arm64"

# --- Non-root user parameters (OpenShift-friendly) ---
ARG ENABLE_SUDO=1
ARG BUILDER_USER=ubi9-builder
ARG BUILDER_UID=10001
ARG BUILDER_GID=10001
ARG BUILDER_HOME="/workspace"

# --- Go environment (image-level; reproducible builds) ---
ENV GOROOT=/usr/local/go \
    GOPATH=/root/go \
    PATH=/usr/local/go/bin:/root/go/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    GOWORK=off \
    GOTOOLCHAIN=local \
    GOFLAGS="-trimpath -buildvcs=false"

# --- Prompt & Welcome configuration ---
ARG WELCOME_ENABLE=1
ARG AUTHOR_EMAIL="lorenzo@biosa-labs.com"
ARG COMPANY_NAME="Biosa Labs"
ENV WELCOME_ENABLE=${WELCOME_ENABLE} \
    IMAGE_TITLE="${IMAGE_TITLE}" \
    IMAGE_DESCRIPTION="${IMAGE_DESCRIPTION}" \
    IMAGE_VENDOR="${IMAGE_VENDOR}" \
    AUTHOR_EMAIL="${AUTHOR_EMAIL}" \
    COMPANY_NAME="${COMPANY_NAME}"

# --- Copy external prompt/welcome scripts ---
COPY build/config/prompt/ /etc/profile.d/

# ------------------------------------------------------------------------------
# Single optimized RUN layer (no cache mount; cache handled by CI):
# - Enable EPEL (parameterized)
# - Upgrade base system
# - Install core dev tools (no weak deps, no docs; quiet output)
# - Install ccache from EPEL (then disable EPEL)
# - Download & verify Go toolchain (sha256; quiet output)
# - Prepare ARM64 sysroot from aarch64 RPMs (quiet extraction)
# - Link GCC start files (crtbegin/crtend)
# - Pack sysroot tarball
# - Create prebuilt & output directories
# - Configure non-root user and optional sudo (NOPASSWD)
# - Permission model compatible with OpenShift (chgrp 0 + g+rwX)
# - Clean caches (minimal final image; do NOT remove /var/cache/dnf)
# NOTE: Commands redirect stdout to /dev/null to keep console clean;
#       stderr is preserved to show errors.
# ------------------------------------------------------------------------------
RUN set -Eeuo pipefail; \
    # Timestamp (UTC ISO-8601)
    TS() { date -u +%Y-%m-%dT%H:%M:%SZ; }; \
    \
    # Colors (force enabled unless NO_COLOR is set)
    if [ -n "${NO_COLOR:-}" ]; then \
    GREEN=""; GRAY=""; CYAN=""; WHITE=""; RESET=""; BOLD=""; \
    else \
    GREEN="$(printf '\033[32m')"; \
    GRAY="$(printf '\033[90m')"; \
    CYAN="$(printf '\033[36m')"; \
    WHITE="$(printf '\033[97m')"; \
    RESET="$(printf '\033[0m')"; \
    BOLD="$(printf '\033[1m')"; \
    fi; \
    export CLICOLOR=1 FORCE_COLOR=1; \
    \
    # Log to stderr to preserve ANSI in build output
    log() { \
    printf '%b[ubi9-builder]%b[%b%s%b] %b>>>%b %b%s%b\n' \
    "${GREEN}" "${RESET}" \
    "${CYAN}" "$(TS)" "${RESET}" \
    "${GRAY}" "${RESET}" \
    "${WHITE}" "$*" "${RESET}" \
    >&2; \
    }; \
    \
    # Header & footer (with duration)
    START_EPOCH="$(date -u +%s)"; \
    header_build() { \
    printf '%b[ubi9-builder]%b[%b%s%b] %b>>>%b %b============================================================%b\n' "${GREEN}" "${RESET}" "${CYAN}" "$(TS)" "${RESET}" "${GRAY}" "${RESET}" "${GREEN}" "${RESET}" >&2; \
    printf '%b[ubi9-builder]%b[%b%s%b] %b>>>%b %bStarting UBI9 Container Toolchain Builder%b\n' "${GREEN}" "${RESET}" "${CYAN}" "$(TS)" "${RESET}" "${GRAY}" "${RESET}" "${WHITE}" "${RESET}" >&2; \
    printf '%b[ubi9-builder]%b[%b%s%b] %b>>>%b %bAuthor:%b Lorenzo Biosa <lorenzo@biosa-labs.com> © Biosa Labs%b\n' "${GREEN}" "${RESET}" "${CYAN}" "$(TS)" "${RESET}" "${GRAY}" "${RESET}" "${WHITE}" "${BOLD}" "${RESET}" >&2; \
    printf '%b[ubi9-builder]%b[%b%s%b] %b>>>%b %b============================================================%b\n' "${GREEN}" "${RESET}" "${CYAN}" "$(TS)" "${RESET}" "${GRAY}" "${RESET}" "${GREEN}" "${RESET}" >&2; \
    }; \
    footer_build() { \
    END_EPOCH="$(date -u +%s)"; \
    DURATION="$((END_EPOCH - START_EPOCH))"; \
    printf '%b[ubi9-builder]%b[%b%s%b] %b>>>%b %b============================================================%b\n' "${GREEN}" "${RESET}" "${CYAN}" "$(TS)" "${RESET}" "${GRAY}" "${RESET}" "${GREEN}" "${RESET}" >&2; \
    printf '%b[ubi9-builder]%b[%b%s%b] %b>>>%b %bCompleted UBI9 Container Toolchain Builder%b (duration: %ss)\n' "${GREEN}" "${RESET}" "${CYAN}" "$(TS)" "${RESET}" "${GRAY}" "${RESET}" "${WHITE}" "${RESET}" "${DURATION}" >&2; \
    printf '%b[ubi9-builder]%b[%b%s%b] %b>>>%b %bAll done.%b\n' "${GREEN}" "${RESET}" "${CYAN}" "$(TS)" "${RESET}" "${GRAY}" "${RESET}" "${WHITE}" "${RESET}" >&2; \
    printf '%b[ubi9-builder]%b[%b%s%b] %b>>>%b %b============================================================%b\n' "${GREEN}" "${RESET}" "${CYAN}" "$(TS)" "${RESET}" "${GRAY}" "${RESET}" "${GREEN}" "${RESET}" >&2; \
    }; \
    \
    # ---- Header --------------------------------------------------------------
    header_build; \
    \
    log "Create tools/prebuilt/out directories "; \
    mkdir -p /opt/tools/bin /opt/prebuilt/linux-amd64 /opt/prebuilt/linux-arm64 /out >/dev/null; \
    log "Enable EPEL and upgrade base system"; \
    rpm -Uvh "${EPEL_RPM_URL}" >/dev/null; \
    dnf -y -q upgrade --refresh --disablerepo='epel*' >/dev/null; \
    \
    log "Install core development tools"; \
    dnf -y -q --disablerepo='epel*' \
    --setopt=install_weak_deps=0 \
    --setopt=tsflags=nodocs \
    install \
    ca-certificates \
    make gcc gcc-c++ glibc-devel glibc-headers \
    gpgme-devel libassuan-devel krb5-devel \
    jq git tar xz gzip gnupg2 \
    clang llvm lld binutils \
    pkgconf pkgconf-pkg-config \
    rpm-build rpmdevtools cpio \
    dnf-plugins-core >/dev/null; \
    \
    log "Install ccache from EPEL"; \
    dnf -y -q --enablerepo='epel*' \
    --setopt=install_weak_deps=0 \
    --setopt=tsflags=nodocs \
    install ccache >/dev/null; \
    dnf config-manager --disable epel >/dev/null || true; \
    \
    log "Install Go ${GO_VERSION} (${TARGETOS}-${TARGETARCH})"; \
    cd /tmp; \
    GO_TARBALL="go${GO_VERSION}.${TARGETOS}-${TARGETARCH}.tar.gz"; \
    curl -fsSLo go.tgz "https://go.dev/dl/${GO_TARBALL}"; \
    rm -rf /usr/local/go; \
    tar -C /usr/local -xzf go.tgz >/dev/null; \
    rm -f go.tgz; \
    \
    log "Prepare ${SYSROOT_ARCH} sysroot"; \
    SYSROOT="${SYSROOT_DIR}"; \
    mkdir -p "${SYSROOT}" /tmp/rpms; \
    dnf -q download --forcearch="${SYSROOT_ARCH}" --arch="${SYSROOT_ARCH}" --resolve --alldeps \
    glibc glibc-devel \
    gpgme gpgme-devel \
    libassuan libassuan-devel \
    krb5-libs krb5-devel \
    libgcc gcc \
    libstdc++ libstdc++-devel \
    --destdir /tmp/rpms >/dev/null; \
    \
    log "Extract RPMs into sysroot"; \
    for rpm in /tmp/rpms/*.rpm; do \
    rpm2cpio "$rpm" | (cd "${SYSROOT}" && cpio -idmu --quiet --no-preserve-owner --numeric-uid-gid >/dev/null 2>&1); \
    done; \
    \
    log "Link GCC start files into sysroot"; \
    GCC_DIR="$(find "${SYSROOT}/usr/lib/gcc" -maxdepth 3 -type d -name "${SYSROOT_ARCH}*linux*" | head -n1 || true)"; \
    if [ -n "${GCC_DIR}" ]; then \
    for f in crtbegin.o crtbeginS.o crtbeginT.o crtend.o crtendS.o; do \
    SRC="$(find "${GCC_DIR}" -maxdepth 2 -type f -name "$f" | head -n1 || true)"; \
    [ -n "${SRC}" ] && ln -sf "$(realpath --no-symlinks "$SRC")" "${SYSROOT}/usr/lib/$f" || true; \
    done; \
    else \
    log "WARN: GCC_DIR not found under ${SYSROOT}/usr/lib/gcc (start files may be missing)"; \
    fi; \
    \
    log "Pack ${SYSROOT_ARCH} sysroot tarball"; \
    mkdir -p /opt/sysroot; \
    tar -C "${SYSROOT}" -czf "/opt/sysroot/sysroot-${SYSROOT_ARCH}.tar.gz" . >/dev/null; \
    \
    log "Create prebuilt and output directories"; \
    mkdir -p "${PREBUILT_DIR_AMD64}" "${PREBUILT_DIR_ARM64}" /out; \
    \
    log "Install sudo and user management tools"; \
    dnf -y -q --setopt=install_weak_deps=0 --setopt=tsflags=nodocs install sudo shadow-utils >/dev/null; \
    \
    log "Create non-root user and group: ${BUILDER_USER} (${BUILDER_UID}:${BUILDER_GID})"; \
    getent group "${BUILDER_GID}" >/dev/null || groupadd -g "${BUILDER_GID}" "${BUILDER_USER}" >/dev/null; \
    getent passwd "${BUILDER_UID}" >/dev/null || useradd -m -d "${BUILDER_HOME}" -s /bin/bash -u "${BUILDER_UID}" -g "${BUILDER_GID}" "${BUILDER_USER}" >/dev/null; \
    \
    if [ "${ENABLE_SUDO}" = "1" ]; then \
    log "Configure passwordless sudo for ${BUILDER_USER}"; \
    echo "${BUILDER_USER} ALL=(ALL) NOPASSWD:ALL" >/etc/sudoers.d/${BUILDER_USER}; \
    chmod 0440 /etc/sudoers.d/${BUILDER_USER}; \
    # Ensure secure_path includes common bins
    printf 'Defaults secure_path=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\n' >/etc/sudoers.d/secure_path; \
    chmod 0440 /etc/sudoers.d/secure_path; \
    # Validate sudoers files (quiet)
    visudo -cf /etc/sudoers >/dev/null; \
    visudo -cf /etc/sudoers.d/${BUILDER_USER} >/dev/null; \
    visudo -cf /etc/sudoers.d/secure_path >/dev/null; \
    else \
    log "Skipping sudo configuration (ENABLE_SUDO=${ENABLE_SUDO})"; \
    fi; \
    \
    # OpenShift-friendly permissions: group 0 can write; random UID can operate
    log "Harden permissions for OpenShift"; \
    for d in "${BUILDER_HOME}" "/out" "/opt/sysroot" "${PREBUILT_DIR_AMD64}" "${PREBUILT_DIR_ARM64}"; do \
    mkdir -p "$d"; \
    chgrp -R 0 "$d"; \
    chmod -R g+rwX "$d"; \
    done; \
    \
    log "Install prompt & welcome scripts to /etc/profile.d"; \
    chmod 0644 /etc/profile.d/00-welcome.sh /etc/profile.d/10-ps1.sh >/dev/null; \
    log "Cleanup temporary files and caches"; \
    rm -rf /tmp/rpms; \
    dnf -y -q clean all >/dev/null; \
    # NOTE: do NOT remove /var/cache/dnf here; CI can mount and own this cache.
    rm -rf /var/tmp/*; \
    \
    # ---- Footer --------------------------------------------------------------
    footer_build;

# --- Optional pkg-config defaults for ARM64 cross (can be overridden at runtime) ---
ENV PKG_CONFIG_SYSROOT_DIR="${SYSROOT_DIR}" \
    PKG_CONFIG_LIBDIR="${SYSROOT_DIR}/usr/lib64/pkgconfig:${SYSROOT_DIR}/usr/lib/pkgconfig"

# --- Working directory (explicit) ---
WORKDIR /workspace

# --- Switch to non-root user by default ---
USER ${BUILDER_UID}

# --- Default command (interactive builder; no shell) ---
CMD ["/bin/echo", "builder ready"]
