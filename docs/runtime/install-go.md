# Go Installation — Auto‑Discovery & Verified Install (UBI/RHEL)

> **Purpose:** Automatically discover the latest **stable Go** release for the current Linux architecture (amd64/arm64), **verify its SHA256**, and install it into the image.  
> **Audience:** Platform Engineering, CI/CD Maintainers, Security & Compliance.  
> **Scripts:**  
> - `scripts/os/discover-go.sh`  
> - `scripts/os/install-go.sh`

---

## 1) Executive Summary

This component replaces inline Dockerfile logic with **parametric, robust scripts** that:

- **Query the official Go downloads feed** (`?mode=json`) to find the **newest stable** release for the current architecture (amd64/arm64).  
- **Verify** the downloaded tarball against the official **SHA256**.  
- **Install** into `${GOROOT}` and prepare `${GOPATH}` and `ccache`.

> **Why `?mode=json`?**  
> The endpoint `https://go.dev/dl/?mode=json` enumerates **available downloadable releases** (including files and checksums), making it suitable for automation. The older `https://go.dev/VERSION?m=text` can return the version powering the website, which is **not guaranteed** to be the latest downloadable release; it is **not recommended** for CI automation.  
> Sources: [Go downloads (dl)](https://go.dev/dl/) · [Use `?mode=json`](https://github.com/golang/go/issues/51135)

---

## 2) Location & Permissions

- **Scripts (repository):**
  ```bash
  scripts/os/discover-go.sh
  scripts/os/install-go.sh
  ```

- **Runtime paths (image):**
  ```bash
  /usr/local/bin/discover-go.sh
  /usr/local/bin/install-go.sh
  ```

- **Permissions:**
  ```bash
  chmod +x scripts/os/discover-go.sh scripts/os/install-go.sh
  ```

- **Line endings:** enforce LF through `.gitattributes`:
  ```gitattributes
  *.sh text eol=lf
  scripts/** text eol=lf
  ```

---

## 3) Environment Variables

*   `GOROOT` (default: `/usr/local/go`)
*   `GOPATH` (default: `/opt/go`)
*   `CCACHE_SIZE` (default: `5.0G`)

> ❗️**Deprecated:** `GO_VERSION` has been **removed**. Pinning is no longer supported in this flow; installation is **discovery‑only**.

---

## 4) Dockerfile Integration

**Copy and enable scripts:**

```dockerfile
# Go discovery/install scripts
COPY scripts/os/discover-go.sh /usr/local/bin/discover-go.sh
COPY scripts/os/install-go.sh   /usr/local/bin/install-go.sh
RUN chmod +x /usr/local/bin/discover-go.sh /usr/local/bin/install-go.sh
```

**Auto‑discover latest stable and install:**

```dockerfile
# Install latest stable Go (arch-aware, verified SHA256)
RUN set -eux; \
    /usr/local/bin/install-go.sh
```

> The scripts map `uname -m` → `linux-amd64` or `linux-arm64`, select the **first stable** release from the official feed, and verify the SHA256 before extracting into `${GOROOT}`.  
> Sources: [Go downloads list & checksums](https://go.dev/dl/), [Use `?mode=json`](https://github.com/golang/go/issues/51135)

---

## 5) Runtime Behavior

*   **Architecture awareness:** detects `x86_64/amd64` and `aarch64/arm64`, selecting the correct tarball suffix (e.g., `go1.25.5.linux-amd64.tar.gz`).
*   **SHA256 verification:** the installer extracts the checksum from the JSON feed and matches it with `sha256sum` before installation.
*   **Paths prepared:**
    *   `${GOROOT}` — the Go toolchain is installed here (existing directory is replaced).
    *   `${GOPATH}` — `pkg/mod` and `bin` are created.
    *   `/etc/ccache.conf` — `max_size` set from `CCACHE_SIZE`.

---

## 6) CI/CD Smoke Test

Add a lightweight job to verify Go is present and correctly installed after the build:

```yaml
- name: Verify Go toolchain
  run: |
    docker run --rm ghcr.io/<owner>/ubi-toolchain-builder:latest \
      bash -lc 'go version && which go && echo "GOROOT=$GOROOT" && echo "GOPATH=$GOPATH"'
```

> On success, `go version` should print the discovered **latest stable** version.

---

## 7) Security & Compliance

*   **Authenticity:** SHA256 verification is performed against the official release feed.
*   **Supply chain hygiene:** downloading directly from the canonical site reduces risk; consider enterprise egress policy and TLS inspection compatibility.
*   **Deterministic behavior:** discovery always targets the **first stable** release listed in the official feed (newest‑first ordering).

> Sources:
>
> *   Official download page and file listings: [go.dev/dl](https://go.dev/dl/)
> *   Guidance to use JSON feed for automation: [golang/go#51135](https://github.com/golang/go/issues/51135)

---

## 8) Troubleshooting

*   **“Unsupported arch” error**  
    The scripts support `amd64` and `arm64`. Ensure you are building for a supported architecture.

*   **Network issues / feed unreachable**  
    Validate connectivity to `https://go.dev/dl/?mode=json` and `https://go.dev/dl/<filename>`. Corporate proxies may require explicit configuration.

*   **SHA256 mismatch**  
    Ensure the tarball was not modified by middleboxes. Re‑fetch; if mismatch persists, verify the feed results and your network path.

---
