#!/usr/bin/env bash
#
# setup-debian.sh — Configure a Debian-family (Debian/Ubuntu/...) machine for
# Positron development.
#
# Run interactively by a developer on a fresh VM. Asks before doing anything
# slow or impactful, and is idempotent so it's safe to re-run.
#
# Usage:
#   ./setup-debian.sh          run the setup steps
#   ./setup-debian.sh --undo   revert what a previous run installed/created
#
# --undo only reverses things THIS script actually did (tracked in a manifest);
# it never touches pre-existing packages or checkouts, and it does not revert
# apt-get update/upgrade. Generated SSH keys are deliberately left in place too,
# since the matching public key may already be registered on GitHub.
#
set -euo pipefail

# Keep apt itself from popping debconf dialogs mid-run. (This is about apt's
# own prompts, not our interactive prompts below.)
export DEBIAN_FRONTEND=noninteractive

# Where to clone the repo and where to clone it from. Override either with the
# matching env var (handy for forks/branches or a non-default location).
REPO_URL="${SETUP_REPO_URL:-https://github.com/softwarenerd/linux-positron-dev-setup.git}"
CLONE_DIR="${SETUP_CLONE_DIR:-$HOME/linux-positron-dev-setup}"

# Where to clone Positron from. Cloned over SSH (into a developer-chosen folder
# under ~/), so it relies on configure_ssh_key having registered a key first.
POSITRON_URL="${SETUP_POSITRON_URL:-git@github.com:posit-dev/positron.git}"

# Package dependencies installed via apt. Maintain this list as Positron's build
# requirements change — one package per line for easy diffs.
PACKAGES=(
  build-essential
  g++
  git
  git-lfs
  libcairo-dev
  libgif-dev
  libjpeg-dev
  libkrb5-dev
  libsdl-pango-dev
  libsecret-1-dev
  libx11-dev
  libxkbfile-dev
  python-is-python3
  python3-pip
)

# Node.js version installed via fnm (see install_node). Pinned here so it's easy
# to bump in one place as Positron's supported Node moves.
NODE_VERSION="22.22.1"

# Python version installed via pyenv (see install_python). Pinned here so it's
# easy to bump in one place as Positron's supported Python moves.
PYTHON_VERSION="3.12.12"

# Login shell wiring. configure_shell sets these from the developer's choice;
# defaults assume bash. Later steps (e.g. install_python) write their shell init
# into $SHELL_RC and use $LOGIN_SHELL to pick the right init syntax.
LOGIN_SHELL="bash"
SHELL_RC="$HOME/.bashrc"

# Manifest of what this run actually created/installed, so `--undo` can revert
# precisely without disturbing anything that pre-existed. Lives outside CLONE_DIR
# (in XDG state) so undo can safely remove the checkout without deleting itself.
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/linux-positron-dev-setup"
MANIFEST="$STATE_DIR/manifest"

# --- helpers ----------------------------------------------------------------

# ACCENT/CYAN/RESET: ANSI codes used to color banners and prompts (yellow, to
# signal "action needed"; cyan to make URLs stand out). Only populated when
# stderr is a terminal, so piped/logged output stays free of escape codes.
if [ -t 2 ]; then
  ACCENT=$'\033[33m'
  CYAN=$'\033[36m'
  RESET=$'\033[0m'
else
  ACCENT=""
  CYAN=""
  RESET=""
fi

# log <message>: timestamped progress line on stderr.
log() {
  printf '[setup] %s\n' "$*" >&2
}

# banner <title>: blank line + full-width rule + title, on stderr, in the accent
# color. Used
# to set off each interactive prompt so it's easy to spot. The rule uses the box-
# drawing character U+2500 and spans the terminal width (falling back to 40).
banner() {
  local width line
  width=$(tput cols 2>/dev/null) || width=40
  [ -n "$width" ] || width=40
  line=$(printf '─%.0s' $(seq 1 "$width"))
  printf '\n' >&2
  printf '%s%s%s\n' "$ACCENT" "$line" "$RESET" >&2
  printf '%s%s%s\n' "$ACCENT" "$1" "$RESET" >&2
}

