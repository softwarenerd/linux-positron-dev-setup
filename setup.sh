#!/usr/bin/env bash
#
# setup.sh — Top-level dispatcher for Positron dev-machine setup.
#
# Detects the Linux distro family and invokes the matching setup-<family>.sh.
# Currently supports the Debian family (Debian, Ubuntu, Mint, Pop!_OS, ...) and
# the Fedora/RHEL family (Fedora, RHEL, Rocky, Alma, CentOS Stream, ...).
# Any arguments are forwarded to the family script.
#
set -euo pipefail

# Directory this script lives in, so sibling scripts resolve regardless of cwd.
# When piped straight into bash (`curl ... | bash`) there is no file on disk, so
# BASH_SOURCE is unset; fall back to "." (the cwd) in that case rather than
# tripping `set -u`. run_family then finds no sibling and downloads it instead.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-.}")" && pwd)"

# Base URL for fetching sibling scripts when this dispatcher is piped straight
# into bash (e.g. `curl ... | bash`) on a fresh box that has no git yet. In that
# case there is no checkout on disk, so the sibling setup-<family>.sh has to be
# downloaded. Override with SETUP_BASE_URL to test a fork or branch.
BASE_URL="${SETUP_BASE_URL:-https://raw.githubusercontent.com/softwarenerd/linux-positron-dev-setup/main}"

die() {
  printf '[setup] error: %s\n' "$*" >&2
  exit 1
}

# fetch <url>: write the contents of <url> to stdout using whatever HTTP client
# is available. curl and wget are present on essentially every Debian/Ubuntu
# base image, so one of them is our bootstrap tool before git exists.
fetch() {
  local url="$1"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO- "$url"
  else
    die "need curl or wget to download $url"
  fi
}

# run_family <family> [args...]: run setup-<family>.sh. Prefer the sibling file
# from a local checkout; otherwise download it (we were piped in via curl/wget).
run_family() {
  local family="$1"; shift
  local script="$SCRIPT_DIR/setup-$family.sh"

  if [ -f "$script" ]; then
    exec "$script" "$@"
  fi

  # No checkout on disk: fetch the family script and run it via process
  # substitution, so bash reads the script from a file (not stdin). That leaves
  # stdin alone and the family script's interactive prompts still read /dev/tty.
  local url="$BASE_URL/setup-$family.sh"
  log "no local checkout; fetching $url ..."
  exec bash <(fetch "$url") "$@"
}

log() {
  printf '[setup] %s\n' "$*" >&2
}

# detect_family: echo the distro family ("debian", "fedora", ...) from
# /etc/os-release, or empty if it can't be determined.
detect_family() {
  [ -r /etc/os-release ] || return 0
  # shellcheck disable=SC1091
  . /etc/os-release
  # ID is the specific distro; ID_LIKE lists related families. Fedora itself has
  # no ID_LIKE (ID=fedora), while RHEL derivatives (Rocky, Alma, CentOS Stream)
  # carry "fedora" and/or "rhel" in ID_LIKE.
  case " ${ID:-} ${ID_LIKE:-} " in
    *" debian "* | *" ubuntu "*) echo "debian" ;;
    *" fedora "* | *" rhel "*) echo "fedora" ;;
  esac
}

main() {
  local family
  family="$(detect_family)"

  case "$family" in
    debian)
      run_family debian "$@"
      ;;
    fedora)
      run_family fedora "$@"
      ;;
    "")
      die "could not determine Linux distro (missing or unrecognized /etc/os-release)."
      ;;
    *)
      die "unsupported distro family: '$family'."
      ;;
  esac
}

main "$@"
