# linux-positron-dev-setup

Scripts to configure a fresh Linux machine for [Positron](https://positron.posit.co)
development. Currently supports the Debian family (Debian, Ubuntu, Mint, Pop!_OS, …).

## Quick start (fresh box, no git yet)

On a brand-new VM you have a terminal and not much else — in particular, no git.
That's fine: these scripts *install* git, so bootstrap them with `curl` (present on
essentially every Debian/Ubuntu base image) instead:

```sh
curl -fsSL https://raw.githubusercontent.com/softwarenerd/linux-positron-dev-setup/main/setup.sh | bash
```

No `curl`? Use `wget`:

```sh
wget -qO- https://raw.githubusercontent.com/softwarenerd/linux-positron-dev-setup/main/setup.sh | bash
```

That single command does everything: it detects the distro, installs git, and
clones this repo for you — so you never have to `git clone` by hand. The only
things it asks you are personal (your name and email, for git). The scripts are
idempotent, so re-running is safe.

## What it does

- Refreshes the apt package index.
- Optionally upgrades installed packages within the current release (defaults to
  No, to keep the box at the chosen ISO's versions).
- Installs git if it isn't already present.
- Configures your git identity, prompting for your name and email (skipped if
  already set).
- Clones this repo to `~/linux-positron-dev-setup` so you have a working
  checkout (skipped if it's already there).

## Configuration

Override these with environment variables if you need to:

| Variable           | Default                                                              | What it controls                          |
| ------------------ | ------------------------------------------------------------------- | ----------------------------------------- |
| `SETUP_BASE_URL`   | `…/softwarenerd/linux-positron-dev-setup/main`                      | Where `setup.sh` fetches sibling scripts. |
| `SETUP_REPO_URL`   | `https://github.com/softwarenerd/linux-positron-dev-setup.git`      | Repo cloned by the setup.                 |
| `SETUP_CLONE_DIR`  | `~/linux-positron-dev-setup`                                         | Where the repo is cloned.                 |
