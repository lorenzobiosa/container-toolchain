#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# log.sh — Unified logging utility (library)
# ------------------------------------------------------------------------------
# Description : Provides a consistent, enterprise-grade logging interface for
#               container builds and scripts. Includes:
#                 - UTC ISO-8601 timestamps (TS)
#                 - ANSI color handling with NO_COLOR override
#                 - Uniform log prefix (configurable)
#                 - Standard log function (log)
#                 - Build header/footer with duration (header_build/footer_build)
#               This file is intended to be sourced by other scripts and Dockerfile
#               RUN steps for cohesive logging across the toolchain.
#
# Usage       : Source it from any shell script or Docker RUN step:
#                 . /usr/local/bin/log.sh
#               Then:
#                 log "Installing dependencies..."
#                 header_build
#                 ... your steps ...
#                 footer_build
#
# Notes       : - Writes logs to stderr to preserve ANSI formatting in container
#                 build output and CI logs.
#               - Colors are enabled by default and can be disabled via NO_COLOR.
#               - Compatible with POSIX sh/Bash; tested in UBI/RHEL minimal environments.
#               - Keep LF (Unix) line endings.
# Author      : Lorenzo Biosa (Biosa Labs) <lorenzo@biosa-labs.com>
# License     : MIT
# ------------------------------------------------------------------------------

# shellcheck shell=bash
# Do NOT 'set -euo pipefail' here because this library is meant to be sourced
# into scripts which may already control error/strict modes. We keep functions
# non-fatal and side-effect free, except when explicitly writing logs.

# --- Configuration -------------------------------------------------------------

# Optional: allow overriding the log prefix and product name through environment.
# Defaults are chosen for UBI-based builder images.
LOG_PREFIX="[${BUILDER_USER}]"

# --- Timestamp (UTC ISO-8601, Zulu) -------------------------------------------

TS() {
  # Prints UTC timestamp in ISO-8601 (e.g., 2025-12-30T16:34:58Z)
  date -u +%Y-%m-%dT%H:%M:%SZ
}

# --- ANSI Colors ---------------------------------------------------------------

# Colors are force-enabled unless NO_COLOR is set.
# NO_COLOR=1 (or any non-empty value) disables all ANSI codes.
if [ -n "${NO_COLOR:-}" ]; then
  GREEN=""; GRAY=""; CYAN=""; WHITE=""; RESET=""; BOLD="";
else
  # Use printf to avoid escape interpretation issues across shells
  GREEN="$(printf '\033[32m')"
  GRAY="$(printf '\033[90m')"
  CYAN="$(printf '\033[36m')"
  WHITE="$(printf '\033[97m')"
  RESET="$(printf '\033[0m')"
  BOLD="$(printf '\033[1m')"
  # Hint to CI/TTY that colors are desired when supported
  export CLICOLOR=1 FORCE_COLOR=1
fi

# --- Standard Log Function -----------------------------------------------------

# Logs a single line to stderr with:
#   [LOG_PREFIX][<UTC ISO timestamp>] >>> message
# Colors: prefix (green), timestamp (cyan), arrow (gray), message (white).
log() {
  # Accept arbitrary message parts; quote "$*" to preserve spaces
  printf '%b%s%b[%b%s%b] %b>>>%b %b%s%b\n' \
    "${GREEN}" "${LOG_PREFIX}" "${RESET}" \
    "${CYAN}" "$(TS)" "${RESET}" \
    "${GRAY}" "${RESET}" \
    "${WHITE}" "$*" "${RESET}" \
    >&2
}

# --- Build Header/Footer with Duration ----------------------------------------

# Record start epoch once; if already set by caller, do not override.
if [ -z "${START_EPOCH:-}" ]; then
  START_EPOCH="$(date -u +%s)"
fi

header_build() {
  # Decorative banner (ASCII) at start of a build/major step
  printf '%b%s%b[%b%s%b] %b>>>%b %b============================================================%b\n' \
    "${GREEN}" "${LOG_PREFIX}" "${RESET}" \
    "${CYAN}" "$(TS)" "${RESET}" \
    "${GRAY}" "${RESET}" \
    "${GREEN}" "${RESET}" \
    >&2

  printf '%b%s%b[%b%s%b] %b>>>%b %bStarting %s%b\n' \
    "${GREEN}" "${LOG_PREFIX}" "${RESET}" \
    "${CYAN}" "$(TS)" "${RESET}" \
    "${GRAY}" "${RESET}" \
    "${WHITE}" "${IMAGE_TITLE}" "${RESET}" \
    >&2

  printf '%b%s%b[%b%s%b] %b>>>%b %bAuthor:%b Lorenzo Biosa <lorenzo@biosa-labs.com> © Biosa Labs%b\n' \
    "${GREEN}" "${LOG_PREFIX}" "${RESET}" \
    "${CYAN}" "$(TS)" "${RESET}" \
    "${GRAY}" "${RESET}" \
    "${WHITE}" "${BOLD}" "${RESET}" \
    >&2

  printf '%b%s%b[%b%s%b] %b>>>%b %b============================================================%b\n' \
    "${GREEN}" "${LOG_PREFIX}" "${RESET}" \
    "${CYAN}" "$(TS)" "${RESET}" \
    "${GRAY}" "${RESET}" \
    "${GREEN}" "${RESET}" \
    >&2
}

footer_build() {
  # Compute and print duration since START_EPOCH; prints a closing banner.
  END_EPOCH="$(date -u +%s)"
  DURATION="$(( END_EPOCH - START_EPOCH ))"

  printf '%b%s%b[%b%s%b] %b>>>%b %b============================================================%b\n' \
    "${GREEN}" "${LOG_PREFIX}" "${RESET}" \
    "${CYAN}" "$(TS)" "${RESET}" \
    "${GRAY}" "${RESET}" \
    "${GREEN}" "${RESET}" \
    >&2

  printf '%b%s%b[%b%s%b] %b>>>%b %bCompleted %s%b (duration: %ss)\n' \
    "${GREEN}" "${LOG_PREFIX}" "${RESET}" \
    "${CYAN}" "$(TS)" "${RESET}" \
    "${GRAY}" "${RESET}" \
    "${WHITE}" "${IMAGE_TITLE}" "${RESET}" "${DURATION}" \
    >&2

  printf '%b%s%b[%b%s%b] %b>>>%b %bAll done.%b\n' \
    "${GREEN}" "${LOG_PREFIX}" "${RESET}" \
    "${CYAN}" "$(TS)" "${RESET}" \
    "${GRAY}" "${RESET}" \
    "${WHITE}" "${RESET}" \
    >&2

  printf '%b%s%b[%b%s%b] %b>>>%b %b============================================================%b\n' \
    "${GREEN}" "${LOG_PREFIX}" "${RESET}" \
    "${CYAN}" "$(TS)" "${RESET}" \
    "${GRAY}" "${RESET}" \
    "${GREEN}" "${RESET}" \
    >&2
}

# --- End of log.sh ------------------------------------------------------------
# This file intentionally defines functions only. No commands are executed at source time.
