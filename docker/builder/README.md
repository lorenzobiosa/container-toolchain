# UBI Container Toolchain Builder

> **Image purpose:** A reproducible, hardened **multi-architecture builder** based on **Red Hat UBI 9** to compile CLI tools (e.g., `kubectl`, `oc`, `rancher`) for **linux/amd64** and **linux/arm64** **inside one amd64 builder image**.  
> Designed for **deterministic builds**, **fast CI**, and **low attack surface**.

---

## Contents

*   Overview
*   Prerequisites
*   Supported architectures
*   Base image pinning
*   Parametric build arguments
*   Image labels & metadata
*   Sysroot best practices
*   Local single-arch build
*   Local multi-arch build
*   Run the toolchain builder
*   Build tools (not the image): Go & Clang examples
*   Run examples: invoking `build-tools.sh` inside the builder
*   Recommended caches
*   CI/CD integration (GitHub Actions)
*   Security & provenance notes
*   Audit the manifest (post-push)
*   Troubleshooting
*   References
*   Appendix: Example Make targets

---

## Overview

This builder image provides:

*   **UBI base** with long-term support and stable ABI.
*   **Cross-toolchain for multi-arch** builds (**one amd64 builder image** compiling both amd64 and arm64): ARM64 & AMD64 sysroots, `clang`/`ld.lld`, `ccache`, Go toolchain, packaging utilities.
*   **Enterprise features**: deterministic builds, OCI-compliant metadata, shell banner/prompt controls, low runtime footprint.
*   **Fully parametric configuration**: all operational values (base image, metadata, toolchain paths, targets, triples) are passed via build args and environment variables—no hard-coded defaults.

**Key design choices:**

*   `FROM --platform=$BUILDPLATFORM` in the Dockerfile to ensure correct base selection during multi-platform builds while keeping the builder logic **identical** across platforms.  
*   **Base image pinning by digest** is recommended for reproducibility (avoids tag drift).
*   **No QEMU required**: All ARM64 binaries are cross-compiled from source using Clang/LLD and per-arch sysroots. No native ARM64 execution occurs during build.

---

## Prerequisites

*   **Docker/Podman** with BuildKit enabled (Buildx recommended).
*   **QEMU is NOT required**: All ARM64 binaries are cross-compiled and not executed during build.

---

## Supported architectures

*   **linux/amd64** (native)
*   **linux/arm64** (cross-compiled via Clang/LLD and per-target sysroots inside the **amd64** builder)

> **Important:** You pass **architectures for the tools** you compile, **not** for the builder image. The builder image itself can remain **amd64**, while producing both **amd64** and **arm64** tool binaries.

The image can be published either as a **single amd64 builder** (preferred) or, optionally, as a **multi-arch manifest** (amd64 & arm64).

---

## Base image pinning

To eliminate base drift, pin UBI minimal by **digest**:

