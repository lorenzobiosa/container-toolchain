# ------------------------------------------------------------------------------
# UBI Toolchain Builder (Multi-Architecture)
# ------------------------------------------------------------------------------
# Description : Deterministic builder for compiling CLI tools targeting 
#               linux/amd64 and linux/arm64 inside containers. Fully
#               parameterized via build args and environment variables.
# Author      : Lorenzo Biosa
# Organization: Biosa Labs
# Contact     : lorenzo@biosa-labs.com
# License     : MIT
# Notes       : Requires Docker BuildKit to use ARG in FROM and multi-arch builds.
# ------------------------------------------------------------------------------

# --- Base image
ARG BASE_IMAGE=""
FROM --platform=$BUILDPLATFORM ${BASE_IMAGE}

# --- Metadata and builder configuration
ARG IMAGE_TITLE="UBI Container Toolchain Builder"
ARG IMAGE_DESCRIPTION="Multi-arch builder (amd64/arm64) for CLI tools"
ARG IMAGE_VENDOR="Biosa Labs"
ARG IMAGE_AUTHOR="Lorenzo Biosa"
ARG AUTHOR_EMAIL="lorenzo@biosa-labs.com"
ARG IMAGE_LICENSES="MIT"
ARG IMAGE_SOURCE_URL="https://github.com/lorenzobiosa/container-toolchain"
ARG VCS_REF="unknown"
ARG BUILD_DATE="unknown"

# --- Toolchain & runtime configuration
ARG GOROOT="/usr/local/go"
ARG GOPATH="/opt/go"
ARG CC="clang"
ARG CXX="clang++"
ARG LD="ld.lld"
ARG CCACHE_SIZE="5.0G"
ARG BUILDER_USER="builder"
ARG BUILDER_UID="10001"
ARG BUILDER_GID="10001"
ARG BUILDER_HOME="/work"
ARG WELCOME_ENABLE="1"
ARG PROMPT_ENABLE_COLORS="1"

# --- Cross-compilation targets & sysroot layout
ARG BUILD_TARGETS="amd64,arm64"
ARG SYSROOT_DIR_BASE="/opt/sysroot"
ARG PREBUILT_DIR_AMD64="/opt/prebuilt/linux-amd64"
ARG PREBUILT_DIR_ARM64="/opt/prebuilt/linux-arm64"

# --- OCI labels
LABEL org.opencontainers.image.title="${IMAGE_TITLE}" \
    org.opencontainers.image.description="${IMAGE_DESCRIPTION}" \
    org.opencontainers.image.vendor="${IMAGE_VENDOR}" \
    org.opencontainers.image.authors="${IMAGE_AUTHOR} <${AUTHOR_EMAIL}>" \
    org.opencontainers.image.revision="${VCS_REF}" \
    org.opencontainers.image.licenses="${IMAGE_LICENSES}" \
    org.opencontainers.image.created="${BUILD_DATE}" \
    org.opencontainers.image.source="${IMAGE_SOURCE_URL}"

# --- Export env from args
ENV IMAGE_TITLE="${IMAGE_TITLE}" \
    IMAGE_DESCRIPTION="${IMAGE_DESCRIPTION}" \
    IMAGE_VENDOR="${IMAGE_VENDOR}" \
    IMAGE_AUTHOR="${IMAGE_AUTHOR}" \
    AUTHOR_EMAIL="${AUTHOR_EMAIL}" \
    LC_ALL=C.UTF-8 \
    LANG=C.UTF-8 \
    GOROOT=${GOROOT} \
    GOPATH=${GOPATH} \
    PATH=/usr/sbin:/usr/bin:/bin:/usr/local/bin:/usr/local/sbin:${GOROOT}/bin:${GOPATH}/bin \
    WELCOME_ENABLE=${WELCOME_ENABLE} \
    PROMPT_ENABLE_COLORS=${PROMPT_ENABLE_COLORS} \
    CC=${CC} \
    CXX=${CXX} \
    LD=${LD} \
    CCACHE_SIZE=${CCACHE_SIZE} \
    CCACHE_DIR=/opt/ccache \
    CCACHE_BASEDIR=/work \
    PKG_CONFIG_SYSROOT_DIR=/opt/sysroot/aarch64 \
    PKG_CONFIG_LIBDIR=/opt/sysroot/aarch64/usr/lib64/pkgconfig:/opt/sysroot/aarch64/usr/lib/pkgconfig \
    PKG_CONFIG_PATH=/usr/lib64/pkgconfig:/usr/share/pkgconfig \
    BUILDER_USER="builder" \
    BUILDER_UID="10001" \
    BUILDER_GID="10001" \
    BUILD_TARGETS="${BUILD_TARGETS}" \
    SYSROOT_DIR_BASE="${SYSROOT_DIR_BASE}" \
    PREBUILT_DIR_AMD64="${PREBUILT_DIR_AMD64}" \
    PREBUILT_DIR_ARM64="${PREBUILT_DIR_ARM64}" \
    LLVM_TRIPLE_AMD64="x86_64-unknown-linux-gnu" \
    LLVM_TRIPLE_ARM64="aarch64-unknown-linux-gnu" \
    SYSROOT_AMD64="${SYSROOT_DIR_BASE}/x86_64" \
    SYSROOT_ARM64="${SYSROOT_DIR_BASE}/aarch64"

