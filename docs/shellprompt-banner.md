# 🖥️ Shell Prompt & Banner Configuration

> **Purpose:** This guide explains how to enable, disable, and customize the **enterprise welcome banner** and the **professional PS1 prompt** provided by the toolchain.  
> It applies to interactive shells inside the builder image and to any environment where `/etc/profile.d/00-welcome.sh` and `/etc/profile.d/10-ps1.sh` are present.

---

## 1) Components

- **Welcome banner** — `/etc/profile.d/00-welcome.sh`  
  Displays a concise, professional banner with image metadata (title, description, vendor, author).
- **PS1 prompt** — `/etc/profile.d/10-ps1.sh`  
  Shows time, `user@host`, current working directory, with clean color coding and a lightweight `ls --color=auto` alias.

> Both scripts are **no‑op** when the shell is not interactive or when disabled via environment variables.  
> Both respect **color configuration** (`NO_COLOR` or `PROMPT_ENABLE_COLORS=0`).

---

## 2) Enabling / Disabling

### Enable banner (default off unless configured at build time)
```bash
export WELCOME_ENABLE=1
````

### Disable banner

```bash
unset WELCOME_ENABLE          # or:
export WELCOME_ENABLE=0
```

### Enable prompt colors

```bash
export PROMPT_ENABLE_COLORS=1
```

### Disable all colors (banner + prompt)

```bash
export NO_COLOR=1
# or, prompt only:
export PROMPT_ENABLE_COLORS=0
```

> **Note:** If `NO_COLOR` is set, colors are disabled regardless of `PROMPT_ENABLE_COLORS`.  
> The scripts initialize color variables only when appropriate.

---

## 3) Banner Customization

You can override any banner field at **runtime** (or pass them as **build args** when baking the image).

### Default variables (runtime)

```bash
export IMAGE_TITLE="UBI9 Container Toolchain Builder"
export IMAGE_DESCRIPTION="UBI9-based builder (amd64 host, arm64 cross sysroot)"
export IMAGE_VENDOR="Your Org"
export AUTHOR_EMAIL="devops@your-org.com"
export COMPANY_NAME="Your Org"
```

### Example — Human‑friendly banner

```bash
export WELCOME_ENABLE=1
export IMAGE_TITLE="UBI9 Builder — Multi-Arch Toolchain"
export IMAGE_DESCRIPTION="Deterministic builds, amd64 & arm64, Cosign+GPG."
export IMAGE_VENDOR="Biosa Labs"
export AUTHOR_EMAIL="lorenzo@biosa-labs.com"
export COMPANY_NAME="Biosa Labs"
```

**Result:**  
A green horizontal delimiter, bold white title and description, author line, and closing delimiter—rendered only on interactive shells.

---

## 4) Prompt Customization (PS1)

The prompt defaults to:

*   **Time** (HH:MM, 24h)
*   **username\@host**
*   **working directory**
*   Newline + `›` chevron

### Disable or Force Colors

```bash
export NO_COLOR=1                # disable
# OR:
export PROMPT_ENABLE_COLORS=1    # enable
```

### Example — Minimal white prompt (no colors)

```bash
export NO_COLOR=1
# open a new interactive shell, PS1 will render without color sequences
```

### Example — Colored prompt with chevron

```bash
export PROMPT_ENABLE_COLORS=1
# PS1 becomes something like:
# [time] user@host /path
# ›
```

### Alias provided

```bash
alias ls='ls --color=auto'
```

---

## 5) Loading Behavior & Safety

*   Scripts exit early if:
    *   The shell is **not** interactive (`case "$-" in *i* )`),
    *   `$BASH` is not set (non‑Bash shell),
    *   Banner/prompt are disabled via env.
*   `PROMPT_COMMAND` is **safely appended** (no overwrite) to avoid conflicts with other prompt logic (e.g., venv, direnv, starship).

---

## 6) Using in Docker Builds (Build Args)

When building the **builder image**, you can pass **build args** to set defaults:

```bash
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t ghcr.io/<owner>/ubi9-toolchain-builder:latest \
  -f build/Dockerfile \
  --push \
  --build-arg WELCOME_ENABLE=1 \
  --build-arg PROMPT_ENABLE_COLORS=1 \
  --build-arg IMAGE_TITLE="UBI9 Container Toolchain Builder" \
  --build-arg IMAGE_DESCRIPTION="UBI9-based builder with ARM64 sysroot" \
  --build-arg IMAGE_VENDOR="Your Org" \
  --build-arg IMAGE_LICENSES="MIT" \
  .
