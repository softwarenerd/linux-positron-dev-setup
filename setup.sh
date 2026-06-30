#!/usr/bin/env bash
#
# setup.sh — Top-level dispatcher for Positron dev-machine setup.
#
# Detects the Linux distro family and invokes the matching setup-<family>.sh.
# Currently supports the Debian family (Debian, Ubuntu, Mint, Pop!_OS, ...).
# Any arguments are forwarded to the family script.
#
set -euo pipefail

# Directory this script lives in, so sibling scripts resolve regardless of cwd.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() {
  printf '[setup] error: %s\n' "$*" >&2
  exit 1
}

# detect_family: echo the distro family ("debian", ...) from /etc/os-release,
# or empty if it can't be determined.
detect_family() {
  [ -r /etc/os-release ] || return 0
  # shellcheck disable=SC1091
  . /etc/os-release
  # ID is the specific distro; ID_LIKE lists related families.
  case " ${ID:-} ${ID_LIKE:-} " in
    *" debian "* | *" ubuntu "*) echo "debian" ;;
  esac
}

main() {
  local family
  family="$(detect_family)"

  case "$family" in
    debian)
      exec "$SCRIPT_DIR/setup-debian.sh" "$@"
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