# have <command>: true if <command> is on PATH.
have() {
  command -v "$1" >/dev/null 2>&1
}

# pkg_installed <pkg>: true if the dpkg package is currently installed.
pkg_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'ok installed'
}

# record <line>: append an action record to the manifest so --undo can reverse
# it later. Creates the state dir on first use.
record() {
  mkdir -p "$STATE_DIR"
  printf '%s\n' "$1" >>"$MANIFEST"
}

# confirm <prompt>: ask a yes/no question, defaulting to Yes so the developer can
# hit ENTER to proceed through the steps. Reads from the terminal (/dev/tty)
# rather than stdin, so the prompt still works when the script is piped in via
# `curl ... | bash` (where stdin is the script itself).
confirm() {
  local prompt="$1" reply=""
  printf '%s%s [Y/n] %s' "$ACCENT" "$prompt" "$RESET" >&2
  read -r reply </dev/tty 2>/dev/null || reply=""
  case "$reply" in
    [Nn] | [Nn][Oo]) return 1 ;;
    *) return 0 ;;
  esac
}

# ask <prompt> <varname>: read a line from the terminal into the named variable,
# re-asking until it's non-empty. Like confirm(), reads /dev/tty so it works
# when the script is piped in via `curl ... | bash`.
ask() {
  local prompt="$1" __var="$2" reply=""
  while [ -z "$reply" ]; do
    printf '%s%s: %s' "$ACCENT" "$prompt" "$RESET" >&2
    read -r reply </dev/tty 2>/dev/null || reply=""
  done
  printf -v "$__var" '%s' "$reply"
}

# ask_default <prompt> <varname> <default>: like ask(), but shows <default> in
# brackets and accepts it when the developer just hits ENTER. If <default> is
# empty this behaves like ask() (re-asks until non-empty), so it works both for
# confirming an existing value and for filling in a missing one.
ask_default() {
  local prompt="$1" __var="$2" default="$3" reply=""
  while :; do
    if [ -n "$default" ]; then
      printf '%s%s [%s]: %s' "$ACCENT" "$prompt" "$default" "$RESET" >&2
    else
      printf '%s%s: %s' "$ACCENT" "$prompt" "$RESET" >&2
    fi
    read -r reply </dev/tty 2>/dev/null || reply=""
    [ -z "$reply" ] && reply="$default"
    [ -n "$reply" ] && break
  done
  printf -v "$__var" '%s' "$reply"
}

# --- steps ------------------------------------------------------------------

# apt_update: refresh the package index so installs resolve to the versions
# available for the release the developer chose.
apt_update() {
  banner "Refresh Package Index"
  log "refreshing apt package index..."
  sudo apt-get update
}

# maybe_upgrade: offer to upgrade installed packages. Like every prompt this
# defaults to Yes (hit ENTER to proceed); answer No to keep the box at the exact
# package versions of the chosen ISO (useful for reproducing release-specific
# bugs). This stays WITHIN the current release — it does not change the
# Ubuntu/Debian (LTS) version.
maybe_upgrade() {
  banner "Upgrade Packages"
  if confirm "Upgrade installed packages to the latest within the current release?"; then
    log "upgrading packages (apt-get full-upgrade)..."
    sudo apt-get full-upgrade -y
  else
    log "skipping upgrade; keeping the release's current package versions."
  fi
}

