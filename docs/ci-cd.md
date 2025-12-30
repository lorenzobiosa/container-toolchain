# CI/CD Pipeline Architecture

## 1. Overview

This document describes the **CI/CD pipeline** for the UBI-9 Multi-Architecture Builder Toolchain, detailing how the system automates the lifecycle from **source to signed, production-grade artifacts**.

The pipeline enforces **performance, security, reproducibility, and governance** at every stage, leveraging modular GitHub Actions workflows.

---

## 2. CI/CD Objectives

| Objective       | Description                                   |
| --------------- | --------------------------------------------- |
| Automation      | Zero manual steps in production pipeline      |
| Performance     | Sub-15-minute total pipeline for full release |
| Reproducibility | Identical outputs across environments         |
| Security        | End-to-end artifact trust enforcement         |
| Governance      | Policy enforcement and compliance             |
| Scalability     | Stateless, parallel execution                 |

---

## 3. Pipeline Stages & Implementation

### 3.1 Source Validation

*   **Triggers:** Pull requests, pushes to protected branches, release tags
*   **Controls:**
    *   Policy enforcement (PR governance, semantic titles, checklists)
    *   Linting & validation
    *   Static analysis (CodeQL, \[codeql.yml])
    *   Secret scanning (Gitleaks, \[security.yml])

### 3.2 Builder Toolchain Build

*   **Workflow:** \[build-image.yml]
*   **Actions:**
    *   Build UBI-9 builder image (multi-arch, pinned versions)
    *   Validate presence of prompt/banner scripts
    *   Push to GHCR with metadata and labels
*   **Duration:** \~10 minutes

### 3.3 Package & Image Build

*   **Workflow:** \[build-toolchain.yml]
*   **Actions:**
    *   Cross-build `kubectl`, `oc`, `rancher` for amd64/arm64
    *   Restore and use CI caches (Go, DNF, ccache)
    *   Run smoke tests on produced binaries
    *   Upload artifacts for signing/release
*   **Duration:** \~5 minutes

### 3.4 Artifact Signing & Verification

*   **Workflow:** \[build-toolchain.yml] (job: sign-and-release)
*   **Actions:**
    *   Sign artifacts with Cosign (keyful/keyless) and GPG
    *   Generate SBOM (Syft, SPDX JSON)
    *   Verify signatures and provenance
    *   Attach all signatures and SBOM to release

### 3.5 Release & Publication

*   **Workflow:** \[build-toolchain.yml] (job: sign-and-release)
*   **Actions:**
    *   Draft → latest GitHub Release with auto-generated notes (\[releases.yml])
    *   Attach all artifacts, checksums, SBOM, SLSA provenance
    *   SLSA attestation via \[slsa-generic-generator]

---

## 4. Governance & Controls

*   **PR Governance:**
    *   Enforced via \[pr-governance.yml]: semantic PR titles, checklists, auto-labeling, issue linking
*   **Branch Protection:**
    *   Mandatory reviews, protected branches
*   **Dependency Management:**
    *   Automated via \[dependabot.yml] and \[auto-update.yml] (nightly pin bump for toolchain versions)
*   **Security Policy:**
    *   CodeQL, Gitleaks, and SARIF upload for code scanning dashboards

---

## 5. Failure Model

*   **Stateless execution:** Each job is isolated; failures leave no persistent state
*   **Deterministic rebuilds:** Any pipeline can be retried with identical results
*   **Safe retries:** All caches and artifacts are managed by CI; no manual cleanup required

---

## 6. Auditability & Compliance

Each pipeline execution produces:

*   Full logs (build, test, signing, release)
*   Artifact hashes and signed checksums
*   SBOM (SPDX JSON)
*   SLSA provenance attestation
*   Traceable release history (auto-generated changelog, immutable tags)

---

## 7. Pipeline Reference

*   \[build-image.yml] — Builder image (multi-arch, GHCR)
*   \[build-toolchain.yml] — Cross-build, sign, release, SLSA
*   \[auto-update.yml] — Nightly tool pin bump
*   \[pr-governance.yml] — PR hygiene, labeling, compliance
*   \[codeql.yml], \[security.yml] — Security scanning
*   \[dependabot.yml] — Dependency update policy
*   \[releases.yml] — Release notes categories

---

## 8. Summary

The CI/CD pipeline delivers **fully automated, high-performance, and enterprise-governed** software supply chain, transforming source code into **signed, auditable, production-ready artifacts** with minimal human intervention.

---
