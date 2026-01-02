#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# discover-go.sh
# ------------------------------------------------------------------------------
# Description : Discover the latest stable Go release compatible with the current
#               Linux architecture (amd64/arm64) using the official go.dev JSON
#               feed, and print FILENAME, VERSION, SHA256 to STDOUT.
#
# Usage       : ./discover-go.sh
# Exit codes  : 0  -> success; 3-line output (FILENAME, VERSION, SHA256)
#               2  -> fatal; no matching stable release, network error, or jq missing
#
# Notes       : - Uses https://go.dev/dl/?mode=json (official feed).
#               - Requires 'jq'; will install it if a supported package manager is present.
#               - Supports x86_64/amd64 and aarch64/arm64 (Linux).
#               - Keep LF (Unix) line endings.
# Author      : Lorenzo Biosa (Biosa Labs) <lorenzo@biosa-labs.com>
# License     : MIT
# ------------------------------------------------------------------------------

set -Eeuo pipefail

# --- Source logging lib
. /usr/local/bin/log.sh

# --- Ensure jq is available (auto-install on UBI/RHEL if possible)
if ! command -v jq >/dev/null 2>&1; then
  if command -v microdnf >/dev/null 2>&1; then
    microdnf -y install jq >/dev/null 2>&1 || true
  elif command -v dnf >/dev/null 2>&1; then
    dnf -y install jq >/dev/null 2>&1 || true
  fi
fi
if ! command -v jq >/dev/null 2>&1; then
  log "ERROR: jq is required but not installed (install 'jq' before running)." >&2
  exit 2
fi

# --- Detect machine arch → Go tarball arch suffix
ARCH="$(uname -m)"
case "${ARCH}" in
  x86_64|amd64)  GO_ARCH="amd64"  ;;
  aarch64|arm64) GO_ARCH="arm64"  ;;
  *)
    log "ERROR: unsupported arch: ${ARCH}" >&2
    exit 2
    ;;
esac

# --- Fetch JSON (newest-first list of releases)
JSON_URL="https://go.dev/dl/?mode=json"
JSON="$(curl -fsS --retry 3 --retry-connrefused --max-time 20 "${JSON_URL}" || true)"
if [ -z "${JSON}" ]; then
  log "ERROR: cannot fetch ${JSON_URL}" >&2
  exit 2
fi

# --- Use jq to select newest stable release and its linux-<arch> tarball (kind=archive)
# We extract: filename, sha256, version (three lines, in this order).
readarray -t OUT < <(printf '%s' "${JSON}" | jq -r --arg arch "${GO_ARCH}" '
  # select first stable release (feed is newest-first)
  first(.[] | select(.stable == true) | .files[]
        | select(.os == "linux" and .arch == $arch and .kind == "archive"))
  | [.filename, .sha256, .version] | .[]
')

if [ "${#OUT[@]}" -ne 3 ]; then
  log "ERROR: no matching stable linux-archive found for arch=${GO_ARCH}" >&2
  exit 2
fi

FILENAME="${OUT[0]}"
SHA256="${OUT[1]}"
VERSION="${OUT[2]}"

# --- Emit outputs (3 lines, exactly as expected by downstream scripts)
printf 'FILENAME=%s\nVERSION=%s\nSHA256=%s\n' "${FILENAME}" "${VERSION}" "${SHA256}"