# install_deps: install the build/runtime package dependencies from PACKAGES.
# Assumes apt_update has already run, so the index is current. apt-get is
# idempotent — already-installed packages are left as-is.
install_deps() {
  banner "Install Dependencies"

  if ! confirm "Do you want to install package dependencies?"; then
    log "skipping package dependency install."
    return 0
  fi

  # Note which packages aren't installed yet, so --undo removes only those and
  # leaves anything that was already present alone.
  local pkg new=()
  for pkg in "${PACKAGES[@]}"; do
    pkg_installed "$pkg" || new+=("$pkg")
  done

  log "installing package dependencies (${#PACKAGES[@]} packages)..."
  sudo apt-get install -y "${PACKAGES[@]}"

  for pkg in "${new[@]:-}"; do
    [ -n "$pkg" ] && record "pkg $pkg"
  done
  log "package dependencies installed."
}

# configure_git_identity: ensure git knows who's authoring commits. Always walks
# the developer through both fields, pre-filling any value that's already set so
# ENTER keeps it. This is the one place we ask the developer for personal info.
configure_git_identity() {
  local cur_name cur_email name email
  cur_name="$(git config --global user.name || true)"
  cur_email="$(git config --global user.email || true)"

  banner "Setup Git Identity"
  log "setting your git identity (used to author your commits)..."

  # Prompt for both, showing any existing value as the default. Only set (and
  # record for undo) fields that actually change, so we never unset or clobber an
  # identity the developer already had, and re-running is a no-op.
  ask_default "Your Git user.name" name "$cur_name"
  if [ "$name" != "$cur_name" ]; then
    git config --global user.name "$name"
    [ -z "$cur_name" ] && record "git-name"
  fi
  ask_default "Your Git user.email" email "$cur_email"
  if [ "$email" != "$cur_email" ]; then
    git config --global user.email "$email"
    [ -z "$cur_email" ] && record "git-email"
  fi
  log "git identity set to $name <$email>."
}

# clip_copy <text>: copy <text> to the system clipboard if a clipboard tool is
# available (Wayland's wl-copy, or X11's xclip/xsel). Returns non-zero if none
# is present so callers can fall back gracefully.
clip_copy() {
  if have wl-copy; then
    printf '%s' "$1" | wl-copy
  elif have xclip; then
    printf '%s' "$1" | xclip -selection clipboard
  elif have xsel; then
    printf '%s' "$1" | xsel --clipboard --input
  else
    return 1
  fi
}

# add_shell_init <tag> <line>...: append a marker-delimited block of shell-init
# lines to $SHELL_RC so a tool (pyenv, fnm, ...) loads in future interactive
# shells. Idempotent by <tag>, and recorded for --undo, which removes the block
# by its markers. <tag> names the tool so blocks are individually identifiable.
add_shell_init() {
  local tag="$1"; shift
  local rc="$SHELL_RC"
  if [ -f "$rc" ] && grep -q "linux-positron-dev-setup: $tag" "$rc"; then
    log "$tag shell init already present in $rc; skipping."
    return 0
  fi
  log "adding $tag shell init to $rc ..."
  {
    printf '\n# >>> linux-positron-dev-setup: %s >>>\n' "$tag"
    printf '%s\n' "$@"
    printf '# <<< linux-positron-dev-setup: %s <<<\n' "$tag"
  } >>"$rc"
  record "shellinit $rc"
}

# set_shell_vars <shell-path>: derive LOGIN_SHELL and SHELL_RC from a login shell
# path (e.g. /usr/bin/zsh) so shell-init steps target the right file with the
# right syntax. Falls back to bash/~/.bashrc for anything we don't specifically
# handle, since that's what pyenv init we emit expects.
set_shell_vars() {
  case "$(basename "$1")" in
    zsh)  LOGIN_SHELL="zsh";  SHELL_RC="$HOME/.zshrc" ;;
    bash) LOGIN_SHELL="bash"; SHELL_RC="$HOME/.bashrc" ;;
    *)
      log "unrecognized login shell '$1'; wiring shell init into ~/.bashrc as a fallback."
      LOGIN_SHELL="bash"; SHELL_RC="$HOME/.bashrc"
      ;;
  esac
}

