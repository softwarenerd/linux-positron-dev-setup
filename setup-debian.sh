#!/usr/bin/env bash
#
# setup-debian.sh — Configure a Debian-family (Debian/Ubuntu/...) machine for
# Positron development.
#
# Run interactively by a developer on a fresh VM. Asks before doing anything
# slow or impactful, and is idempotent so it's safe to re-run.
#
set -euo pipefail

# Keep apt itself from popping debconf dialogs mid-run. (This is about apt's
# own prompts, not our interactive prompts below.)
export DEBIAN_FRONTEND=noninteractive

# --- helpers ----------------------------------------------------------------

# log <message>: timestamped progress line on stderr.
log() {
  printf '[setup] %s\n' "$*" >&2
}

# have <command>: true if <command> is on PATH.
have() {
  command -v "$1" >/dev/null 2>&1
}

# confirm <prompt>: ask a yes/no question, defaulting to No. Reads from the
# terminal (/dev/tty) rather than stdin, so the prompt still works when the
# script is piped in via `curl ... | bash` (where stdin is the script itself).
confirm() {
  local prompt="$1" reply=""
  printf '%s [y/N] ' "$prompt" >&2
  read -r reply </dev/tty 2>/dev/null || reply=""
  case "$reply" in
    [Yy] | [Yy][Ee][Ss]) return 0 ;;
    *) return 1 ;;
  esac
}

# --- steps ------------------------------------------------------------------

# apt_update: refresh the package index so installs resolve to the versions
# available for the release the developer chose.
apt_update() {
  log "refreshing apt package index..."
  sudo apt-get update
}

# maybe_upgrade: offer to upgrade installed packages. Defaults to No so that,
# by default, the box stays at the exact package versions of the chosen ISO
# (useful for reproducing release-specific bugs). This stays WITHIN the current
# release — it does not change the Ubuntu/Debian (LTS) version.
maybe_upgrade() {
  if confirm "Upgrade installed packages to the latest within the current release? (stays on this LTS; does not change your release)"; then
    log "upgrading packages (apt-get full-upgrade)..."
    sudo apt-get full-upgrade -y
  else
    log "skipping upgrade; keeping the release's current package versions."
  fi
}

# install_git: ensure git is present. Idempotent — skips if already installed.
# Assumes apt_update has already run, so the index is current.
install_git() {
  if have git; then
    log "git already installed ($(git --version)); skipping."
    return 0
  fi

  log "git not found; installing via apt..."
  sudo apt-get install -y git
  log "git installed ($(git --version))."
}

# --- main -------------------------------------------------------------------

main() {
  apt_update
  maybe_upgrade
  install_git
}

main "$@"
