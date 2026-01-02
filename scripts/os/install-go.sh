#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# install-go.sh
# ------------------------------------------------------------------------------
# Description : Install the latest stable Go for the current Linux architecture.
#               Verifies SHA256 and installs into ${GOROOT}, prepares ${GOPATH},
#               and writes ccache conf.
#
# Usage       : ./install-go.sh
# Exit codes  : 0  -> success
#               2  -> fatal error (network/sha256/unsupported arch/etc.)
#
# Notes       : - Requires curl, tar, sha256sum.
#               - Discovery-only flow: calls discover-go.sh to obtain the newest
#                 stable release for the current arch (amd64/arm64).
#               - Keep LF line endings.
# Author      : Lorenzo Biosa (Biosa Labs) <lorenzo@biosa-labs.com>
# License     : MIT
# ------------------------------------------------------------------------------

set -Eeuo pipefail

# --- Source logging lib
. /usr/local/bin/log.sh

GOROOT="${GOROOT:-/usr/local/go}"
GOPATH="${GOPATH:-/opt/go}"
CCACHE_SIZE="${CCACHE_SIZE:-5.0G}"

# --- Discover newest stable FILENAME, VERSION, SHA256 (3 lines from discover-go.sh)
FILENAME=""
VERSION=""
SHA256=""

if ! command -v /usr/local/bin/discover-go.sh >/dev/null 2>&1; then
  log "ERROR: /usr/local/bin/discover-go.sh not found. Copy it into the image first." >&2
  exit 2
fi

readarray -t OUT < <(/usr/local/bin/discover-go.sh)
for line in "${OUT[@]}"; do
  case "${line}" in
    FILENAME=*) FILENAME="${line#FILENAME=}" ;;
    VERSION=*)  VERSION="${line#VERSION=}"  ;;
    SHA256=*)   SHA256="${line#SHA256=}"   ;;
  esac
done

if [[ -z "${FILENAME}" || -z "${VERSION}" || -z "${SHA256}" ]]; then
  log "ERROR: discovery returned incomplete data (FILENAME/VER/SHA256 missing)" >&2
  exit 2
fi

TMP="/tmp/${FILENAME}"
URL="https://go.dev/dl/${FILENAME}"   # official download path
log "Downloading ${VERSION} from ${URL}"
curl -fsSL "${URL}" -o "${TMP}"

# --- Verify SHA256
CALC_SHA="$(sha256sum "${TMP}" | awk '{print $1}')"
if [[ "${CALC_SHA}" != "${SHA256}" ]]; then
  log "ERROR: sha256 mismatch for ${FILENAME}" >&2
  log "       expected: ${SHA256}" >&2
  log "       actual:   ${CALC_SHA}" >&2
  exit 2
fi

# --- Install into ${GOROOT}
log "Installing Go to ${GOROOT}"
rm -rf "${GOROOT}"
tar -C "$(dirname "${GOROOT}")" -xzf "${TMP}"
rm -f "${TMP}"

# --- Prepare GOPATH and ccache
mkdir -p "${GOPATH}/pkg/mod" "${GOPATH}/bin" "/opt/ccache"
printf 'max_size = %s\n' "${CCACHE_SIZE}" > /etc/ccache.conf

log "Installed ${VERSION} to ${GOROOT}. GOPATH=${GOPATH}"
exit 0