# configure_shell: optionally switch the developer's login shell to Zsh. Our
# developers work on macOS (where Zsh is the default), so offer it here. Installs
# zsh, makes it the login shell via chsh, and points $SHELL_RC/$LOGIN_SHELL at
# zsh so later steps wire their shell init into ~/.zshrc. Declining detects the
# current login shell and targets that instead. Must run before install_python,
# which relies on these variables.
configure_shell() {
  banner "Choose Shell"

  local user old_shell zsh_path
  user="$(id -un)"
  old_shell="$(getent passwd "$user" | cut -d: -f7)"

  if ! confirm "Would you like to use Zsh? (the default shell on macOS)"; then
    log "keeping your current login shell ($old_shell)."
    set_shell_vars "$old_shell"
    return 0
  fi

  if ! pkg_installed zsh; then
    log "installing zsh..."
    sudo apt-get install -y zsh
    record "pkg zsh"
  fi

  # Switch the login shell with sudo chsh so it doesn't prompt for a password.
  # Record the previous shell so --undo can restore it.
  zsh_path="$(command -v zsh)"
  if [ "$old_shell" != "$zsh_path" ]; then
    log "setting your login shell to $zsh_path ..."
    sudo chsh -s "$zsh_path" "$user"
    record "shell $old_shell"
  else
    log "login shell is already $zsh_path; skipping."
  fi

  set_shell_vars "$zsh_path"

  # zsh is now present (we installed it or it was already there), so offer
  # oh-my-zsh on top of it.
  install_oh_my_zsh
}

# install_oh_my_zsh: optionally install the oh-my-zsh framework on top of zsh.
# Only reached from configure_shell's zsh path, so zsh is guaranteed present.
# Idempotent — skips if ~/.oh-my-zsh already exists. Runs the official installer
# unattended so it doesn't try to chsh (we already did) or exec a login zsh
# (which would hijack this script). The installer creates ~/.zshrc from its
# template, backing up any existing one to ~/.zshrc.pre-oh-my-zsh; because this
# runs before the tool-init steps, their shell init is appended afterwards.
# Recorded for --undo, which removes ~/.oh-my-zsh and restores the backup.
install_oh_my_zsh() {
  if [ -d "$HOME/.oh-my-zsh" ]; then
    log "oh-my-zsh already installed ($HOME/.oh-my-zsh); skipping."
    return 0
  fi

  if ! confirm "Install oh-my-zsh?"; then
    log "skipping oh-my-zsh install."
    return 0
  fi

  # The installer fetches over HTTPS; make sure curl is present (record only if
  # we newly add it, for --undo).
  if ! pkg_installed curl; then
    log "installing curl..."
    sudo apt-get install -y curl
    record "pkg curl"
  fi

  log "installing oh-my-zsh ..."
  # --unattended sets CHSH=no and RUNZSH=no: don't change the login shell (we
  # already did) and don't drop into a new zsh at the end.
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
  record "omz"
  log "oh-my-zsh installed."
}

