#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# discover-epel.sh
# ------------------------------------------------------------------------------
# Description : Discover the correct EPEL release URL automatically based on the
#               OS major version (RHEL/UBI derivatives) and print it to
#               STDOUT. Intended for container builds to avoid hardcoding EPEL.
#
# Usage       : ./discover-epel.sh
# Exit codes  : 0  -> success; URL printed (e.g., https://.../epel-release-latest-9.noarch.rpm)
#               2  -> fatal error (OS major not determinable / unsupported)
#
# Notes       : - Reads /etc/os-release first; falls back to `rpm -E %{rhel}`.
#               - Keep this file with LF (Unix) line endings to avoid parsing issues.
#
# Author      : Lorenzo Biosa
# Organization: Biosa Labs
# Contact     : lorenzo@biosa-labs.com
# License     : MIT
# ------------------------------------------------------------------------------

set -Eeuo pipefail

# --- Source logging lib
. /usr/local/bin/log.sh

# --- Determine OS version from /etc/os-release (preferred)
OS_VERSION_ID=""
if [[ -f /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  OS_VERSION_ID="${VERSION_ID:-}"
fi

# --- Fallback: query RHEL macro via rpm to get the major version
if [[ -z "${OS_VERSION_ID}" ]] && command -v rpm >/dev/null 2>&1; then
  OS_VERSION_ID="$(rpm -E '%{rhel}' 2>/dev/null || true)"
fi

# --- Extract major (first numeric component)
MAJOR=""
if [[ -n "${OS_VERSION_ID}" ]]; then
  MAJOR="${OS_VERSION_ID%%.*}"
fi

# --- Validate major and emit appropriate URL
if [[ -z "${MAJOR}" ]]; then
  log "ERROR: cannot determine OS major version" >&2
  exit 2
fi

case "${MAJOR}" in
  8|9|10)
    echo "https://dl.fedoraproject.org/pub/epel/epel-release-latest-${MAJOR}.noarch.rpm"
    ;;
  *)
    log "ERROR: unsupported OS major '${MAJOR}'" >&2
    exit 2
    ;;
esac
