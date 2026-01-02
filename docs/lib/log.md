# Logging Utility — Unified Logging for Container Builds & Scripts

> **Purpose:** Provide a consistent, enterprise-grade logging interface for all scripts and Dockerfile RUN steps in the UBI/RHEL toolchain builder.  
> **Audience:** Platform Engineering, CI/CD Maintainers, Security & Compliance.  
> **Script:** `scripts/lib/log.sh`

---

## 1) Executive Summary

The logging utility (`log.sh`) standardizes log output across all installation, configuration, and build scripts. It ensures:
- **Uniform timestamps** (UTC ISO-8601)
- **Consistent color coding** (with NO_COLOR override)
- **Standardized log prefix and product name**
- **Banner header/footer with build duration**
- **All logs to stderr** for clear separation from machine-readable output

This approach improves traceability, auditability, and developer experience in CI/CD pipelines and interactive builds.

---

## 2) Location & Usage

- **Script path:**  
  `scripts/lib/log.sh`
- **Runtime path in image:**  
  `/usr/local/bin/log.sh`
- **Permissions:**  
  ```bash
  chmod +x scripts/lib/log.sh
  ```
- **Line endings:** enforce LF with `.gitattributes`:
  ```gitattributes
  *.sh text eol=lf
  scripts/** text eol=lf
  ```

---

## 3) How to Use

**Source the library in any shell script or Dockerfile RUN step:**

```bash
. /usr/local/bin/log.sh
```

**Then use the provided functions:**

*   `log "Your message here"` — log a message with timestamp, prefix, and colors
*   `header_build` — print a standardized build start banner
*   `footer_build` — print a standardized build completion banner with duration

**Example in a script:**

```bash
#!/usr/bin/env bash
set -euo pipefail
. /usr/local/bin/log.sh

header_build
log "Starting Python installation..."
# ... installation steps ...
log "Python installed successfully."
footer_build
```

**Example in Dockerfile:**

```dockerfile
RUN set -eux; \
    . /usr/local/bin/log.sh; \
    header_build; \
    log "Installing Go..."; \
    # ... installation steps ...
    footer_build
```

---

## 4) Features

*   **Timestamp:** All log entries include UTC ISO-8601 timestamp for auditability.
*   **Color coding:** ANSI colors are enabled by default; set `NO_COLOR=1` to disable.
*   **Prefix:** Default is `[ubi9-builder]`, customizable via `LOG_PREFIX` environment variable.
*   **Product name:** Default is `UBI9 Container Toolchain Builder`, customizable via `PRODUCT_NAME`.
*   **Banner:** `header_build` and `footer_build` print decorative banners with author, product, and duration.
*   **stderr output:** All logs go to stderr to preserve formatting and avoid mixing with stdout.

---

## 5) Operational Notes

*   **Idempotency:** Sourcing the script multiple times is safe; `START_EPOCH` is set only once unless overwritten.
*   **Customization:** Override `LOG_PREFIX` and `PRODUCT_NAME` via environment variables for different images or pipelines.
*   **Color policy:** Use `NO_COLOR=1` to disable ANSI codes in environments that do not support color.
*   **Audit trail:** Banner and log lines provide clear traceability for build steps and durations.

---

## 6) Troubleshooting

*   **No color in logs:** Ensure `NO_COLOR` is not set, and your terminal or CI supports ANSI colors.
*   **No logs printed:** Confirm you are sourcing the script and using the `log` function, not just echo.
*   **Banner not shown:** Call `header_build` and `footer_build` at the start and end of your build steps.

---

## 7) Maintenance Guidelines

*   **Keep as a library:** Do not execute commands at source time; only define functions.
*   **Update prefix/product:** When changing image family or branding, update `LOG_PREFIX` and `PRODUCT_NAME` as needed.
*   **Extend as needed:** Add new log levels or formatting functions for future requirements.

---
