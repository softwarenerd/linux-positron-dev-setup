# linux-positron-dev-setup

Scripts to configure a fresh Linux machine for [Positron](https://positron.posit.co)
development.

Supports the Debian family (Debian, Ubuntu, Mint, Pop!_OS, …)
and the Fedora family (Fedora, RHEL, CentOS Stream, Rocky, AlmaLinux, …).

## Quick start

Run the setup script using `wget` or `curl`.

For `wget` run:

```sh
bash -c "$(wget -qO- https://raw.githubusercontent.com/softwarenerd/linux-positron-dev-setup/main/setup.sh)"
```

For `curl` run:

```sh
bash -c "$(curl -fsSL https://raw.githubusercontent.com/softwarenerd/linux-positron-dev-setup/main/setup.sh)"
```

This downloads each script in full before running it, so a dropped connection can't
leave you executing a half-downloaded script.

That single command detects your distro and installs everything you need for Positron
development on Linux. The only things it asks you are personal (your name and email,
for git). The scripts are idempotent, so re-running is safe.

## What it does

- Refreshes the apt package index.
- Optionally upgrades installed packages within the current release (keeping the
  box on the same Debian/Ubuntu version).
- Installs all package dependencies.
- Optionally switches your login shell to Zsh (the default shell on macOS).
- Installs Node.js via [fnm](https://github.com/Schniz/fnm) and sets it as the
  default.
- Installs Python via [pyenv](https://github.com/pyenv/pyenv) and sets it as the
  global version.
- Generates an ed25519 SSH key (if you don't already have one), shows it, copies
  it to your clipboard (if a clipboard tool is available), and points you at
  GitHub to register it.
- Configures your git identity, prompting for your name and email (pre-filling
  anything that's already set).
- Clones Positron over SSH into a folder you choose under `~/` (skipped if it's
  already there).
- Optionally installs Visual Studio Code.

## Configuration

Override these with environment variables if you need to:

| Variable           | Default                                                              | What it controls                          |
| ------------------ | ------------------------------------------------------------------- | ----------------------------------------- |
| `SETUP_BASE_URL`   | `…/softwarenerd/linux-positron-dev-setup/main`                      | Where `setup.sh` fetches sibling scripts. |
| `SETUP_REPO_URL`   | `https://github.com/softwarenerd/linux-positron-dev-setup.git`      | Repo cloned by the setup.                 |
| `SETUP_CLONE_DIR`  | `~/linux-positron-dev-setup`                                         | Where the repo is cloned.                 |
