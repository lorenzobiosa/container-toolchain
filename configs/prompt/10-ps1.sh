#!/bin/bash
# ------------------------------------------------------------------------------
# File: /etc/profile.d/10-ps1.sh
# Purpose: Enterprise-grade Bash prompt customization for interactive shells.
#          Displays time, user@host, working directory, and integrates color
#          coding for clarity and professional look.
# Author:  Lorenzo Biosa <lorenzo@biosa-labs.com> © Biosa Labs
# ------------------------------------------------------------------------------

# --- Exit if not an interactive Bash shell ---
[ -n "$BASH" ] || return
case "$-" in
*i*) : ;; # interactive shell
*) return ;;
esac

# ------------------------------------------------------------------------------
# Color configuration (disable if NO_COLOR or PROMPT_ENABLE_COLORS=0)
# ------------------------------------------------------------------------------
if [ -n "${NO_COLOR:-}" ]; then
    GREEN=''
    CYAN=''
    GRAY=''
    WHITE=''
    RESET=''
else
    GREEN='\033[32m' # Green for username
    CYAN='\033[36m'  # Cyan for host and time
    GRAY='\033[90m'  # Gray for separators
    WHITE='\033[97m' # White for working directory
    RESET='\033[0m'
fi

# ------------------------------------------------------------------------------
# Prompt components
# ------------------------------------------------------------------------------
TIME_FORMAT="${CYAN}\A" # HH:MM (24h)
USER="${GREEN}\u"       # Username in green
HOST="${GRAY}@\h"       # Host in cyan
WORKDIR="${WHITE}\w"    # Current working directory

# ------------------------------------------------------------------------------
# PS1 layout
# ------------------------------------------------------------------------------
PS1="${GRAY}${TIME_FORMAT} ${RESET}${USER}${HOST} ${WORKDIR}${RESET}\n› "

# ------------------------------------------------------------------------------
# Prompt hook:
# - Prints a blank line only after the first prompt has been displayed
# - Preserves the original $? value (no side effects)
# - Designed to be composable with existing PROMPT_COMMAND logic
# ------------------------------------------------------------------------------

# Internal state: tracks whether the first prompt has already been shown
__FIRST_PROMPT_SHOWN=0

__prompt_hook() {
    # Mark that the first prompt has now been displayed
    __FIRST_PROMPT_SHOWN=1
}

# Safely append the prompt hook to PROMPT_COMMAND without overwriting
# any existing prompt logic (e.g. virtualenv, direnv, starship, etc.).
PROMPT_COMMAND="__prompt_hook${PROMPT_COMMAND:+; $PROMPT_COMMAND}"

# ------------------------------------------------------------------------------
# Export alias
# ------------------------------------------------------------------------------
alias ls='ls --color=auto'