```dockerfile
ARG BASE_IMAGE="registry.access.redhat.com/ubi9/ubi-minimal@sha256:<digest>"
FROM --platform=$BUILDPLATFORM ${BASE_IMAGE}
````

> Pinning is a Docker best practice for reproducibility and smaller attack surface.

***

## Parametric build arguments

The Dockerfile is **fully parametric**—operational values are passed via build args and environment variables.

**Key build args (selected):**

*   **Base & metadata**
    *   `BASE_IMAGE` — UBI minimal base (digest pin recommended).
    *   `IMAGE_TITLE`, `IMAGE_DESCRIPTION`, `IMAGE_VENDOR`, `IMAGE_AUTHOR`, `AUTHOR_EMAIL`
    *   `IMAGE_LICENSES`, `IMAGE_SOURCE_URL`, `VCS_REF`, `BUILD_DATE`

*   **Toolchain**
    *   `GOROOT` (default `/usr/local/go`)
    *   `GOPATH` (default `/opt/go`)
    *   `CC` (default `clang`), `CXX` (default `clang++`), `LD` (default `ld.lld`)
    *   `CCACHE_SIZE` (default `5.0G`)

*   **Runtime user**
    *   `BUILDER_USER` (default `builder`)
    *   `BUILDER_UID` (default `10001`)
    *   `BUILDER_GID` (default `10001`)
    *   `BUILDER_HOME` (default `/work`)

*   **Prompt/banner**
    *   `WELCOME_ENABLE` (default `1`)
    *   `PROMPT_ENABLE_COLORS` (default `1`)

*   **Cross compilation (new)**
    *   `BUILD_TARGETS` — comma-separated list of targets to assemble **sysroots** for (e.g., `amd64,arm64`)
    *   `SYSROOT_DIR_BASE` — base sysroot path (default `/opt/sysroot`)
    *   `PREBUILT_DIR_AMD64`, `PREBUILT_DIR_ARM64` — output/prebuilt paths

**Environment exported by the image (selected):**

*   `LLVM_TRIPLE_AMD64="x86_64-unknown-linux-gnu"`
*   `LLVM_TRIPLE_ARM64="aarch64-unknown-linux-gnu"`
*   `SYSROOT_AMD64="${SYSROOT_DIR_BASE}/x86_64"`
*   `SYSROOT_ARM64="${SYSROOT_DIR_BASE}/aarch64"`
*   `PKG_CONFIG_SYSROOT_DIR`, `PKG_CONFIG_LIBDIR`, `PKG_CONFIG_PATH` (defaults set for ARM64; **override per target** at build time)

> EPEL is discovered at build-time via `discover-epel.sh`; no EPEL URL arg is needed.

***

## Image labels & metadata

The builder sets **OCI labels** for traceability (passed via build args):

*   `org.opencontainers.image.title`
*   `org.opencontainers.image.description`
*   `org.opencontainers.image.vendor`
*   `org.opencontainers.image.authors`
*   `org.opencontainers.image.revision`
*   `org.opencontainers.image.licenses`
*   `org.opencontainers.image.created`
*   `org.opencontainers.image.source`

***

## Sysroot best practices

*   **Automated assembly**: The Dockerfile assembles per-target sysroots (`amd64`, `arm64`) by downloading RPMs (via `dnf-plugins-core`) and extracting them into `${SYSROOT_DIR_BASE}/<arch>`.
*   **Minimal content**: Only headers/libs required for cross-linking: `glibc`, `libstdc++`, `libgcc`, and selected development libs (e.g., `gpgme`, `libassuan`, `krb5` when needed).
*   **Start files**: GCC `crt*.o` are symlinked into the sysroot for reliable linking flows.
*   **Packaging**: Sysroots are tarred for reuse into `/opt/sysroot/sysroot-<target>.tar.gz`.
*   **Per-target build**: Override `PKG_CONFIG_SYSROOT_DIR` / `PKG_CONFIG_LIBDIR` to match `${SYSROOT_AMD64}` or `${SYSROOT_ARM64}` during your tool builds; pass `--target` and `--sysroot` to `clang`.

***

## Local single-arch build

Build locally for the **current host arch** (recommended: produce a single **amd64** builder image):

```bash
podman build \
  -f docker/builder/Dockerfile \
  --build-arg BASE_IMAGE="registry.access.redhat.com/ubi9/ubi-minimal@sha256:<digest>" \
  --build-arg IMAGE_TITLE="UBI Container Toolchain Builder" \
  --build-arg IMAGE_DESCRIPTION="Multi-arch builder (amd64/arm64) for CLI tools" \
  --build-arg IMAGE_VENDOR="Biosa Labs" \
  --build-arg IMAGE_AUTHOR="Lorenzo Biosa" \
  --build-arg AUTHOR_EMAIL="lorenzo@biosa-labs.com" \
  --build-arg IMAGE_LICENSES="MIT" \
  --build-arg IMAGE_SOURCE_URL="https://github.com/lorenzobiosa/container-toolchain" \
  --build-arg VCS_REF="$(git rev-parse --short=12 HEAD)" \
  --build-arg BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --build-arg GOROOT="/usr/local/go" \
  --build-arg GOPATH="/opt/go" \
  --build-arg CC="clang" --build-arg CXX="clang++" --build-arg LD="ld.lld" \
  --build-arg CCACHE_SIZE="5.0G" \
  --build-arg BUILDER_USER="builder" --build-arg BUILDER_UID="10001" --build-arg BUILDER_GID="10001" \
  --build-arg BUILDER_HOME="/work" \
  --build-arg WELCOME_ENABLE="1" --build-arg PROMPT_ENABLE_COLORS="1" \
  --build-arg BUILD_TARGETS="amd64,arm64" \
  --build-arg SYSROOT_DIR_BASE="/opt/sysroot" \
  --build-arg PREBUILT_DIR_AMD64="/opt/prebuilt/linux-amd64" \
  --build-arg PREBUILT_DIR_ARM64="/opt/prebuilt/linux-arm64" \
  -t localhost/ubi9-toolchain-builder:dev \
  .
