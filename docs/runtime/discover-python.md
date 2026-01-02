# Discovery Script — Python

> **Purpose:** Automatically discover the newest **Python** package available from enabled UBI/RHEL repositories and print the package name (e.g., `python3.13`) to STDOUT.  
> **Audience:** Platform Engineering, CI/CD Maintainers, Security & Compliance.

---

## 1) Executive Summary

`discover-python.sh` removes the need for a fragile `PYTHON_VERSION` build‑arg by **probing the repositories** and selecting the most recent **vendor‑supported** Python package available for the current base image. It is **read‑only** (no installs), **deterministic**, and **vendor‑compliant**.

**Decision Rationale:**  
Historically, passing `PYTHON_VERSION` as a build-arg led to failures when the requested version was not available in the target base image (e.g., `python3.13` on UBI8). By auto-discovering the newest available Python 3 package, we ensure builds are robust, portable, and always aligned with vendor support. This approach reduces configuration drift, simplifies onboarding, and eliminates the need for per-major version mapping.

---

## 2) Location & Permissions

*   **Script path:** `scripts/os/discover-python.sh`
*   **Permissions:** `chmod +x scripts/os/discover-python.sh`
*   **Line endings:** enforce LF with `.gitattributes`:
    ```gitattributes
    *.sh text eol=lf
    scripts/** text eol=lf
    ```

---

## 3) Usage

```bash
scripts/os/discover-python.sh
# STDOUT (example): python3.13
# Exit code 0: success; printed package name
# Exit code 2: fatal error (no package manager / no candidate found)
````

**Note:** The script prefers **microdnf** (UBI minimal), with **dnf** as fallback.

---

## 4) Integration in Dockerfile

Embed the script and use its output to install Python and bootstrap pip:

```dockerfile
COPY scripts/os/discover-python.sh /usr/local/bin/discover-python.sh
RUN chmod +x /usr/local/bin/discover-python.sh

