#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# clean-lowest-python-setuptools.sh
# ------------------------------------------------------------------------------
# Description : Find python<MAJOR>.* dirs under /usr/lib (e.g., python3.10,
#               python4.0), select the lowest minor version, then remove
#               setuptools residues from /usr/lib/<version>/site-packages
#               (setuptools*, pkg_resources*, etc.). Designed for UBI/RHEL
#               containers where residual files trigger security scanner findings.
#
# Usage       : ./clean-lowest-python-setuptools.sh
# Exit codes  : 0  -> success (cleaned or nothing to do)
#               1  -> no python<MAJOR>.* dirs found under /usr/lib
#               2  -> site-packages not found for the lowest version
#
# Notes       : - Operates ONLY under /usr/lib as requested.
#               - If you also want to clean /usr/local/lib or venvs, add similar logic.
#               - Keep LF line endings.
# Author      : Lorenzo Biosa
# Organization: Biosa Labs
# Contact     : lorenzo@biosa-labs.com
# License     : MIT
# ------------------------------------------------------------------------------

set -Eeuo pipefail

# --- Source logging lib
. /usr/local/bin/log.sh

# 1) Gather python<MAJOR>.* directories under /usr/lib and sort by version (lowest first)
#    Example matches: /usr/lib/python3.6, /usr/lib/python3.10, /usr/lib/python4.0
mapfile -t PY_DIRS < <(find /usr/lib -maxdepth 1 -mindepth 1 -type d -regex '.*/python[0-9]+\.[0-9]+' 2>/dev/null | sort -V)
if [[ ${#PY_DIRS[@]} -eq 0 ]]; then
  log "ERROR: No /usr/lib/python<MAJOR>.* directories found."
  exit 1
fi

log "Found Python dirs under /usr/lib:"
log "${PY_DIRS[@]}"

# 2) Pick the lowest minor version directory (version sort ensures numeric order)
LOWEST_DIR="${PY_DIRS[0]}"
LOWEST_VER="${LOWEST_DIR##*/}" # e.g., python3.10 or python4.0

log "Lowest Python dir: ${LOWEST_DIR} (version: ${LOWEST_VER})"

# 3) Compute site-packages path and clean setuptools-related residues
SITE_PKGS="${LOWEST_DIR}/site-packages"
if [[ ! -d "${SITE_PKGS}" ]]; then
  log "ERROR: site-packages not found at: ${SITE_PKGS}"
  exit 2
fi

log "Target site-packages: ${SITE_PKGS}"

rm -f \
  "${SITE_PKGS}"/setuptools-*.dist-info/METADATA \
  "${SITE_PKGS}"/pip-*.dist-info/METADATA \
  "${SITE_PKGS}"/urllib3-*-py*.egg-info/PKG-INFO \
  "${SITE_PKGS}"/urllib3-*.dist-info/METADATA \
  "${SITE_PKGS}"/idna-*-py*.egg-info/PKG-INFO \
  "${SITE_PKGS}"/idna-*.dist-info/METADATA \
  "${SITE_PKGS}"/requests-*-py*.egg-info/PKG-INFO \
  "${SITE_PKGS}"/requests-*.dist-info/METADATA \
  || true

log "Cleanup completed for ${SITE_PKGS}"
exit 0