```

> `BUILD_TARGETS` controls which sysroots are assembled (e.g., `amd64`, `arm64`, or both) **inside the image**.  
> It does **not** change the builder image architecture: the builder remains **amd64**.

***

## Local multi-arch build (optional manifest)

If you prefer publishing a **multi-arch manifest** for the builder image (amd64 + arm64), use Buildx:

```bash
podman buildx build \
  --platform linux/amd64,linux/arm64 \
  -f docker/builder/Dockerfile \
  --build-arg BASE_IMAGE="registry.access.redhat.com/ubi9/ubi-minimal@sha256:<digest>" \
  --build-arg IMAGE_TITLE="UBI Container Toolchain Builder" \
  --build-arg IMAGE_DESCRIPTION="Multi-arch builder (amd64/arm64) for CLI tools" \
  --build-arg IMAGE_VENDOR="Biosa Labs" \
  --build-arg IMAGE_AUTHOR="Lorenzo Biosa" \
  --build-arg AUTHOR_EMAIL="lorenzo@biosa-labs.com" \
  --build-arg IMAGE_LICENSES="MIT" \
  --build-arg IMAGE_SOURCE_URL="https://github.com/lorenzobiosa/container-toolchain" \
  --build-arg VCS_REF="$(git rev-parse --short=12 HEAD)" \
  --build-arg BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --build-arg GOROOT="/usr/local/go" \
  --build-arg GOPATH="/opt/go" \
  --build-arg CC="clang" --build-arg CXX="clang++" --build-arg LD="ld.lld" \
  --build-arg CCACHE_SIZE="5.0G" \
  --build-arg BUILDER_USER="builder" --build-arg BUILDER_UID="10001" --build-arg BUILDER_GID="10001" \
  --build-arg BUILDER_HOME="/work" \
  --build-arg WELCOME_ENABLE="1" --build-arg PROMPT_ENABLE_COLORS="1" \
  --build-arg BUILD_TARGETS="amd64,arm64" \
  --build-arg SYSROOT_DIR_BASE="/opt/sysroot" \
  --build-arg PREBUILT_DIR_AMD64="/opt/prebuilt/linux-amd64" \
  --build-arg PREBUILT_DIR_ARM64="/opt/prebuilt/linux-arm64" \
  -t localhost/ubi9-toolchain-builder:latest \
  -t localhost/ubi9-toolchain-builder:$(git rev-parse --short=12 HEAD) \
  .
