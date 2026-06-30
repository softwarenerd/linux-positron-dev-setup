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

# Where to clone the repo and where to clone it from. Override either with the
# matching env var (handy for forks/branches or a non-default location).
REPO_URL="${SETUP_REPO_URL:-https://github.com/softwarenerd/linux-positron-dev-setup.git}"
CLONE_DIR="${SETUP_CLONE_DIR:-$HOME/linux-positron-dev-setup}"

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

# ask <prompt> <varname>: read a line from the terminal into the named variable,
# re-asking until it's non-empty. Like confirm(), reads /dev/tty so it works
# when the script is piped in via `curl ... | bash`.
ask() {
  local prompt="$1" __var="$2" reply=""
  while [ -z "$reply" ]; do
    printf '%s: ' "$prompt" >&2
    read -r reply </dev/tty 2>/dev/null || reply=""
  done
  printf -v "$__var" '%s' "$reply"
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

# configure_git_identity: ensure git knows who's authoring commits. Idempotent —
# if both name and email are already set globally, leaves them alone. Otherwise
# prompts for whatever's missing. This is the one place we ask the developer for
# personal info.
configure_git_identity() {
  local name email
  name="$(git config --global user.name || true)"
  email="$(git config --global user.email || true)"

  if [ -n "$name" ] && [ -n "$email" ]; then
    log "git identity already set ($name <$email>); skipping."
    return 0
  fi

  log "setting your git identity (used to author your commits)..."
  [ -n "$name" ] || ask "Your name" name
  [ -n "$email" ] || ask "Your email" email
  git config --global user.name "$name"
  git config --global user.email "$email"
  log "git identity set to $name <$email>."
}

# clone_repo: clone this repo into CLONE_DIR so the developer ends up with a
# working checkout (no manual git clone needed). Idempotent — skips if it's
# already there. Uses HTTPS so it works before any SSH key is set up.
clone_repo() {
  if [ -d "$CLONE_DIR/.git" ]; then
    log "repo already cloned at $CLONE_DIR; skipping."
    return 0
  fi
  if [ -e "$CLONE_DIR" ]; then
    log "WARNING: $CLONE_DIR exists but isn't a git checkout; skipping clone."
    return 0
  fi

  log "cloning $REPO_URL into $CLONE_DIR ..."
  git clone "$REPO_URL" "$CLONE_DIR"
  log "cloned. Your checkout is at $CLONE_DIR."
}

# --- main -------------------------------------------------------------------

main() {
  apt_update
  maybe_upgrade
  install_git
  configure_git_identity
  clone_repo
}

main "$@"