# install_node: install fnm (Fast Node Manager) and the pinned Node.js
# ($NODE_VERSION), then set it as the default. fnm is the current recommendation
# for managing Node versions. Idempotent — skips the fnm install and the version
# install if they're already present. Runs before install_python and, like it,
# relies on configure_shell having set $SHELL_RC/$LOGIN_SHELL.
install_node() {
  banner "Install Node.js"

  if ! confirm "Install Node.js $NODE_VERSION via fnm?"; then
    log "skipping Node.js install."
    return 0
  fi

  # fnm's installer fetches and unpacks a release zip over HTTPS, so make sure
  # curl and unzip exist. Record only what we newly add, for --undo.
  local dep
  for dep in curl unzip; do
    if ! pkg_installed "$dep"; then
      log "installing $dep..."
      sudo apt-get install -y "$dep"
      record "pkg $dep"
    fi
  done

  # fnm itself, into ~/.fnm (both the binary and, via $FNM_DIR, the installed
  # Node versions, so --undo can remove everything by deleting one directory).
  # --skip-shell so we control the shell wiring ourselves (via add_shell_init),
  # consistent with pyenv.
  local fnm_dir="$HOME/.fnm"
  if [ -x "$fnm_dir/fnm" ]; then
    log "fnm already installed ($fnm_dir); skipping."
  else
    log "installing fnm into $fnm_dir ..."
    curl -fsSL https://fnm.vercel.app/install | bash -s -- --install-dir "$fnm_dir" --skip-shell
    record "fnm-root $fnm_dir"
  fi

  # Make fnm usable for the rest of this script.
  export PATH="$fnm_dir:$PATH"
  export FNM_DIR="$fnm_dir"

  # Wire fnm into future interactive shells now, before the (network-dependent)
  # version install below. Under `set -e` a failed `fnm install` would abort the
  # script, and if the wiring came afterward we'd leave the binary on disk but
  # off PATH — fnm unusable in new shells. The `[ -d "$FNM_DIR" ]` guard mirrors
  # fnm's own installer so the block is a no-op if the dir is ever removed.
  add_shell_init fnm \
    'export FNM_DIR="$HOME/.fnm"' \
    'if [ -d "$FNM_DIR" ]; then' \
    '  export PATH="$FNM_DIR:$PATH"' \
    "  eval \"\$(fnm env --use-on-cd --shell $LOGIN_SHELL)\"" \
    'fi'

  # Install the pinned Node version (idempotent).
  if fnm list 2>/dev/null | grep -q "v$NODE_VERSION"; then
    log "Node.js $NODE_VERSION already installed via fnm; skipping."
  else
    log "installing Node.js $NODE_VERSION with fnm..."
    fnm install "$NODE_VERSION"
    record "fnm-version $NODE_VERSION"
  fi
  fnm default "$NODE_VERSION"
  log "fnm default Node.js set to $NODE_VERSION."
}

# install_python: install pyenv and build the pinned CPython ($PYTHON_VERSION),
# then set it as the global version. Positron needs Python both to build against
# and to run against, and pyenv lets the developer manage/switch versions
# cleanly. Idempotent — skips the pyenv clone and the version build if they're
# already present.
install_python() {
  banner "Install Python"

  if ! confirm "Install Python $PYTHON_VERSION via pyenv?"; then
    log "skipping Python install."
    return 0
  fi

  # Packages needed to compile CPython from source (the pyenv "suggested build
  # environment"). Only the ones not already present are recorded, so --undo
  # removes just what we added.
  local build_deps=(
    make build-essential libssl-dev zlib1g-dev libbz2-dev libreadline-dev
    libsqlite3-dev wget curl llvm libncursesw5-dev xz-utils tk-dev
    libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev
  )
  local pkg new=()
  for pkg in "${build_deps[@]}"; do
    pkg_installed "$pkg" || new+=("$pkg")
  done
  if [ "${#new[@]}" -gt 0 ]; then
    log "installing ${#new[@]} pyenv build dependencies..."
    sudo apt-get install -y "${build_deps[@]}"
    for pkg in "${new[@]}"; do record "pkg $pkg"; done
  fi

  # pyenv itself, into ~/.pyenv.
  local pyenv_root="$HOME/.pyenv"
  if [ -d "$pyenv_root/.git" ]; then
    log "pyenv already installed ($pyenv_root); skipping clone."
  else
    log "installing pyenv into $pyenv_root ..."
    git clone --depth 1 https://github.com/pyenv/pyenv.git "$pyenv_root"
    record "pyenv-root $pyenv_root"
  fi

  # Make pyenv usable for the rest of this script.
  export PYENV_ROOT="$pyenv_root"
  export PATH="$PYENV_ROOT/bin:$PATH"

  # Build the pinned version. pyenv would skip an existing build itself, but the
  # explicit check keeps the log clean and avoids a needless rebuild.
  if pyenv versions --bare 2>/dev/null | grep -qx "$PYTHON_VERSION"; then
    log "Python $PYTHON_VERSION already installed via pyenv; skipping build."
  else
    log "building Python $PYTHON_VERSION with pyenv (this can take a few minutes)..."
    pyenv install "$PYTHON_VERSION"
    record "pyenv-version $PYTHON_VERSION"
  fi
  pyenv global "$PYTHON_VERSION"
  log "pyenv global Python set to $PYTHON_VERSION."

  # Wire pyenv into future interactive shells.
  add_shell_init pyenv \
    'export PYENV_ROOT="$HOME/.pyenv"' \
    '[ -d "$PYENV_ROOT/bin" ] && export PATH="$PYENV_ROOT/bin:$PATH"' \
    "eval \"\$(pyenv init - $LOGIN_SHELL)\""
}