```

> Even when you publish a multi-arch manifest, the builder logic remains the same; you can still compile both targets **from the amd64 build**.

***

## Run the toolchain builder

Start an interactive shell:

```bash
podman run --rm -it localhost/ubi9-toolchain-builder:latest bash
```

Enable banner/prompt at runtime (optional):

```bash
export WELCOME_ENABLE=1
export PROMPT_ENABLE_COLORS=1
export IMAGE_TITLE="UBI Container Toolchain Builder"
export IMAGE_DESCRIPTION="Multi-arch builds (amd64/arm64)"
```

***

## Build tools (not the image): Go & Clang examples

> The following examples show **how to compile your CLI tools for both amd64 and arm64** inside the **single amd64 builder**.  
> Sysroots are already assembled at image build and available under `${SYSROOT_AMD64}` and `${SYSROOT_ARM64}`.

### Go (typical for CLI tools)

```bash
# amd64 binary
env GOOS=linux GOARCH=amd64 \
  go build -trimpath -ldflags="-s -w" \
  -o /out/mytool-linux-amd64 ./cmd/mytool

# arm64 binary
env GOOS=linux GOARCH=arm64 \
  go build -trimpath -ldflags="-s -w" \
  -o /out/mytool-linux-arm64 ./cmd/mytool
```

> The builder auto-discovers and installs the **latest stable Go** with checksum verification.

### C/C++ via Clang/LLD (using per-target sysroot & triple)

```bash
# amd64 build (override pkg-config to point to AMD64 sysroot)
export PKG_CONFIG_SYSROOT_DIR="${SYSROOT_AMD64}"
export PKG_CONFIG_LIBDIR="${SYSROOT_AMD64}/usr/lib64/pkgconfig:${SYSROOT_AMD64}/usr/lib/pkgconfig"

clang \
  --target="${LLVM_TRIPLE_AMD64}" \
  --sysroot="${SYSROOT_AMD64}" \
  -fuse-ld=lld \
  -O2 -DNDEBUG \
  -o /out/mytool-linux-amd64 \
  src/main.c

# arm64 build (override pkg-config to point to ARM64 sysroot)
export PKG_CONFIG_SYSROOT_DIR="${SYSROOT_ARM64}"
export PKG_CONFIG_LIBDIR="${SYSROOT_ARM64}/usr/lib64/pkgconfig:${SYSROOT_ARM64}/usr/lib/pkgconfig}"

clang \
  --target="${LLVM_TRIPLE_ARM64}" \
  --sysroot="${SYSROOT_ARM64}" \
  -fuse-ld=lld \
  -O2 -DNDEBUG \
  -o /out/mytool-linux-arm64 \
  src/main.c
```

> For projects using `pkg-config`, ensure `.pc` discovery aligns with the selected sysroot by overriding `PKG_CONFIG_SYSROOT_DIR`/`PKG_CONFIG_LIBDIR` **per target**.

***

## Run examples: invoking `build-tools.sh` inside the builder

> These examples show **how to run the builder image to produce your tool binaries**, driving the build with a script such as `/usr/local/bin/build-tools.sh`.  
> The script can accept a `BUILD_TARGETS` env (`amd64`, `arm64`, or `amd64,arm64`) and compile accordingly.

**Podman (preferred):**

```bash
# Build both amd64 and arm64 tools using the single amd64 builder image
podman run --rm \
  -e BUILD_TARGETS="amd64,arm64" \
  -v "$PWD":/work \
  -v "$PWD/out":/out \
  localhost/ubi9-toolchain-builder:latest \
  /usr/local/bin/build-tools.sh
```

**Docker:**

```bash
# Only arm64 tools
docker run --rm \
  -e BUILD_TARGETS="arm64" \
  -v "%CD%":/work \
  -v "%CD%/out":/out \
  ghcr.io/<owner>/ubi9-toolchain-builder:latest \
  /usr/local/bin/build-tools.sh
```

**Notes:**

*   Mount your **source** into `/work` and write artifacts to `/out`.
*   `BUILD_TARGETS` drives per-target compilation; the builder’s **image arch remains amd64**.

***

## Recommended caches

For faster builds (especially in CI):

*   **Go build cache** → `~/.cache/go-build`
*   **Go modules** → `~/go/pkg/mod`
*   **ccache** → `~/.ccache`
*   **DNF** → `/var/cache/dnf`

Bind-mount them in `podman run` or configure **GitHub Actions cache** for repeatable builds.

***

## CI/CD integration (GitHub Actions)

Use the official Buildx action and a **reusable workflow** to standardize image pushes:

```yaml
# .github/workflows/build-image.yml
name: Build Builder Image
on:
  workflow_dispatch:
  push:
    branches: [ "main" ]
