#!/bin/bash
# ------------------------------------------------------------------------------
# File: /etc/profile.d/00-welcome.sh
# Purpose: Display a professional welcome banner on interactive Bash shells.
#          Intended for enterprise environments, containers, and managed systems.
#          Respects color settings and can be disabled via environment variables.
# Author:  Lorenzo Biosa <lorenzo@biosa-labs.com> © Biosa Labs
# ------------------------------------------------------------------------------

# --- Exit if not an interactive Bash shell ---
[ -n "$BASH" ] || return
case "$-" in
*i*) : ;; # interactive shell
*) return ;;
esac

# ------------------------------------------------------------------------------

# Configuration flags:
# - WELCOME_ENABLE=0        → disable banner entirely
# - NO_COLOR                → disable ANSI colors
# - PROMPT_ENABLE_COLORS=0  → disable ANSI colors explicitly
if [ "${WELCOME_ENABLE:-1}" != "1" ]; then
    return
fi

# ------------------------------------------------------------------------------
# Color configuration
# ------------------------------------------------------------------------------

if [ -n "${NO_COLOR:-}" ] || [ "${PROMPT_ENABLE_COLORS:-1}" != "1" ]; then
    GREEN=''
    GRAY=''
    WHITE=''
    RESET=''
    BOLD=''
else
    GREEN='\033[32m' # Green for separators
    GRAY='\033[90m'  # Gray for secondary text
    WHITE='\033[97m' # White for primary text
    RESET='\033[0m'
    BOLD='\033[1m'
fi

# ------------------------------------------------------------------------------
# Render welcome banner
# ------------------------------------------------------------------------------
printf '%b============================================================%b\n' "$GREEN" "$RESET"
printf '%b%b%s%b\n' "$BOLD" "$WHITE" "$IMAGE_TITLE" "$RESET"
printf '%b%b%s%b\n' "$BOLD" "$GRAY" "$IMAGE_DESCRIPTION" "$RESET"
printf '%bAuthor:%b %s <%s> © %s%b\n' \
    "$BOLD" "$WHITE" "$IMAGE_AUTHOR" "$AUTHOR_EMAIL" "$IMAGE_VENDOR" "$RESET"
printf '%b============================================================%b\n' "$GREEN" "$RESET"