# configure_ssh_key: ensure an ed25519 SSH key pair exists. Idempotent — if
# ~/.ssh/id_ed25519 is already there, leaves it alone. Otherwise generates one
# non-interactively (no passphrase), labelled with the git email if set. Then
# shows the public key and points the developer at GitHub to register it.
configure_ssh_key() {
  local key="$HOME/.ssh/id_ed25519" comment pub

  banner "Setup SSH Keys"
  if [ -f "$key" ]; then
    log "SSH key already exists ($key); skipping generation."
  else
    log "generating an ed25519 SSH key ($key)..."
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    comment="$(git config --global user.email || true)"
    ssh-keygen -t ed25519 -f "$key" -N "" -C "$comment"
    log "SSH key created."
  fi

  pub="$(cat "${key}.pub")"
  printf '\n' >&2
  printf 'Your public SSH key (%s.pub):\n\n' "$key" >&2
  printf '%s\n\n' "$pub" >&2
  if clip_copy "$pub"; then
    printf 'It has been copied to your clipboard.\n' >&2
  fi
  printf '%sAdd it to GitHub here: %s%shttps://github.com/settings/ssh/new%s\n\n' "$ACCENT" "$RESET" "$CYAN" "$RESET" >&2
  while ! confirm "Have you added your SSH key to GitHub?"; do
    printf '%sWell, do it! Add your SSH key to GitHub, then confirm.%s\n' "$ACCENT" "$RESET" >&2
  done
}

# clone_positron: clone Positron over SSH into a developer-chosen folder under
# ~/ (e.g. "Work" or "Code"), creating that folder if needed. Runs after
# configure_ssh_key so the SSH clone can authenticate. Idempotent — skips if the
# checkout is already there.
clone_positron() {
  banner "Clone Positron"

  local folder parent dest
  ask "Which folder under ~/ should Positron go in? (e.g. Work, Code)" folder
  parent="$HOME/$folder"
  dest="$parent/positron"

  if [ -d "$dest/.git" ]; then
    log "Positron already cloned at $dest; skipping."
    return 0
  fi
  if [ -e "$dest" ]; then
    log "WARNING: $dest exists but isn't a git checkout; skipping clone."
    return 0
  fi

  # Create the parent folder only if it's missing, and record it for --undo only
  # when we actually created it (so undo never removes a folder that pre-existed).
  if [ ! -d "$parent" ]; then
    log "creating $parent ..."
    mkdir -p "$parent"
    record "mkdir $parent"
  fi

  log "cloning $POSITRON_URL into $dest ..."
  git clone "$POSITRON_URL" "$dest"
  record "clone $dest"
  log "cloned. Your Positron checkout is at $dest."
}

