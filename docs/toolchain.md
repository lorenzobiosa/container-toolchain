# UBI-9 Builder Toolchain Design

## 1. Purpose

This document describes the **design, structure, and guarantees** of the UBI-9 Builder Toolchain—the core asset enabling high-performance, reproducible, secure, and cross-architecture builds.

---

## 2. Design Principles

| Principle       | Description                                        |
| --------------- | -------------------------------------------------- |
| Determinism     | Identical inputs produce identical outputs         |
| Isolation       | All builds occur in a fully controlled environment |
| Source-first    | All packages compiled from source                  |
| Reproducibility | Stable results across environments                 |
| Minimalism      | Only required tooling is included                  |
| Performance     | Optimized for fast builds                          |
| Security        | No opaque binaries, full provenance                |

---

## 3. Toolchain Composition

*   **Base OS:** Red Hat Universal Base Image 9 (UBI 9)
    *   Enterprise support, stable ABI, certified security lifecycle
*   **Compiler stack:**
    *   GCC, Clang, LLD, assembler toolchains, standard libraries
    *   All versions **strictly pinned** in `/build/config/tool-versions.json`
*   **Build & packaging tools:**
    *   `make`, `cmake`, autotools, packaging utilities
    *   Cross-compilation frameworks (ARM64 sysroot, PKG\_CONFIG, etc.)
*   **No dynamic resolution:**
    *   All tools and versions are resolved at build time, never at runtime

---

## 4. Cross-Architecture Support

*   **Single toolchain image** produces both **amd64** and **arm64** packages
*   Includes:
    *   Architecture-specific compilers and sysroots
    *   Emulation/cross-build tooling
    *   Consistent runtime environments for both architectures
*   **Guarantee:** Functional parity and reproducibility across architectures

---

## 5. Version & Dependency Management

*   All toolchain versions:
    *   Declared explicitly in `/build/config/tool-versions.json`
    *   Version-pinned and auditable in source control
    *   Immutable per release (no drift between builds)
*   **Automated updates:**
    *   Nightly auto-update workflow and Dependabot for dependency hygiene

---

## 6. Performance Characteristics

| Operation                | Typical Time |
| ------------------------ | ------------ |
| Build toolchain image    | \~10 minutes |
| Multi-arch package build | \~5 minutes  |

*   Achieved via:
    *   Layer reuse in Docker builds
    *   Optimized build ordering
    *   Minimal dependency resolution and cache usage

---

## 7. Security Model

*   **No precompiled third-party binaries**
*   **Full source provenance** for all artifacts
*   **Deterministic rebuilds** (bit-for-bit identical outputs)
*   **Cryptographic artifact signing** (Cosign, GPG)
*   **Controlled trust boundaries** (all build steps in container, no host leakage)

---

## 8. Operational Guarantees

*   Reproducible builds (identical outputs for identical inputs)
*   Cross-architecture consistency (amd64/arm64)
*   Minimal runtime footprint (only essential tools in final images)
*   Strong security posture (signed, verified, SBOM’d artifacts)
*   Enterprise compliance readiness (audit logs, provenance, SLSA attestation)

---

**Note:**  
For overall architecture, CI/CD, and governance, see \[architecture.md] and \[ci-cd.md].  
For implementation details, refer to the builder Dockerfiles and `/build/config/tool-versions.json`.

---