# --- Scripts and configurations
COPY scripts/os/*.sh scripts/lib/*.sh /usr/local/bin/
COPY scripts/os/python-supported.txt /usr/local/share/python-supported.txt
COPY configs/prompt/ /etc/profile.d/
COPY build/build-tools.sh /usr/local/bin/
COPY build/config/tool-versions.json /usr/local/share/

# --- Minimal system packages for deterministic toolchain (kept static by design)
RUN set -Eeuo pipefail; \
    # --- Set executable permissions on scripts and source log.sh lib
    chmod +x /usr/local/bin/*.sh; \
    chmod +x /etc/profile.d/*.sh; \
    . /usr/local/bin/log.sh; \
    \
    # --- Header
    header_build; \
    \
    # --- Package Manager Detection
    log "Detecting available package manager (microdnf or dnf)..."; \
    PKG_MGR=""; \
    if command -v microdnf >/dev/null 2>&1; then \
    PKG_MGR="microdnf"; \
    log "Package manager detected: microdnf (UBI minimal/standard)."; \
    elif command -v dnf >/dev/null 2>&1; then \
    PKG_MGR="dnf"; \
    log "Package manager detected: dnf (RHEL/UBI standard)."; \
    else \
    log "FATAL: No supported package manager found (microdnf or dnf missing). Aborting build." >&2; \
    exit 2; \
    fi; \
    \
    # --- Python & EPEL Discovery
    log "Starting discovery for Python runtime..."; \
    PY_PKG="$(/usr/local/bin/discover-python.sh $PKG_MGR)"; \
    log "Discovery completed: Python package resolved to '${PY_PKG}'."; \
    log "Starting discovery for EPEL repository..."; \
    EPEL_URL="$(/usr/local/bin/discover-epel.sh)"; \
    log "Discovery completed: EPEL repository resolved to '${EPEL_URL}'."; \
    \
    # --- Repository Enablement & Hygiene
    log "Registering EPEL repository to enable additional vendor streams..."; \
    rpm -Uvh "${EPEL_URL}" >/dev/null; \
    log "Enabling UBI base repositories (ubi.repo) for package operations..."; \
    sed -i 's/enabled = 0/enabled = 1/g' /etc/yum.repos.d/ubi.repo; \
    log "Enabling EPEL repositories for supplemental packages..."; \
    sed -i 's/enabled = 0/enabled = 1/g' /etc/yum.repos.d/epel*; \
    \
    # --- System Update
    log "Refreshing repository metadata and applying base upgrades..."; \
    "${PKG_MGR}" -y update >/dev/null && "${PKG_MGR}" upgrade -y --refresh >/dev/null; \
    \
    # --- Toolchain Installation
    log "Installing core toolchain and runtime packages..."; \
    "${PKG_MGR}" install -y --setopt=tsflags=nodocs \
    findutils which tar gzip xz unzip git sudo "${PY_PKG}" \
    jq ccache clang lld llvm glibc-static \
    gcc gcc-c++ \
    krb5-libs krb5-devel \
    dnf-plugins-core rpm-build rpmdevtools cpio pkgconf \
    pkgconf-pkg-config ca-certificates>/dev/null; \
    log "Core toolchain and Python runtime installed successfully."; \
    \
    # --- Python Pip Bootstrapping (from PyPA)
    log "Bootstrapping pip from PyPA..."; \
    curl -fsSL https://bootstrap.pypa.io/get-pip.py -o /tmp/get-pip.py; \
    "${PY_PKG}" /tmp/get-pip.py --root-user-action=ignore >/dev/null; \
    log "pip bootstrapped successfully."; \
    \
    # --- Python Userland Updates (Security Hygiene)
    log "Updating Python userland packages..."; \
    "${PY_PKG}" -m pip install \
    --root-user-action=ignore \
    --no-cache-dir \
    --ignore-installed \
    --upgrade \
    setuptools urllib3 requests idna wheel >/dev/null; \
    log "Python userland packages updated successfully."; \
    \
    # --- Go Toolchain Installation (Discovery-Only)
    log "Installing Go toolchain via discovery..."; \
    /usr/local/bin/install-go.sh; \
    log "Go toolchain installed successfully."; \
    \
    # --- Sysroot Assembly for Requested Targets (amd64/arm64)
    log "Preparing sysroots for targets: ${BUILD_TARGETS} ..."; \
    IFS=',' read -r -a TARGETS <<< "${BUILD_TARGETS}"; \
    for t in "${TARGETS[@]}"; do \
    case "$t" in \
    amd64)  SYSARCH="x86_64"; LLVM_TRIPLE="${LLVM_TRIPLE_AMD64}"; SYSROOT="${SYSROOT_AMD64}" ;; \
    arm64)  SYSARCH="aarch64"; LLVM_TRIPLE="${LLVM_TRIPLE_ARM64}"; SYSROOT="${SYSROOT_ARM64}" ;; \
    *) log "WARN: Unsupported target '$t' (skipping)"; continue ;; \
    esac; \
    \
    log "Assembling sysroot for target=${t} (sysarch=${SYSARCH}) at ${SYSROOT} ..."; \
    mkdir -p "${SYSROOT}" /tmp/rpms; \
    \
    # Download only RPMs for the correct architecture
    "${PKG_MGR}" -q download --forcearch="${SYSARCH}" --arch="${SYSARCH}" --resolve --alldeps \
    glibc glibc-devel gpgme gpgme-devel libassuan libassuan-devel \
    krb5-libs krb5-devel libgcc gcc gcc-c++ libstdc++ libstdc++-devel \
    --destdir /tmp/rpms >/dev/null; \
    \
    # Remove any RPMs not matching the target arch (defensive)
    find /tmp/rpms -type f ! -name "*.${SYSARCH}.rpm" -delete; \
    \
    # Extract RPM payloads into sysroot
    for rpm in /tmp/rpms/*.rpm; do \
    rpm2cpio "$rpm" | (cd "${SYSROOT}" && cpio -idmu --quiet --no-preserve-owner --numeric-uid-gid >/dev/null 2>&1); \
    done; \
    \
    # (Optional) Check pthread.h for ARM64
    if [ "${SYSARCH}" = "aarch64" ]; then \
    grep -n 'regparm' "${SYSROOT}/usr/include/pthread.h" || log "pthread.h for aarch64 OK"; \
    fi; \
    \
    # Link GCC start files (crt*), needed by some link flows
    GCC_DIR="$(find "${SYSROOT}/usr/lib/gcc" -maxdepth 3 -type d -name "${SYSARCH}*linux*" | head -n1 || true)"; \
    if [ -n "${GCC_DIR}" ]; then \
    for f in crtbegin.o crtbeginS.o crtbeginT.o crtend.o crtendS.o; do \
    SRC="$(find "${GCC_DIR}" -maxdepth 2 -type f -name "$f" | head -n1 || true)"; \
    [ -n "${SRC}" ] && ln -sf "$(realpath --no-symlinks "$SRC")" "${SYSROOT}/usr/lib/$f" || true; \
    done; \
    else \
    log "WARN: GCC start files directory not found for ${SYSARCH}"; \
    fi; \
    \
    done; \
    mkdir -p /opt/sysroot/aarch64/usr/include/gnu; \
    touch /opt/sysroot/aarch64/usr/include/gnu/stubs-32.h; \
    \
    # --- Non-root user (UID/GID provided via args)
    log "Provisioning non-root user '${BUILDER_USER}' (UID=${BUILDER_UID}, GID=${BUILDER_GID})..."; \
    # Create group if it doesn't exist; otherwise no-op
    if getent group "${BUILDER_GID}" >/dev/null; then \
    log "Group with GID=${BUILDER_GID} already exists; skipping creation."; \
    else \
    log "Creating group '${BUILDER_USER}' with GID=${BUILDER_GID}..."; \
    groupadd -g "${BUILDER_GID}" "${BUILDER_USER}"; \
    fi; \
    \
    # Create user if it doesn't exist; otherwise no-op
    if id -u "${BUILDER_UID}" >/dev/null 2>&1; then \
    log "User with UID=${BUILDER_UID} already exists; skipping creation."; \
    else \
    log "Creating user '${BUILDER_USER}' with UID=${BUILDER_UID}, primary GID=${BUILDER_GID}..."; \
    useradd -m -u "${BUILDER_UID}" -g "${BUILDER_GID}" -s /bin/bash "${BUILDER_USER}"; \
    fi; \
    \
    # Workspace & ccache directories (owned by the non-root user)
    log "Preparing workspace and cache directories (/work, /opt/ccache) and adjusting ownership..."; \
    mkdir -p /work /opt/ccache; \
    chown -R "${BUILDER_USER}":"${BUILDER_USER}" /work /opt/ccache "${GOPATH}"; \
    \
    # Sudo policy: NOPASSWD in controlled builders for automation (CI-friendly)
    log "Configuring sudoers for '${BUILDER_USER}' (NOPASSWD) and enforcing secure PATH..."; \
    printf '%s\n' "${BUILDER_USER} ALL=(ALL) NOPASSWD:ALL" >/etc/sudoers.d/"${BUILDER_USER}"; \
    chmod 0440 /etc/sudoers.d/"${BUILDER_USER}"; \
    \
    # Ensure secure_path includes standard locations (prevents path hijacking in escalated contexts)
    printf '%s\n' 'Defaults secure_path=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin' \
    >/etc/sudoers.d/secure_path; \
    chmod 0440 /etc/sudoers.d/secure_path; \
    \
    # Validate sudoers files (quiet mode) to avoid broken sudo configuration at runtime
    log "Validating sudoers configuration..."; \
    visudo -cf /etc/sudoers >/dev/null; \
    visudo -cf /etc/sudoers.d/"${BUILDER_USER}" >/dev/null; \
    visudo -cf /etc/sudoers.d/secure_path >/dev/null; \
    log "Non-root user provisioning and sudoers validation completed successfully."; \
    \
    # --- Prebuilt / tooling / output directories
    log "Creating prebuilt and output directories..."; \
    mkdir -p /opt/tools/bin "${PREBUILT_DIR_AMD64}" "${PREBUILT_DIR_ARM64}" /out; \
    \
    # OpenShift-friendly permissions: group 0 can write; random UID can operate
    log "Harden permissions for OpenShift"; \
    for d in "${BUILDER_HOME}" "/out" "/opt/sysroot" "${PREBUILT_DIR_AMD64}" "${PREBUILT_DIR_ARM64}"; do \
    mkdir -p "$d"; \
    chgrp -R 0 "$d"; \
    chmod -R g+rwX "$d"; \
    done; \
    \
    # --- Cleanup
    log "System cleanup..."; \
    /usr/local/bin/clean-python-setuptools.sh; \
    "${PKG_MGR}" clean all >/dev/null; \
    rm -rf /var/tmp/* \
    /root/.cache/pip \
    /tmp/*; \
    log "System cleanup completed."; \
    \
    # --- Footer
    footer_build;

USER ${BUILDER_UID}

# --- Workspace & shell
WORKDIR ${BUILDER_HOME}
CMD ["/bin/bash", "-lc", "echo 'Builder ready (parametric)'; exec bash"]