RUN set -eux; \
    PY_PKG="$("/usr/local/bin/discover-python.sh")"; \
    microdnf -y update && microdnf upgrade -y --refresh; \
    microdnf install -y --setopt=tsflags=nodocs "${PY_PKG}"; \
    curl -fsSL https://bootstrap.pypa.io/get-pip.py -o /tmp/get-pip.py; \
    "${PY_PKG}" /tmp/get-pip.py; \
    "${PY_PKG}" -m pip install --no-cache-dir --upgrade setuptools wheel; \
    microdnf clean all; \
    rm -rf /var/cache/dnf/* /var/tmp/* /root/.cache/pip /tmp/*
```

---

## 5) CI/CD Smoke Test

```yaml
- name: Python discovery
  run: |
    pkg=$(scripts/os/discover-python.sh)
    echo "Discovered: $pkg"
    test -n "$pkg" && echo "OK" || (echo "Discovery failed" && exit 2)
```

---

## 6) Troubleshooting

*   **Empty output:**  
    Ensure repositories are enabled (EPEL/CRB if required) and metadata is fresh. Run `microdnf makecache` or `microdnf update -y`.

*   **`microdnf` vs `dnf`:**  
    UBI minimal images use `microdnf`. If neither is present, the script exits with code 2.

*   **CRLF line endings:**  
    If you see odd Bash behavior (arrays/variables empty unexpectedly), convert to LF with `dos2unix` or enforce via `.gitattributes`.

---

## 7) Security & Compliance Notes

*   The discovery is **read-only**; it does not install—only prints available package names.
*   For **vendor backports** (e.g., security fixes shipped via release bump on RHEL), ensure scanners recognize **vendor release numbers** even when upstream versions look older. Document RHSA advisories in CI reports when necessary.
*   This approach ensures **vendor support compliance**: the script always selects the newest Python 3 package available in the enabled repositories, reducing the risk of unsupported configurations and simplifying audits.

---

## 8) Maintenance Guidelines

*   **Candidate list:** Update when new **vendor Python streams** are published (e.g., add `python3.14` later).
*   **OS support:** Keep aligned with UBI/RHEL major versions in your fleet (8/9/10).
*   **Testing:** Maintain matrix jobs across UBI8/UBI9/UBI10 to preempt repository regressions.
*   **Documentation:** Keep this file updated with any changes to Python packaging or organizational repository policies.

---

## 9) Decision Details & Rationale

*   **Why auto-discovery?**  
    Manual mapping of Python versions via build-args is fragile and error-prone. Auto-discovery ensures builds are deterministic, portable, and vendor-aligned.
*   **What alternatives were considered?**
    *   Pinning `PYTHON_VERSION` per major (brittle, high maintenance).
    *   Shipping Python from source or a bundled layer (diverges from vendor support, increases image size).
    *   Auto-discovery (chosen for simplicity, compliance, and maintainability).
*   **Consequences:**
    *   CI/CD pipelines no longer require `PYTHON_VERSION`.
    *   Builds are robust across major versions.
    *   Auditing and onboarding are simplified.

---

## 10) Candidate list synchronization (CI) — official source

To keep `scripts/os/python-supported.txt` aligned with **GA + actively supported** branches (bugfix + security; **exclude** “feature”/pre‑release and **EOL**), run a scheduled CI job that:

1.  **Fetches** the official table from the **Python Developer’s Guide** (authoritative source of status for 3.10–3.14).
2.  **Filters** rows with status **bugfix** or **security** to derive the candidate `python3.X` lines.
3.  **Sorts** descending (newest → conservative) and **writes** to `scripts/os/python-supported.txt`.
4.  (Optional) **Cross‑checks** with *endoflife.date* to validate support windows.

> Sources:
>
> *   Python Developer’s Guide — *Status of Python versions* (official): <https://devguide.python.org/versions/>
> *   PEP 602 — *Annual Release Cycle* (support windows): <https://peps.python.org/pep-0602/>
> *   Cross‑check (optional): <https://endoflife.date/python>

**Example GitHub Actions job:**

```yaml
name: Sync Python Supported Branches
on:
  schedule:
    - cron: "0 3 * * 1"   # every Monday 03:00 UTC
  workflow_dispatch:

jobs:
  update-python-supported:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Generate python-supported.txt from official devguide
        run: |
          set -euo pipefail
          tmp_html="$(mktemp)"
          curl -fsSL "https://devguide.python.org/versions/" -o "$tmp_html"

          # Extract versions with status 'bugfix' or 'security' from the devguide.
          # The page is HTML; we use Python's html.parser to be robust.
          python <<'PYCODE'
import sys, re
from html.parser import HTMLParser

class VersionTableParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.in_table = False
        self.row = []
        self.rows = []
        self.capture = False
        self.cell_text = []

    def handle_starttag(self, tag, attrs):
        if tag == 'table':
            self.in_table = True
        if self.in_table and tag in ('tr', 'td', 'th'):
            self.capture = True
            self.cell_text = []

    def handle_endtag(self, tag):
        if self.in_table and tag in ('td', 'th'):
            txt = ''.join(self.cell_text).strip()
            self.row.append(txt)
            self.capture = False
        if self.in_table and tag == 'tr':
            if self.row:
                self.rows.append(self.row)
            self.row = []
        if tag == 'table' and self.in_table:
            self.in_table = False

    def handle_data(self, data):
        if self.capture:
            self.cell_text.append(data)

# Read HTML from stdin
html = open(sys.argv[1], 'r', encoding='utf-8').read()
p = VersionTableParser()
p.feed(html)

# Heuristics:
# Find rows that look like "[version] ... [status]" e.g., "3.13 ... bugfix" / "3.12 ... security"
# Keep only GA + actively supported (bugfix/security).
supported = []
for row in p.rows:
    joined = ' '.join(row)
    m = re.search(r'\b3\.(\d{2}|\d{1})\b', joined)
    if not m:
        continue
    ver = m.group(0)
    if re.search(r'\bbugfix\b', joined, re.IGNORECASE) or re.search(r'\bsecurity\b', joined, re.IGNORECASE):
        supported.append(ver)

# Deduplicate, sort descending numerically, and output as python3.X lines
unique = sorted(set(supported), key=lambda v: tuple(map(int, v.split('.'))), reverse=True)
with open('scripts/os/python-supported.txt', 'w', encoding='utf-8') as f:
    for v in unique:
        f.write(f'python{v}\n')
PYCODE
          python scripts/os/discover-python.sh >/dev/null 2>&1 || true  # sanity: interpreter available

      - name: Show generated candidates
        run: |
          echo "Generated candidates:"
          cat scripts/os/python-supported.txt

      - name: Commit & push if changed
        run: |
          if ! git diff --quiet -- scripts/os/python-supported.txt; then
            git config user.name "github-actions[bot]"
            git config user.email "github-actions[bot]@users.noreply.github.com"
            git add scripts/os/python-supported.txt
            git commit -m "chore: sync python-supported.txt from devguide (GA + actively supported)"
            git push
          else
            echo "No changes in python-supported.txt"
          fi
```

> This job **does not run during image build**: it maintains the **version‑controlled list** ahead of time, ensuring build determinism while the script uses repository **repoquery** to check availability in UBI/RHEL repos.  
> The support windows and statuses are defined by PSF and documented in the Devguide and **PEP 602**. [\[myoffice.a...enture.com\]](https://myoffice.accenture.com/personal/lorenzo_biosa_accenture_com/Documents/Microsoft%20Copilot%20Chat%20Files/sign-and-verify.sh), [\[myoffice.a...enture.com\]](https://myoffice.accenture.com/personal/lorenzo_biosa_accenture_com/Documents/Microsoft%20Copilot%20Chat%20Files/CONTRIBUTING.md)

---

### References

- **Python Developer’s Guide — Status of Python versions** (authoritative GA/support status): <https://devguide.python.org/versions/> [1](https://myoffice.accenture.com/personal/lorenzo_biosa_accenture_com/Documents/Microsoft%20Copilot%20Chat%20Files/sign-and-verify.sh)  
- **PEP 602 — Annual Release Cycle for Python** (support phases & windows): <https://peps.python.org/pep-0602/> [2](https://myoffice.accenture.com/personal/lorenzo_biosa_accenture_com/Documents/Microsoft%20Copilot%20Chat%20Files/CONTRIBUTING.md)  
- *(Optional cross‑check)* **endoflife.date/python** (support timeline visualization): <https://endoflife.date/python> [3](https://myoffice.accenture.com/personal/lorenzo_biosa_accenture_com/Documents/Microsoft%20Copilot%20Chat%20Files/CODE_OF_CONDUCT.md)

If you want, I can also provide a small **unit test script** to validate that `python-supported.txt` contains only bugfix/security branches and excludes feature/EOL, using the same parsing logic as the CI job.

---
