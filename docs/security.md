# Security Architecture & Threat Model

## 1. Purpose

This document defines the **security model** for the UBI-9 Multi-Architecture Builder Toolchain and its artifacts, focusing on how the system delivers **secure, auditable, reproducible, and low-vulnerability software supply chains** from source to production.

---

## 2. Security Objectives

| Objective              | Description                                      |
| ---------------------- | ------------------------------------------------ |
| Supply Chain Integrity | No untrusted binaries enter the pipeline         |
| Reproducibility        | Builds are deterministic and verifiable          |
| Artifact Authenticity  | All artifacts are cryptographically signed       |
| Minimal Attack Surface | Runtime images contain only necessary components |
| Defense in Depth       | Multiple security controls at every stage        |
| Compliance             | Audit-ready security posture                     |

---

## 3. Threat Model

**In-Scope Threats:**

*   Dependency tampering
*   Build environment compromise
*   Artifact substitution
*   Unauthorized releases
*   Supply-chain attacks

**Out-of-Scope Threats:**

*   Physical infrastructure compromise
*   Compromise of external hosting providers

---

## 4. Trust Boundaries & Controls

| Boundary            | Controls                                      |
| ------------------- | --------------------------------------------- |
| Source → CI         | PR reviews, protected branches, policy checks |
| CI → Builder        | Immutable, containerized build environment    |
| Builder → Artifacts | Cryptographic signing (Cosign, GPG), SBOM     |
| Artifacts → Release | Signature verification, provenance, SLSA      |

*   **No artifact is promoted without cryptographic validation and provenance.**

---

## 5. Source-Based Security Model

*   All software is **compiled from source** inside the controlled toolchain.
*   **No opaque or prebuilt binaries** are allowed in the pipeline.
*   All build steps are **containerized** and isolated from the host.

---

## 6. Artifact Integrity & Verification

*   Every artifact is:
    *   **Signed** during the release stage (Cosign, GPG)
    *   **Verified** before publication (keyful/keyless, SLSA attestation)
    *   Associated with **immutable provenance metadata** (SBOM, checksums)
*   **Unsigned or unverifiable artifacts are never released.**

---

## 7. Vulnerability Reduction Strategy

*   **Eliminate prebuilt binary dependencies** (source-only builds)
*   **Minimize runtime image contents** (only essential packages)
*   **Use UBI 9 minimal runtime base**
*   **Enforce deterministic builds** (identical outputs for identical inputs)
*   **Automated security scanning** (CodeQL, Gitleaks, SARIF reporting)

---

## 8. Incident Response & Recovery

If a compromise is detected:

*   **Invalidate builds** and revoke affected artifacts
*   **Rotate signing keys** (Cosign, GPG)
*   **Re-execute pipeline** from a clean state
*   **Preserve full audit trail** for investigation

---

## 9. Compliance & Auditability

*   **Full traceability**: All steps, artifacts, and signatures are logged and auditable
*   **SBOM (SPDX JSON)** and **SLSA provenance** attached to every release
*   **Immutable versioning**: Every release is uniquely tagged and cannot be altered
*   **Automated policy enforcement**: PR governance, branch protection, dependency pinning

---

## 10. Summary

The security architecture ensures that all released software is **trusted, auditable, reproducible, and extremely low in vulnerability exposure**—with layered controls, cryptographic validation, and automated compliance at every stage.

---
