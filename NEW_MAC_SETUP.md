# New Mac Setup

This repo includes `setup_new_mac.sh` to bootstrap a new macOS machine for your Bash workflow.

## What It Does

1. Installs Xcode Command Line Tools (if missing; exits for re-run after GUI install)
2. Installs Homebrew (if missing)
3. Installs latest Bash from Homebrew and sets it as login shell
4. Configures Bash prompt + aliases
5. Installs common tools:
   - `uv`
   - Visual Studio Code (`visual-studio-code` cask)
6. Optionally installs dev tools group (with flag):
   - `git`, `jq`, `fzf`, `ripgrep`, `tmux`
7. Optionally installs Go tools group (with flag):
   - `go`
8. Optionally installs JavaScript/TypeScript tools group (with flag):
   - `node`, `pnpm`

## Usage

Run from this repo:

```bash
chmod +x setup_new_mac.sh
./setup_new_mac.sh
```

Install with optional dev tools:

```bash
./setup_new_mac.sh --dev-tools
```

Install with optional Go tools:

```bash
./setup_new_mac.sh --go-tools
```

Install with optional JavaScript/TypeScript tools:

```bash
./setup_new_mac.sh --js-ts-tools
```

Install all optional groups:

```bash
./setup_new_mac.sh --all
```

Show options:

```bash
./setup_new_mac.sh --help
```

## Notes

- Requires macOS 12 (Monterey) or later.
- On macOS 12, Homebrew cannot build Rust-dependent formulae, so the script works around this:
  - **ripgrep** is downloaded as a prebuilt binary from GitHub releases into `~/.local/bin/`.
  - **Node.js 22 LTS** is installed via [fnm](https://github.com/Schniz/fnm) (also a prebuilt binary in `~/.local/bin/`), with **pnpm** installed via npm. fnm is loaded automatically via `.bashrc`.
- May prompt for:
  - Xcode Command Line Tools install
  - `sudo` when appending Bash path to `/etc/shells`
  - password for `chsh`
- Existing files are backed up before overwrite:
  - `~/.bash_aliases`
  - `~/.bashrc`
  - `~/.bash_profile`
  - backups use `.bak.YYYYMMDDHHMMSS`

## Bash Config Applied

- Prompt includes:
  - `user@host:path`
  - Git branch when in a repo
  - exit code indicator when previous command fails
- Aliases:
  - `ls='ls -G'`
  - `ll='ls -al'`
  - `la='ls -A'`
  - `l='ls -CF'`
  - `ping2='ping -i 0.1'`
- `$HOME/.local/bin` prepended to `$PATH` in `~/.bashrc`
- `set -o vi` enabled in `~/.bash_profile`

## After Running

```bash
exec "$SHELL" -l
echo "$SHELL"
```

Expected shell path is typically:
- Apple Silicon: `/opt/homebrew/bin/bash`
- Intel: `/usr/local/bin/bash`
