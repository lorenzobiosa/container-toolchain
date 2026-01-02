#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# discover-python.sh
# ------------------------------------------------------------------------------
# Description : Discover the newest Python package available from UBI/RHEL
#               repositories (any supported major, e.g., 3/4) and print the
#               installable package name to STDOUT (e.g., "python3.13").
#               Intended for container builds (UBI minimal/standard) to auto-select
#               a valid Python without passing PYTHON_VERSION as a build-arg.
#
# Usage       : ./discover-python.sh
# Exit codes  : 0  -> success; a package name (e.g., "python3.13") is printed
#               2  -> fatal error (no package manager found / candidates list missing
#                    or empty / no candidate resolvable in enabled repositories)
#
# Notes       : - The script prefers microdnf (UBI minimal), falling back to dnf.
#               - Only the package availability is checked; the script does not install.
#               - Keep this file with LF (Unix) line endings to avoid parsing issues.
#               - Candidates are loaded from a version-controlled file in the repo
#                 to ensure "no network in build" for upstream metadata.
#
# Author      : Lorenzo Biosa
# Organization: Biosa Labs
# Contact     : lorenzo@biosa-labs.com
# License     : MIT
# ------------------------------------------------------------------------------

set -Eeuo pipefail

# --- Source logging lib
. /usr/local/bin/log.sh

# --- Package manager as parameter
PKG_MGR="$1"

# --- Load candidate Python versions from a version-controlled file
#     Primary installed path: /usr/local/share/python-supported.txt
#     Fallback to repo path: scripts/os/python-supported.txt
#     Accepted line formats (dynamic, any major):
#       - python<MAJOR>.<MINOR>                  (e.g., python3.14, python4.0)
#       - NEVRA: python<MAJOR>-<MAJOR>.<MINOR>.<PATCH>-... (e.g., python3-3.12.12-1.el10_1.x86_64)
#     (No static fallback embedded; if both files are missing/empty -> fatal)

SUPPORTED_PRIMARY="/usr/local/share/python-supported.txt"
SUPPORTED_FALLBACK="scripts/os/python-supported.txt"

# Internal representation: list of version keys "MAJOR.MINOR" (e.g., "3.14", "4.0")
VERSION_KEYS=()

read_candidates_file() {
  local f="$1"
  while IFS= read -r raw; do
    # strip whitespace
    local line
    line="$(echo "$raw" | sed 's/[[:space:]]//g')"
    [[ -z "$line" ]] && continue

    # Match "python<MAJOR>.<MINOR>"
    if [[ "$line" =~ ^python([0-9]+)\.([0-9]+)$ ]]; then
      VERSION_KEYS+=( "${BASH_REMATCH[1]}.${BASH_REMATCH[2]}" )
      continue
    fi

    # Match NEVRA "python<MAJOR>-<MAJOR>.<MINOR>.<PATCH>-..."
    # e.g., python3-3.12.12-1.el10_1.x86_64  -> MAJOR=3, MINOR=12
    if [[ "$line" =~ ^python([0-9]+)-\1\.([0-9]+)\.[0-9]+- ]]; then
      VERSION_KEYS+=( "${BASH_REMATCH[1]}.${BASH_REMATCH[2]}" )
      continue
    fi

    # Match NEVRA without PATCH (rare but handle): python<MAJOR>-<MAJOR>.<MINOR>-
    if [[ "$line" =~ ^python([0-9]+)-\1\.([0-9]+)- ]]; then
      VERSION_KEYS+=( "${BASH_REMATCH[1]}.${BASH_REMATCH[2]}" )
      continue
    fi

    # Ignore any other lines
  done < "$f"
}

if [[ -f "${SUPPORTED_PRIMARY}" ]]; then
  read_candidates_file "${SUPPORTED_PRIMARY}"
elif [[ -f "${SUPPORTED_FALLBACK}" ]]; then
  read_candidates_file "${SUPPORTED_FALLBACK}"
else
  log "ERROR: supported candidates list not found (expected one of:" >&2
  log "       ${SUPPORTED_PRIMARY} or ${SUPPORTED_FALLBACK})." >&2
  log "       Ensure the CI job keeps the candidates file in sync with the official status." >&2
  exit 2
fi

# Unique + sort descending (newest → conservative), e.g. 4.0 > 3.14 > 3.13 > 3.12 ...
if [[ ${#VERSION_KEYS[@]} -eq 0 ]]; then
  log "ERROR: candidates list is empty. Please refresh python-supported.txt from the official status." >&2
  exit 2
fi
mapfile -t VERSION_KEYS < <(printf "%s\n" "${VERSION_KEYS[@]}" | sort -r -V | awk '!seen[$0]++')

# Maintain a display list similar to the original "CANDIDATES" (for error messages),
# expressed as "python<MAJOR>.<MINOR>" so logs remain familiar.
CANDIDATES=()
for vkey in "${VERSION_KEYS[@]}"; do
  CANDIDATES+=( "python${vkey}" )
done

# --- For each normalized version key "<MAJOR>.<MINOR>", construct install-name attempts:
#     Try, in order:
#       1) "python<MAJOR>.<MINOR>"
#       2) "python<MAJOR>"
#     This covers UBI naming where the stream is python3.<minor>, and generic python3 on UBI10.
build_pkg_attempts() {
  local vkey="$1"              # e.g., "3.12"
  local major="${vkey%%.*}"    # "3"
  local minor="${vkey##*.}"    # "12"
  echo "python${major}.${minor}"
  echo "python${major}"
}

# --- Check if a package is resolvable in the enabled repositories
#     Return: 0 (true) if available; 1 (false) otherwise.
check_pkg() {
  local pkg="$1"
  if [[ "${PKG_MGR}" == "microdnf" ]]; then
    # microdnf: repoquery prints matches when a package is resolvable (exact match)
    microdnf repoquery "${pkg}" 2>/dev/null | grep -q "${pkg}"
  else
    # dnf: prefer repoquery exact match; fallback to list available exact match
    dnf -qy repoquery --qf '%{name}' "${pkg}" 2>/dev/null | grep -q "${pkg}" \
      || dnf -qy list available "${pkg}" 2>/dev/null | awk 'NR>1 {print $1}' | grep -q "${pkg}"
  fi
}

# --- Try candidates in order; for each version try its installable names; print the
#     first resolvable package and exit
for vkey in "${VERSION_KEYS[@]}"; do
  mapfile -t TRY_PKGS < <(build_pkg_attempts "${vkey}")
  for cand_pkg in "${TRY_PKGS[@]}"; do
    if check_pkg "${cand_pkg}"; then
      echo "${cand_pkg}"
      exit 0
    fi
  done
done

# --- No candidates matched: emit a clear error message and fail
log "ERROR: no suitable Python package found (checked: ${CANDIDATES[*]})." >&2
log "       Repositories may lack the listed GA/actively-supported branches; verify EPEL/CRB and repo metadata." >&2
exit 2