# install_vscode: optionally download and install the latest stable VS Code for
# arm64 from Microsoft. Downloads the .deb into ~/Downloads, then installs it with
# apt-get (which resolves any dependencies). Idempotent — skips if `code` is
# already installed. Recorded for --undo only when we newly install it.
install_vscode() {
  banner "Install Visual Studio Code"

  if ! confirm "Install Visual Studio Code?"; then
    log "skipping Visual Studio Code install."
    return 0
  fi

  # Check the dpkg package, not `code` on PATH: in a VS Code remote/SSH session
  # the server ships its own `code` CLI shim, so `have code` gives a false
  # positive even when the .deb isn't installed.
  if pkg_installed code; then
    log "Visual Studio Code already installed (code package present); skipping."
    return 0
  fi

  # curl fetches the .deb over HTTPS; make sure it's present (record only if we
  # newly add it, for --undo).
  if ! pkg_installed curl; then
    log "installing curl..."
    sudo apt-get install -y curl
    record "pkg curl"
  fi

  # Download the latest stable arm64 build into ~/Downloads. The URL redirects to
  # a versioned .deb (e.g. code_1.126.0-..._arm64.deb); -L follows the redirect
  # and -OJ saves it under the server-provided filename.
  local dl="$HOME/Downloads"
  mkdir -p "$dl"
  log "downloading the latest VS Code (arm64) into $dl ..."
  ( cd "$dl" && curl -fSL -OJ "https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-arm64" )

  # Pick the VS Code .deb to install. Normally there's exactly one, but if older
  # downloads linger, sort -V takes the highest version. The directory prefix is
  # identical across matches, so the sort keys on the version in the filename.
  local deb
  deb="$(ls "$dl"/code_*.deb 2>/dev/null | sort -V | tail -n1)"
  if [ -z "$deb" ]; then
    log "WARNING: no VS Code .deb found in $dl after download; skipping install."
    return 0
  fi

  log "installing $(basename "$deb") ..."
  sudo apt-get install -y "$deb"
  record "pkg code"
  log "Visual Studio Code installed."
}

# install_ssh_server: optionally install and enable the OpenSSH server so the
# machine accepts incoming SSH connections (e.g. for VS Code Remote - SSH).
# Idempotent — the apt-get install is a no-op if openssh-server is already
# present, and `systemctl enable --now` is safe to re-run. Recorded for --undo
# only when we newly install the package.
install_ssh_server() {
  banner "Enable SSH server"

  if ! confirm "Install and enable the OpenSSH server?"; then
    log "skipping OpenSSH server setup."
    return 0
  fi

  if ! pkg_installed openssh-server; then
    log "installing openssh-server..."
    sudo apt-get install -y openssh-server
    record "pkg openssh-server"
  else
    log "openssh-server already installed."
  fi

  # Enable the service and start it now. On Debian/Ubuntu the unit is named ssh.
  log "enabling and starting the ssh service..."
  sudo systemctl enable --now ssh
  record "service ssh"
  log "OpenSSH server is enabled and running."
}

# configure_zsh_prompt: if zsh is the login shell and oh-my-zsh is installed,
# append a custom PROMPT as the final shell-init block of ~/.zshrc. Runs last in
# main() so it lands after every other block (pyenv, fnm, and oh-my-zsh's own
# config), letting it win as the effective prompt. The prompt uses oh-my-zsh
# helpers ($fg, git_prompt_info), so we only add it when oh-my-zsh is present;
# otherwise the developer manages their own prompt. Idempotent and undo-aware via
# add_shell_init.
configure_zsh_prompt() {
  [ "$LOGIN_SHELL" = zsh ] || return 0
  [ -d "$HOME/.oh-my-zsh" ] || return 0
  banner "Configure Zsh Prompt"
  add_shell_init "zsh-prompt" \
    'PROMPT='\''[%m]%{$fg_bold[green]%}%p %{$fg[cyan]%}[%~]%{$reset_color%} $(git_prompt_info)%{$fg_bold[blue]%}% %{$reset_color%}'\'''
  log "custom zsh prompt written to $SHELL_RC."
}

