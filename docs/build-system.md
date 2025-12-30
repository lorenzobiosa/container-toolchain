# Build System Design & Implementation

## 1. Overview

This document details the **internal design and operational behavior** of the build system powering the UBI-9 Multi-Architecture Builder Toolchain.  
It focuses on the *how*—the concrete mechanisms, scripts, and workflow logic—behind the production of **deterministic, cross-architecture packages and container images**.

---

## 2. Build System Objectives

| Objective   | Description                                                 |
| ----------- | ----------------------------------------------------------- |
| Performance | Builder image \~10 minutes, multi-arch packages \~5 minutes |
| Determinism | Identical outputs from identical inputs                     |
| Isolation   | Fully controlled, containerized build environment           |
| Security    | No unverified binaries or uncontrolled dependencies         |
| Scalability | Stateless, parallel CI execution                            |

---

## 3. Builder Image Construction

### 3.1 Base Image & Multi-Stage Build

*   **Base:** Red Hat UBI 9 (long-term support, enterprise compliance)
*   **Multi-stage Docker build:**
    *   Stages: OS prep → toolchain install → cross-arch setup → build tooling → final assembly
    *   **Layer reuse** and **minimal final image size**
    *   All tools installed and pinned via `/build/config/tool-versions.json`
    *   No runtime resolution of tool versions

### 3.2 Toolchain & Build Tools

*   Compilers: GCC, Clang, LLD
*   Build systems: `make`, `cmake`, autotools
*   Cross-compilation: ARM64 sysroot, PKG\_CONFIG, Clang/LLD for ARM
*   Utilities: `jq`, `tar`, `xz`, `gzip`, `ccache` (optional)
*   Go toolchain: version pinned, provided in image

---

## 4. Deterministic Build Invariants

| Invariant             | Enforcement               |
| --------------------- | ------------------------- |
| Pinned tool versions  | Configuration enforcement |
| Immutable environment | Containerized builder     |
| No external binaries  | Source-based compilation  |
| Reproducible layers   | Controlled build order    |
| Verified outputs      | Signing & verification    |

*   **No prebuilt binaries**: All packages are built from source, no opaque dependencies.
*   **Strict version pinning**: All critical tools and libraries are version-locked.
*   **Build scripts**: All logic is encoded in versioned scripts (`build-tools.sh`, etc.).

---

## 5. Package Build Workflow

### 5.1 Source-Based Compilation

*   All packages (`kubectl`, `oc`, `rancher`) are built from source.
*   Cross-architecture: Both **amd64** and **arm64** produced from the same definition.
*   **Smoke tests**: Validate ELF headers, permissions, and (on native arch) client version output.

### 5.2 Performance

| Stage                    | Typical Duration |
| ------------------------ | ---------------- |
| Builder image build      | \~10 minutes     |
| Multi-arch package build | \~5 minutes      |

*   **CI caching**: Go build, Go modules, DNF, ccache (restored per job for speed).
*   **Stateless**: Each build is isolated; failures leave no persistent state.

---

## 6. Image Assembly

*   **Minimal UBI 9 runtime base**
*   Only pipeline-produced packages included
*   **SBOM (SPDX JSON)** generated for every release

---

## 7. Failure & Recovery Model

*   **Stateless builds**: Failures are isolated to the CI job; no persistent side effects.
*   **Deterministic retry**: Any build can be retried with identical results, given the same inputs.

---

## 8. Compliance & Auditability

*   **Full artifact traceability**: All outputs are signed (Cosign, GPG), checksummed, and SBOM’d.
*   **Deterministic rebuilds**: Given the same source and pins, outputs are bit-for-bit identical.
*   **Comprehensive CI logs**: All build, test, and signing steps are logged and auditable.

---

## 9. Integration with CI/CD

*   **Build orchestration**: All builds are triggered and managed by GitHub Actions workflows.
*   **Automated signing & verification**: Artifacts are signed (Cosign, GPG), verified, and published.
*   **Release automation**: Draft → latest releases, SLSA provenance, and SBOM attached.
*   **Dependency updates**: Automated via Dependabot and nightly auto-update workflows.

---

## 10. Summary

The build system is the technical foundation for **speed, security, reproducibility, and enterprise reliability**—enabling the production of **high-quality, low-vulnerability container images** at scale, with full automation and auditability.

---
