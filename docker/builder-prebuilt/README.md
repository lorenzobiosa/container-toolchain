# UBI Container Toolchain Builder (Prebuilt Stash)

> **Image purpose:** This image bakes precompiled multi-arch toolchain tarballs (`tools-linux-amd64.tar.gz`, `tools-linux-arm64.tar.gz`) into a UBI-based builder for **fast CI/CD workflows** and reproducible builds.  
> Designed for **nightly pipeline acceleration**, **artifact integrity**, and **enterprise compliance**.

---

## Contents

*   Overview
*   Prerequisites
*   Supported architectures
*   Base image & pinning
*   Parametric build arguments
*   Image labels & metadata
*   Local single-arch build
*   Local multi-arch build & push (Buildx)
*   Run the prebuilt builder
*   Artifact verification (SHA256)
*   Sysroot best practices
*   Recommended caches
*   CI/CD integration (GitHub Actions)
*   Security & provenance notes
*   Audit the manifest (post-push)
*   Troubleshooting
*   References
*   Appendix: Example Make targets

---

## Overview

This prebuilt builder image:

*   **Incorporates precompiled toolchain tarballs** for both `amd64` and `arm64`, validated by SHA256 at build time.
*   **Uses the main builder image as its base** for consistency and reproducibility.
*   **Accelerates nightly and CI/CD workflows** by avoiding repeated source builds.
*   **Ensures artifact integrity** by failing the build if checksums do not match.
*   **Optionally incorporates a minimal, read-only ARM64 sysroot** for cross-compilation.

---

## Prerequisites

*   **Docker Engine** with BuildKit enabled (Buildx recommended).
*   Prebuilt tarballs: `tools-linux-amd64.tar.gz`, `tools-linux-arm64.tar.gz` (produced by your toolchain build process).
*   Optional: ARM64 sysroot tarball (`arm64-sysroot.tar.gz`) for cross-compilation.
*   Network access to your image registry (e.g., GHCR).
*   **QEMU is NOT required:** All ARM64 binaries are cross-compiled and not executed during build. This results in faster, more reproducible multi-arch builds.

---

## Supported architectures

*   **linux/amd64**
*   **linux/arm64**

Multi-arch images are delivered as a **single manifest list** with platform-specific manifests.

---

## Base image & pinning

The Dockerfile uses the main builder image as its base.  
Pin by digest for reproducibility:

```dockerfile
ARG BASE_IMAGE="ghcr.io/<owner>/ubi9-toolchain-builder:latest"
FROM --platform=$BUILDPLATFORM ${BASE_IMAGE}
```

> Pinning by digest (e.g., `@sha256:<digest>`) is recommended for reproducibility.

---

## Parametric build arguments

The Dockerfile is **fully parametric**—all operational values are passed via build args and environment variables.  
No hard-coded defaults are present.

**Key build args:**

*   `BASE_IMAGE` — Main builder image (digest pin recommended).
*   `IMAGE_TITLE`, `IMAGE_DESCRIPTION`, `IMAGE_VENDOR`, `IMAGE_LICENSES`, `IMAGE_SOURCE_URL`, `VCS_REF`, `BUILD_DATE` — Metadata for OCI labels and traceability.
*   `WELCOME_ENABLE`, `PROMPT_ENABLE_COLORS` — Shell banner/prompt controls.
*   `BUILDER_UID`, `BUILDER_GID` — UID/GID for user inside container.
*   `AMD64_TARBALL`, `ARM64_TARBALL` — Paths to prebuilt toolchain tarballs.
*   `AMD64_SHA256`, `ARM64_SHA256` — Expected SHA256 for each tarball.
*   `ARM64_SYSROOT`, `ARM64_SYSROOT_SHA256` — Optional ARM64 sysroot tarball and its SHA256.

> All values must be provided at build time (see example below).

---

## Image labels & metadata

The image sets **OCI labels** for traceability (all values passed via build args):

*   `org.opencontainers.image.title`
*   `org.opencontainers.image.description`
*   `org.opencontainers.image.vendor`
*   `org.opencontainers.image.version`
*   `org.opencontainers.image.revision`
*   `org.opencontainers.image.licenses`
*   `org.opencontainers.image.created`
*   `org.opencontainers.image.source`

Keep these updated via build args or Dockerfile `LABEL` instructions to align with enterprise governance.

---

## Local single-arch build

Prepare your tarballs and checksums:

```bash
mkdir -p out
cp tools-linux-amd64.tar.gz out/
cp tools-linux-arm64.tar.gz out/
AMD64_SHA=$(sha256sum out/tools-linux-amd64.tar.gz | awk '{print $1}')
ARM64_SHA=$(sha256sum out/tools-linux-arm64.tar.gz | awk '{print $1}')
```

Build for the current host arch:

```bash
docker build \
  -f docker/builder-prebuilt/Dockerfile \
  --build-arg BASE_IMAGE="ghcr.io/<owner>/ubi9-toolchain-builder:latest" \
  --build-arg IMAGE_TITLE="UBI Toolchain Builder (Prebuilt)" \
  --build-arg IMAGE_DESCRIPTION="Precompiled multi-arch toolchain baked for fast CI/CD" \
  --build-arg IMAGE_VENDOR="Biosa Labs" \
  --build-arg IMAGE_AUTHOR="Lorenzo Biosa" \
  --build-arg AUTHOR_EMAIL="lorenzo@biosa-labs.com" \
  --build-arg IMAGE_LICENSES="MIT" \
  --build-arg IMAGE_SOURCE_URL="https://github.com/<owner>/<repo>" \
  --build-arg VCS_REF="$(git rev-parse --short=12 HEAD)" \
  --build-arg BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --build-arg WELCOME_ENABLE="1" \
  --build-arg PROMPT_ENABLE_COLORS="1" \
  --build-arg BUILDER_UID="10001" \
  --build-arg BUILDER_GID="10001" \
  --build-arg AMD64_TARBALL="out/tools-linux-amd64.tar.gz" \
  --build-arg ARM64_TARBALL="out/tools-linux-arm64.tar.gz" \
  --build-arg AMD64_SHA256="${AMD64_SHA}" \
  --build-arg ARM64_SHA256="${ARM64_SHA}" \
  --build-arg ARM64_SYSROOT="out/arm64-sysroot.tar.gz" \
  --build-arg ARM64_SYSROOT_SHA256="$(sha256sum out/arm64-sysroot.tar.gz | awk '{print $1}')" \
  -t ghcr.io/<owner>/ubi9-toolchain-builder:prebuilt-dev \
  .
```

---

## Local multi-arch build & push (Buildx)

1.  **Create & use** a Buildx builder:

```bash
docker buildx create --use
```

2.  **Login** to GHCR (or your registry):

```bash
echo "${GHCR_TOKEN}" | docker login ghcr.io -u <github_user> --password-stdin
```

3.  **Build & push** the multi-arch image:

```bash
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -f docker/builder-prebuilt/Dockerfile \
  --build-arg BASE_IMAGE="ghcr.io/<owner>/ubi9-toolchain-builder:latest" \
  ... [all other build-args as above] ...
  -t ghcr.io/<owner>/ubi9-toolchain-builder:latest \
  -t ghcr.io/<owner>/ubi9-toolchain-builder:$(git rev-parse --short=12 HEAD) \
  --push \
  .
```

---

## Run the prebuilt builder

Start an interactive shell:

```bash
docker run --rm -it \
  ghcr.io/<owner>/ubi9-toolchain-builder:latest \
  bash
```

Set banner/prompt at runtime:

```bash
export WELCOME_ENABLE=1
export PROMPT_ENABLE_COLORS=1
export IMAGE_TITLE="UBI Toolchain Builder (Prebuilt)"
export IMAGE_DESCRIPTION="Precompiled multi-arch toolchain"
```

---

## Artifact verification (SHA256)

During build, the Dockerfile **verifies the SHA256** of each tarball.  
If the checksum does not match, the build **fails** immediately.

This ensures only trusted, reproducible artifacts are baked into the image.

---

## Sysroot best practices

*   **Minimal, read-only sysroot**: Only necessary headers and libraries for ARM64 cross-compilation are included. Avoid unnecessary locale data and debugging symbols.
*   **Provision via CI**: The sysroot is passed as a versioned tarball (`arm64-sysroot.tar.gz`) and unpacked in the builder or prebuilt image. SHA256 is verified at build time for supply chain integrity.
*   **Configuration**: Use `PKG_CONFIG_SYSROOT_DIR`, `PKG_CONFIG_LIBDIR`, and compiler `--sysroot` flags. Avoid full toolchain bloat; include only essential SOVERSION libraries.
*   **No QEMU required**: All ARM64 binaries are cross-compiled and not executed during build.

---

## Recommended caches

For faster builds (especially in CI):

*   **Go build cache** → mount: `~/.cache/go-build`
*   **Go modules** → mount: `~/go/pkg/mod`
*   **ccache** → mount: `~/.ccache`
*   **DNF/cache** → mount: `/var/cache/dnf`

Bind-mount them in `docker run` or configure **GitHub Actions cache** for repeatable builds.

---

## CI/CD integration (GitHub Actions)

Use the official Buildx action and a **reusable workflow** for multi-arch pushes:

```yaml
# .github/workflows/nightly.yml
name: Nightly - Bake Prebuilt
on:
  schedule:
    - cron: "0 2 * * *"
  workflow_dispatch:
permissions:
  contents: read
  packages: write

jobs:
  bake:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: docker/setup-buildx-action@v3
      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.repository_owner }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - name: Build & Push (multi-arch)
        uses: docker/build-push-action@v6
        with:
          context: .
          file: docker/builder-prebuilt/Dockerfile
          platforms: linux/amd64,linux/arm64
          push: true
          tags: |
            ghcr.io/${{ github.repository_owner }}/ubi9-toolchain-builder:latest
            ghcr.io/${{ github.repository_owner }}/ubi9-toolchain-builder:${{ github.sha }}
          build-args: |
            BASE_IMAGE=ghcr.io/${{ github.repository_owner }}/ubi9-toolchain-builder:latest
            IMAGE_TITLE=UBI Toolchain Builder (Prebuilt)
            IMAGE_DESCRIPTION=Precompiled multi-arch toolchain baked for fast CI/CD
            IMAGE_VENDOR=Biosa Labs
            IMAGE_AUTHOR=Lorenzo Biosa
            AUTHOR_EMAIL=lorenzo@biosa-labs.com
            IMAGE_LICENSES=MIT
            IMAGE_SOURCE_URL=https://github.com/<owner>/<repo>
            VCS_REF=${{ github.sha }}
            BUILD_DATE=${{ github.event.head_commit.timestamp }}
            WELCOME_ENABLE=1
            PROMPT_ENABLE_COLORS=1
            BUILDER_UID=10001
            BUILDER_GID=10001
            AMD64_TARBALL=out/tools-linux-amd64.tar.gz
            ARM64_TARBALL=out/tools-linux-arm64.tar.gz
            AMD64_SHA256=${{ steps.shas.outputs.amd64_sha }}
            ARM64_SHA256=${{ steps.shas.outputs.arm64_sha }}
            ARM64_SYSROOT=out/arm64-sysroot.tar.gz
            ARM64_SYSROOT_SHA256=${{ steps.shas.outputs.sysroot_sha }}
          provenance: false
          sbom: false
```

> The `provenance: false` and `sbom: false` flags prevent BuildKit from attaching attestation manifests to the index, keeping the manifest list clean. **\[Refs 1,2]**

---

## Security & provenance notes

*   **Attestation manifests (provenance/SBOM)** are disabled at push-time to avoid extra `unknown/unknown` entries in the registry manifest list (GHCR UI).  
    If you need SBOM/provenance, publish them as **OCI referrers** linked to the image digest, or as release assets.

*   **SHA256 verification** ensures only trusted artifacts are baked into the image.

---

## Audit the manifest (post-push)

Validate the registry state after pushing the multi-arch image:

```bash
docker buildx imagetools inspect ghcr.io/<owner>/ubi9-toolchain-builder:latest

# Strict JSON audit: exactly amd64 and arm64, all manifests have .platform
json="$(docker buildx imagetools inspect ghcr.io/<owner>/ubi9-toolchain-builder:latest --format '{{json .Manifest}}')"
echo "$json" | jq '.manifests[].platform'
```

---

## Troubleshooting

*   **Digest “unknown/unknown” in GHCR:** Ensure the workflow disables BuildKit attestation manifests (`provenance: false`, `sbom: false`).
*   **Checksum mismatch:** Make sure the SHA256 values passed match the tarballs; the build will fail if mismatched.
*   **Sysroot issues:** Ensure the sysroot tarball is minimal, read-only, and SHA256-verified at build time. Pass it via CI as a build artifact and unpack in the builder or prebuilt image.
*   **Cache issues:** Enable and mount caches for Go build, Go modules, ccache, and DNF for faster builds.

---

## References

1.  **Docker BuildKit — Build attestations**  
    <https://docs.docker.com/build/metadata/attestations/>
2.  **Docker Buildx — Multi-platform builds**  
    <https://docs.docker.com/build/building/multi-platform/>
3.  **Docker Buildx — Manifest list inspection**  
    <https://docs.docker.com/reference/cli/docker/buildx/imagetools/inspect/>
4.  **OCI Referrers / Registry UI notes**  
    <https://oci-playground.github.io/specs-latest/specs/distribution/v1.1.0-rc2/oci-distribution-spec.html>
5.  **Community discussion on GHCR UI and attestation manifests**  
    <https://github.com/orgs/community/discussions/45969>

---

## Appendix: Example Make targets

```makefile
.PHONY: docker-prebuilt audit
docker-prebuilt:
	docker buildx build \
	  --platform linux/amd64,linux/arm64 \
	  -f docker/builder-prebuilt/Dockerfile \
	  --build-arg BASE_IMAGE=ghcr.io/<owner>/ubi9-toolchain-builder:latest \
	  ... [all other build-args as above] ...
	  -t ghcr.io/<owner>/ubi9-toolchain-builder:latest \
	  -t ghcr.io/<owner>/ubi9-toolchain-builder:$(shell git rev-parse --short=12 HEAD) \
	  --push .

audit:
	docker buildx imagetools inspect ghcr.io/<owner>/ubi9-toolchain-builder:latest
```

> For CI parity locally, consider using `nektos/act` to run GitHub Actions workflows in Docker.  
> <https://github.com/nektos/act>

---