permissions:
  contents: read
  packages: write

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: docker/setup-buildx-action@v3
      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.repository_owner }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Build & Push (single-arch amd64 builder)
        uses: docker/build-push-action@v6
        with:
          context: .
          file: docker/builder/Dockerfile
          platforms: linux/amd64
          push: true
          tags: |
            ghcr.io/${{ github.repository_owner }}/ubi9-toolchain-builder:latest
            ghcr.io/${{ github.repository_owner }}/ubi9-toolchain-builder:${{ github.sha }}
          build-args: |
            BASE_IMAGE=registry.access.redhat.com/ubi9/ubi-minimal@sha256:<digest>
            VCS_REF=${{ github.sha }}
            BUILD_DATE=${{ github.event.head_commit.timestamp }}
            BUILD_TARGETS=amd64,arm64
            SYSROOT_DIR_BASE=/opt/sysroot
            PREBUILT_DIR_AMD64=/opt/prebuilt/linux-amd64
            PREBUILT_DIR_ARM64=/opt/prebuilt/linux-arm64
          provenance: false
          sbom: false

      # Optional: publish a multi-arch manifest builder
      - name: Build & Push (multi-arch manifest OPTIONAL)
        if: ${{ false }}  # flip to true if desired
        uses: docker/build-push-action@v6
        with:
          context: .
          file: docker/builder/Dockerfile
          platforms: linux/amd64,linux/arm64
          push: true
          tags: |
            ghcr.io/${{ github.repository_owner }}/ubi9-toolchain-builder:latest
            ghcr.io/${{ github.repository_owner }}/ubi9-toolchain-builder:${{ github.sha }}
          build-args: |
            BASE_IMAGE=registry.access.redhat.com/ubi9/ubi-minimal@sha256:<digest>
            VCS_REF=${{ github.sha }}
            BUILD_DATE=${{ github.event.head_commit.timestamp }}
            BUILD_TARGETS=amd64,arm64
            SYSROOT_DIR_BASE=/opt/sysroot
            PREBUILT_DIR_AMD64=/opt/prebuilt/linux-amd64
            PREBUILT_DIR_ARM64=/opt/prebuilt/linux-arm64
          provenance: false
          sbom: false
```

> The builder image remains **amd64** by default; it still **compiles both targets** inside the container.

***

## Security & provenance notes

*   **Build attestations (provenance/SBOM)** may create additional manifests. To keep your tag’s manifest index clean, you can **disable** attestation manifests at push-time in CI with `provenance: false` and `sbom: false`.
*   If you need SBOM/provenance, prefer **OCI referrers** linked to the image **digest**, not tagged variants in the manifest list. Referrers keep the manifest index clean and are discoverable via referrer APIs.

***

## Audit the manifest (post-push)

Validate the registry state after pushing the image:

```bash
# Human-readable inspection (manifest list if multi-arch)
docker buildx imagetools inspect ghcr.io/<owner>/ubi9-toolchain-builder:latest

