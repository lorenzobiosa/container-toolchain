# Discovery Script — EPEL URL

> **Purpose:** Automatically compute the correct **EPEL release URL** based on the OS major version and print it to STDOUT, e.g., `https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm`.  
> **Audience:** Platform Engineering, CI/CD Maintainers, Security & Compliance.

---

## 1) Executive Summary

`discover-epel.sh` removes the need for the `EPEL_RPM_URL` build‑arg. It determines the OS major via `/etc/os-release` (or falls back to `rpm -E '%{rhel}'`) and emits the **EPEL release URL**. This enables **deterministic builds** without hardcoding repository URLs.

**Decision Rationale:**  
Historically, passing `EPEL_RPM_URL` as a build-arg required manual mapping and was error-prone across different base images. By auto-discovering the correct EPEL release URL, we ensure builds are robust, vendor-compliant, and easier to audit. This approach aligns with Red Hat best practices and reduces configuration drift.

---

## 2) Location & Permissions

*   **Script path:** `scripts/os/discover-epel.sh`
*   **Permissions:** `chmod +x scripts/os/discover-epel.sh`
*   **Line endings:** enforce LF with `.gitattributes`:
    ```gitattributes
    *.sh text eol=lf
    scripts/** text eol=lf
    ```

---

## 3) Usage

```bash
scripts/os/discover-epel.sh
# STDOUT (example): https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm
# Exit code 0: success; printed URL
# Exit code 2: fatal error (cannot determine OS major / unsupported)
```

---

## 4) Integration in Dockerfile

Install EPEL based on discovered URL, then enable needed repos and refresh metadata:

```dockerfile
COPY scripts/os/discover-epel.sh /usr/local/bin/discover-epel.sh
RUN chmod +x /usr/local/bin/discover-epel.sh

RUN set -eux; \
    EPEL_URL="$("/usr/local/bin/discover-epel.sh")"; \
    rpm -Uvh "${EPEL_URL}"; \
    sed -i 's/enabled = 0/enabled = 1/g' /etc/yum.repos.d/ubi.repo || true; \
    sed -i 's/enabled = 0/enabled = 1/g' /etc/yum.repos.d/epel* || true; \
    microdnf -y update && microdnf upgrade -y --refresh
```

---

## 5) CI/CD Smoke Test

```yaml
- name: EPEL discovery
  run: |
    url=$(scripts/os/discover-epel.sh)
    echo "Discovered: $url"
    test -n "$url" && echo "OK" || (echo "Discovery failed" && exit 2)
```

---

## 6) Troubleshooting

*   **Missing `/etc/os-release`:**  
    In normal containers `/etc/os-release` exists. If not, the script falls back to `rpm -E '%{rhel}'`. Ensure `rpm` is present.

*   **Network access:**  
    Builds must reach `dl.fedoraproject.org`. In restricted environments, mirror EPEL internally and swap the URL post‑discovery.

---

## 7) Security & Compliance Notes

*   Installing EPEL is **standard** for accessing additional packages on RHEL/UBI; some EPEL content may require **CRB** (CodeReady Builder). Follow organizational policies and audit repository changes in CI/CD logs.
*   Keep a record of **repository state** (enabled, metadata refreshed) for auditability.
*   This approach ensures **vendor support compliance**: the script always selects the correct EPEL release for the OS major, reducing risk of unsupported configurations and simplifying audits.

---

## 8) Maintenance Guidelines

*   **Mirroring:** If you use internal mirrors, consider replacing the discovered URL via policy in CI.
*   **Testing:** Verify discovery before installing packages that depend on EPEL.
*   **Documentation:** Keep this file updated with any changes to EPEL release patterns or organizational repository policies.

---

## 9) Decision Details & Rationale

*   **Why auto-discovery?**  
    Manual mapping of EPEL URLs via build-args is fragile and error-prone. Auto-discovery ensures builds are deterministic, portable, and vendor-aligned.
*   **What alternatives were considered?**
    *   Hardcoding URLs per base image (not portable, high maintenance).
    *   Passing build-args (fragile, error-prone).
    *   Auto-discovery (chosen for simplicity, compliance, and maintainability).
*   **Consequences:**
    *   CI/CD pipelines no longer require `EPEL_RPM_URL`.
    *   Builds are robust across major versions.
    *   Auditing and onboarding are simplified.

---