```

> These become image defaults; users can **override at runtime** inside containers.

---

## 7) Using Inside a Container (Runtime)

### Set environment on `docker run`

```bash
docker run --rm -it \
  -e WELCOME_ENABLE=1 \
  -e PROMPT_ENABLE_COLORS=1 \
  -e IMAGE_TITLE="Multi-Arch Toolchain" \
  -e IMAGE_DESCRIPTION="Deterministic builds, Cosign+GPG" \
  -e IMAGE_VENDOR="Your Org" \
  ghcr.io/<owner>/ubi9-toolchain-builder:latest \
  bash
```

### Persisting across sessions

Add exports to your init script (e.g., `/etc/profile`, `~/.bashrc`) in your base image:

```bash
echo 'export WELCOME_ENABLE=1'    | tee -a ~/.bashrc
echo 'export PROMPT_ENABLE_COLORS=1' | tee -a ~/.bashrc
```

---

## 8) Common Recipes

### Quiet shells (CI logs)

```bash
export WELCOME_ENABLE=0
export PROMPT_ENABLE_COLORS=0
export NO_COLOR=1
# Result: no banner, neutral PS1 (or default of the shell), no color noise in logs
```

### Branded builder for a team

```bash
export WELCOME_ENABLE=1
export PROMPT_ENABLE_COLORS=1
export IMAGE_TITLE="Your Team — Toolchain Builder"
export IMAGE_DESCRIPTION="Multi-arch builds; secure & reproducible"
export IMAGE_VENDOR="Your Org"
export AUTHOR_EMAIL="team@your-org.com"
export COMPANY_NAME="Your Org"
```

### Readability in restricted terminals

```bash
export NO_COLOR=1
# Use non-color prompt in limited terminals or when pasting text in tickets/logs
```

---

## 9) Troubleshooting

**Banner not showing?**

*   Ensure you’re in an **interactive Bash shell** (`echo $-` contains `i`).
*   Check `WELCOME_ENABLE=1` is actually exported and not overridden.
*   If `NO_COLOR=1`, the banner still shows (but without color). If you want it off, set `WELCOME_ENABLE=0`.

**Prompt not colored?**

*   Colors are disabled if `NO_COLOR=1`.
*   Set `PROMPT_ENABLE_COLORS=1` and ensure no other prompt tool (starship/direnv) overrides PS1 later.

**Conflicts with other prompt managers?**

*   The script **appends** to `PROMPT_COMMAND` safely.  
    If another tool replaces PS1 after our script runs, ensure loading order or explicitly set your preferred PS1 at the end of `~/.bashrc`.

**Non‑Bash shells (zsh/fish)?**

*   These scripts target Bash. For zsh/fish, porting is required (PS1 & hooks differ).  
    Alternatively, run Bash (`bash -l`) for interactive sessions.

---

## 10) Best Practices

*   **Keep it simple:** Use short titles/descriptions—fast, readable banners.
*   **Respect automation:** Disable banner/colors in non‑interactive CI contexts.
*   **Standardize branding:** Provide org‑level defaults at image build time, allow runtime overrides for teams.
*   **Accessibility:** Enable `NO_COLOR` when screen readers or monochrome terminals are in use.

---

## 11) Quick Reference

### Env vars (banner)

*   `WELCOME_ENABLE` — `1` to enable, `0` or unset to disable
*   `IMAGE_TITLE` — title line (bold)
*   `IMAGE_DESCRIPTION` — description line (bold gray)
*   `IMAGE_VENDOR` — shown in “Author:” line
*   `AUTHOR_EMAIL` — shown in angled brackets
*   `COMPANY_NAME` — copyright line

### Env vars (prompt)

*   `PROMPT_ENABLE_COLORS` — `1` to enable colors
*   `NO_COLOR` — disables all ANSI color sequences (prompt & banner)

---

## 12) Files & Paths

*   Banner script: `/etc/profile.d/00-welcome.sh`
*   Prompt script: `/etc/profile.d/10-ps1.sh`
*   Included by default in the **builder image**; you can copy them to other images if needed.

---

## 13) Links

*   Main Usage Guide: `docs/USAGE.md`
*   Builder Image Workflow: `.github/workflows/build-image.yml`
*   Toolchain Build Workflow: `.github/workflows/build-toolchain.yml`

---

**That’s it!**  
With these settings, your shells feel professional, consistent, and informative—without getting in the way of CI logs or automation. Tailor them per environment and keep colors off where clarity is paramount.

---