# Strict JSON audit: check platform entries
json="$(docker buildx imagetools inspect ghcr.io/<owner>/ubi9-toolchain-builder:latest --format '{{json .Manifest}}')"
echo "$json" | jq '.manifests[].platform'
```

***

## Troubleshooting

*   **Extra `unknown/unknown` platform in registry UI:** Disable attestation manifests at push-time (`provenance: false`, `sbom: false`) to keep indices clean.
*   **Digest mismatch on base image:** If you pin by digest, verify the digest is correct and accessible; re-pull when updating base.
*   **Slow builds:** Enable caches (Go build, Go mod, ccache, DNF) and avoid unnecessary multi-arch image builds if you only need an amd64 builder that compiles both targets.
*   **Sysroot issues:** Ensure per-target overrides for `PKG_CONFIG_SYSROOT_DIR`/`PKG_CONFIG_LIBDIR` match `${SYSROOT_AMD64}` or `${SYSROOT_ARM64}` and pass `--target` + `--sysroot` to `clang`. Check that `crt*.o` links exist under `${SYSROOT}/usr/lib`.

***

## References

1.  Docker Buildx — Multi-platform builds & CLI  
    <https://docs.docker.com/build/building/multi-platform/> · <https://docs.docker.com/reference/cli/docker/buildx/>
2.  Docker — Best practices for Dockerfiles (pinning, layers)  
    <https://docs.docker.com/build/building/best-practices/>
3.  Docker BuildKit — Build attestations (SBOM/provenance)  
    <https://docs.docker.com/build/metadata/attestations/> · <https://docs.docker.com/build/metadata/attestations/slsa-provenance/>
4.  Docker Buildx — `imagetools inspect` (manifest list)  
    <https://docs.docker.com/reference/cli/docker/buildx/imagetools/inspect/>
5.  OCI Distribution / Referrers (general background)  
    <https://oci-playground.github.io/specs-latest/specs/distribution/v1.1.0-rc2/oci-distribution-spec.html>

> Note: References are provided for general concepts and workflows. See official Docker documentation for exact command-line behavior and up-to-date best practices.

***

## Appendix: Example Make targets

If you use a `Makefile`, add:

```makefile
.PHONY: build-audit build-amd64 builder-run tools-amd64 tools-arm64 tools-both

# Build single-arch amd64 builder that compiles both targets internally
build-amd64:
	docker buildx build \
	  --platform linux/amd64 \
	  -f docker/builder/Dockerfile \
	  --build-arg BASE_IMAGE=registry.access.redhat.com/ubi9/ubi-minimal@sha256:<digest> \
	  --build-arg BUILD_TARGETS=amd64,arm64 \
	  --build-arg SYSROOT_DIR_BASE=/opt/sysroot \
	  --build-arg PREBUILT_DIR_AMD64=/opt/prebuilt/linux-amd64 \
	  --build-arg PREBUILT_DIR_ARM64=/opt/prebuilt/linux-arm64 \
	  -t ghcr.io/<owner>/ubi9-toolchain-builder:latest \
	  -t ghcr.io/<owner>/ubi9-toolchain-builder:$(shell git rev-parse --short=12 HEAD) \
	  .

# Inspect pushed manifest (useful if you enabled the optional multi-arch publish)
build-audit:
	docker buildx imagetools inspect ghcr.io/<owner>/ubi9-toolchain-builder:latest

# Run builder interactively
builder-run:
	docker run --rm -it ghcr.io/<owner>/ubi9-toolchain-builder:latest bash

# Produce tools (amd64 only) via build-tools.sh
tools-amd64:
	docker run --rm \
	  -e BUILD_TARGETS="amd64" \
	  -v "$(PWD)":/work \
	  -v "$(PWD)/out":/out \
	  ghcr.io/<owner>/ubi9-toolchain-builder:latest \
	  /usr/local/bin/build-tools.sh

# Produce tools (arm64 only) via build-tools.sh
tools-arm64:
	docker run --rm \
	  -e BUILD_TARGETS="arm64" \
	  -v "$(PWD)":/work \
	  -v "$(PWD)/out":/out \
	  ghcr.io/<owner>/ubi9-toolchain-builder:latest \
	  /usr/local/bin/build-tools.sh

# Produce tools (amd64 and arm64) via build-tools.sh
tools-both:
	docker run --rm \
	  -e BUILD_TARGETS="amd64,arm64" \
	  -v "$(PWD)":/work \
	  -v "$(PWD)/out":/out \
	  ghcr.io/<owner>/ubi9-toolchain-builder:latest \
	  /usr/local/bin/build-tools.sh
```

> For CI parity locally, consider `nektos/act` to run GitHub Actions workflows in Docker: <https://github.com/nektos/act>

***