# undo: reverse everything recorded in the manifest, then delete it. Only touches
# what this script created/installed; leaves pre-existing state untouched. Does
# not revert apt-get update/upgrade.
undo() {
  banner "Undo Linux Positron Dev Setup"
  if [ ! -f "$MANIFEST" ]; then
    log "no manifest found ($MANIFEST); nothing to undo."
    return 0
  fi

  local line dir ver file old_shell svc pkgs=() dirs=()
  while IFS= read -r line; do
    case "$line" in
      "pkg "*) pkgs+=("${line#pkg }") ;;
      "mkdir "*) dirs+=("${line#mkdir }") ;;
      "service "*)
        svc="${line#service }"
        log "disabling and stopping the $svc service ..."
        sudo systemctl disable --now "$svc" 2>/dev/null || true
        ;;
      "omz")
        log "removing oh-my-zsh ..."
        rm -rf "$HOME/.oh-my-zsh"
        if [ -f "$HOME/.zshrc.pre-oh-my-zsh" ]; then
          log "restoring pre-oh-my-zsh ~/.zshrc ..."
          mv -f "$HOME/.zshrc.pre-oh-my-zsh" "$HOME/.zshrc"
        fi
        ;;
      "git-name")
        log "unsetting git user.name ..."
        git config --global --unset user.name || true
        ;;
      "git-email")
        log "unsetting git user.email ..."
        git config --global --unset user.email || true
        ;;
      "shell "*)
        old_shell="${line#shell }"
        log "restoring login shell to $old_shell ..."
        sudo chsh -s "$old_shell" "$(id -un)" 2>/dev/null || true
        ;;
      "pyenv-version "*)
        ver="${line#pyenv-version }"
        log "uninstalling pyenv Python $ver ..."
        PYENV_ROOT="$HOME/.pyenv" PATH="$HOME/.pyenv/bin:$PATH" \
          pyenv uninstall -f "$ver" 2>/dev/null || true
        ;;
      "pyenv-root "*)
        dir="${line#pyenv-root }"
        log "removing pyenv ($dir) ..."
        rm -rf "$dir"
        ;;
      "fnm-version "*)
        ver="${line#fnm-version }"
        log "uninstalling Node.js $ver ..."
        FNM_DIR="$HOME/.fnm" PATH="$HOME/.fnm:$PATH" \
          fnm uninstall "$ver" 2>/dev/null || true
        ;;
      "fnm-root "*)
        dir="${line#fnm-root }"
        log "removing fnm ($dir) ..."
        rm -rf "$dir"
        ;;
      "shellinit "*)
        file="${line#shellinit }"
        log "removing our shell init from $file ..."
        sed -i '/# >>> linux-positron-dev-setup: /,/# <<< linux-positron-dev-setup: /d' "$file" 2>/dev/null || true
        ;;
      "clone "*)
        dir="${line#clone }"
        log "removing cloned repo $dir ..."
        rm -rf "$dir"
        ;;
    esac
  done <"$MANIFEST"

  if [ "${#pkgs[@]}" -gt 0 ]; then
    log "purging ${#pkgs[@]} packages that setup installed..."
    sudo apt-get purge -y "${pkgs[@]}"
    sudo apt-get autoremove -y
  fi

  # Remove folders we created, last, so any checkouts inside them (removed above)
  # are already gone. rmdir only deletes empty dirs, so a folder the developer
  # later put other work in is left untouched.
  for dir in "${dirs[@]:-}"; do
    [ -n "$dir" ] || continue
    rmdir "$dir" 2>/dev/null && log "removed $dir" || true
  done

  rm -f "$MANIFEST"
  rmdir "$STATE_DIR" 2>/dev/null || true
  log "undo complete."
}

# --- main -------------------------------------------------------------------

main() {
  banner "Linux Positron Dev Setup"
  apt_update
  maybe_upgrade
  install_deps
  configure_shell
  install_node
  install_python
  configure_ssh_key
  configure_git_identity
  clone_positron
  install_vscode
  install_ssh_server
  configure_zsh_prompt
}

case "${1:-}" in
  ""|--setup) main ;;
  --undo) undo ;;
  -h|--help) printf 'usage: %s [--undo]\n' "$0" ;;
  *) printf 'unknown option: %s\nusage: %s [--undo]\n' "$1" "$0" >&2; exit 2 ;;
esac
