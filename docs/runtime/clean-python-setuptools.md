# Cleanup Script — Remove `setuptools` Residues from Lowest Python Under `/usr/lib`

> **Purpose:** Delete legacy `setuptools` (and related) files from the **lowest minor Python** `site-packages` under `/usr/lib`, to eliminate scanner findings (file‑based CVE reports) without removing system RPMs or breaking vendor dependencies.  
> **Audience:** Platform Engineering, CI/CD Maintainers, Security & Compliance.  
> **Script:** `scripts/os/clean-python-setuptools.sh`

---

## 1) Executive Summary

Security scanners often report vulnerabilities based on **file presence** (e.g., `setuptools-53.0.0.dist-info/METADATA`) residing in `site-packages` of older Python minors shipped by the base OS. Even when toolchains are updated elsewhere (e.g., Python 3.13 via pip), those **legacy files** may remain on disk and trigger findings.

This script implements a **minimal, deterministic** cleanup policy:

1. **Discover** Python directories under `/usr/lib` (`/usr/lib/python<MAJOR>.*`).  
2. **Select** the **lowest minor** (e.g., `python3.10` if 3.10, 3.11, 3.12 are present).  
3. **Remove** well‑known `setuptools` and legacy residues in `/usr/lib/<lowest>/site-packages/`:
   - `setuptools*`  
   - `pkg_resources*`  
   - `_distutils_hack*`  
   - `easy_install.py`

This approach addresses file‑based detections **without** uninstalling RPMs (which may be required by system packages), preserving **vendor support compliance**.

---

## 2) Scope & Policy

- **In-scope paths:** `/usr/lib/python3.X/site-packages/` for the **lowest minor** found.  
- **Out of scope (by design):**  
  - `/usr/local/lib/python3.X/site-packages/`  
  - Virtual environments (e.g., `/opt/venv/.../site-packages`)  
  - Higher minors under `/usr/lib` (e.g., `python3.11`, `python3.12`)
  
> If your scanner reports files outside `/usr/lib` or in higher minors, either:
> - run the same logic for **each** `/usr/lib/python3.*` directory; or  
> - extend your policy to include `/usr/local/lib` and known venv roots (e.g., `/opt/venv`).

---

## 3) Script Location & Permissions

- **Repository path:**  
  `scripts/os/clean-python-setuptools.sh`
- **Runtime path in image:**  
  `/usr/local/bin/clean-python-setuptools.sh`
- **Permissions:**  
  ```bash
  chmod +x scripts/os/clean-python-setuptools.sh
  ```

*   **Line Endings:** enforce LF with `.gitattributes`:
    ```gitattributes
    *.sh text eol=lf
    scripts/** text eol=lf
    ```

---

## 4) Usage

```bash
# Run as root (container or host with appropriate privileges)
 /usr/local/bin/clean-python-setuptools.sh

# Exit codes:
# 0 -> success (cleanup performed or nothing to do)
# 1 -> no /usr/lib/python3.* directories found
# 2 -> site-packages not found for the selected (lowest) version
```

**What it does:**

*   Finds `/usr/lib/python3.*` directories and sorts them numerically (lowest first).
*   Picks the **lowest** (e.g., `/usr/lib/python3.10`).
*   Removes: `setuptools*`, `pkg_resources*`, `_distutils_hack*`, `easy_install.py` from `site-packages`.

---

## 5) Integration in Dockerfile

Place the script and run it **after** upgrading your “target” Python toolchain (pip/setuptools/wheel) to modern, supported versions:

```dockerfile
# Copy & enable
COPY scripts/os/clean-python-setuptools.sh /usr/local/bin/clean-python-setuptools.sh
RUN chmod +x /usr/local/bin/clean-python-setuptools.sh

# Example: after you've discovered PY_VER (e.g., python3.13) and upgraded tooling
RUN set -eux; \
    "${PY_PKG}" -m pip install --no-cache-dir --upgrade pip "setuptools>=78.1.1" wheel; \
    /usr/local/bin/clean-python-setuptools.sh
```

> This sequence ensures your primary toolchain is updated **first**, then legacy residues under `/usr/lib` are removed to quiet file‑based scanner findings.

---

## 6) Operational Safety

*   **Vendor compliance:** RPMs that provide `python3.9dist(setuptools)` may be required by system packages. This script **does not remove RPMs**; it only deletes leftover files that trigger findings.
*   **Idempotency:** Running multiple times is safe; missing files are ignored.
*   **Least impact:** Only touches `/usr/lib/<lowest>/site-packages`.
*   **Auditing:** Consider logging the list of deleted paths to your build logs (or use the variant that prints before deletion if you need change records).

---

## 7) Security & Compliance Notes

*   **File-based scanners:** Most tools flag vulnerabilities by detecting files and `.dist-info` metadata rather than active usage. Removing these files in legacy locations usually resolves reports without altering system dependencies.
*   **Governance:** Retain a record of cleanup runs within CI logs (timestamp, selected version, target path).
*   **Separation of concern:** Keep “upgrade to modern toolchain” and “cleanup of legacy residues” as distinct steps for transparency.

---

## 8) Troubleshooting

*   **`Exit 1: No /usr/lib/python3.* dirs found`**  
    The image may not ship system Python under `/usr/lib`. Confirm your base image layout; if needed, extend the script to scan `/usr/local/lib` or use the interpreter‑guided approach.

*   **`Exit 2: site-packages not found`**  
    The lowest minor directory may not contain `site-packages`. Verify distribution layout; consider iterating all minors or switching to interpreter‑guided detection.

*   **Scanner still reports residues**  
    Ensure findings are not from other locations (e.g., `/usr/local/lib/python3.X/site-packages` or virtual envs). Add additional cleanup logic where appropriate.

---

## 9) Extensibility (Optional)

If your policy evolves to clean **all minors** or other roots:

*   Loop over **every** `/usr/lib/python3.*` dir (not just lowest).
*   Add additional roots: `/usr/local/lib/python3.*/site-packages`, `/opt/venv/**/site-packages`.
*   Integrate with an interpreter‑guided method (`sysconfig.get_paths()["purelib"]`) for precise target paths.

---

## 10) Example CI Step (Container)

```yaml
- name: Run setuptools cleanup in test container
  run: |
    docker run --rm ghcr.io/<owner>/ubi-toolchain-builder:latest \
      bash -lc '/usr/local/bin/clean-python-setuptools.sh'
```

> This confirms the script executes cleanly in the built image and logs the selected directory / actions.

---

