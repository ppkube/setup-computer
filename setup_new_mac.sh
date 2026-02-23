#!/usr/bin/env bash
set -euo pipefail

INSTALL_DEV_TOOLS=0
INSTALL_GO_TOOLS=0
INSTALL_JS_TS_TOOLS=0

log() {
  printf '[setup] %s\n' "$*"
}

warn() {
  printf '[setup][warn] %s\n' "$*" >&2
}

backup_if_exists() {
  local file="$1"
  if [[ -f "$file" ]]; then
    local backup="${file}.bak.$(date +%Y%m%d%H%M%S)"
    cp "$file" "$backup"
    log "Backed up $file to $backup"
  fi
}

require_macos() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    printf 'This script is for macOS only.\n' >&2
    exit 1
  fi

  MACOS_MAJOR_VERSION="$(sw_vers -productVersion | cut -d. -f1)"
  if [[ "$MACOS_MAJOR_VERSION" -lt 12 ]]; then
    printf 'macOS 12 (Monterey) or later is required. Detected version: %s\n' \
      "$(sw_vers -productVersion)" >&2
    exit 1
  fi
}

print_usage() {
  cat <<'EOF'
Usage: ./setup_new_mac.sh [options]

Options:
  --dev-tools   Install optional dev tools: git, jq, fzf, ripgrep, tmux
  --go-tools    Install optional Go tools: go
  --js-ts-tools Install optional JavaScript/TypeScript tools: node, pnpm
  --all         Install all optional groups
  -h, --help    Show this help and exit
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dev-tools)
        INSTALL_DEV_TOOLS=1
        shift
        ;;
      --go-tools)
        INSTALL_GO_TOOLS=1
        shift
        ;;
      --js-ts-tools)
        INSTALL_JS_TS_TOOLS=1
        shift
        ;;
      --all)
        INSTALL_DEV_TOOLS=1
        INSTALL_GO_TOOLS=1
        INSTALL_JS_TS_TOOLS=1
        shift
        ;;
      -h|--help)
        print_usage
        exit 0
        ;;
      *)
        printf 'Unknown option: %s\n\n' "$1" >&2
        print_usage >&2
        exit 1
        ;;
    esac
  done
}

ensure_xcode_clt() {
  if xcode-select -p >/dev/null 2>&1; then
    log "Xcode Command Line Tools already installed."
    return
  fi

  log "Installing Xcode Command Line Tools..."
  xcode-select --install || true
  printf '\nXcode Command Line Tools install has been triggered.\n'
  printf 'Please complete the GUI install, then re-run this script.\n'
  exit 0
}

install_homebrew() {
  if command -v brew >/dev/null 2>&1; then
    log "Homebrew already installed: $(brew --version | head -n1)"
    return
  fi

  log "Installing Homebrew..."
  NONINTERACTIVE=1 /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
}

load_brew_shellenv() {
  eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || true)"
  eval "$(/usr/local/bin/brew shellenv 2>/dev/null || true)"
}

install_latest_bash() {
  if brew list bash >/dev/null 2>&1; then
    log "Bash already installed via Homebrew."
  else
    log "Installing latest Bash via Homebrew..."
    brew install bash
  fi

  local bash_path
  bash_path="$(brew --prefix)/bin/bash"

  if ! grep -qx "$bash_path" /etc/shells; then
    log "Adding $bash_path to /etc/shells (sudo required)..."
    printf '%s\n' "$bash_path" | sudo tee -a /etc/shells >/dev/null
  else
    log "$bash_path already exists in /etc/shells."
  fi

  if [[ "${SHELL:-}" != "$bash_path" ]]; then
    log "Changing login shell to $bash_path (password may be required)..."
    chsh -s "$bash_path"
    warn "Login shell changed. Open a new terminal session after this script finishes."
  else
    log "Login shell already set to $bash_path."
  fi
}

configure_bash_files() {
  local home="${HOME}"
  local bash_aliases="${home}/.bash_aliases"
  local bashrc="${home}/.bashrc"
  local bash_profile="${home}/.bash_profile"

  mkdir -p "$HOME/.local/bin"

  backup_if_exists "$bash_aliases"
  backup_if_exists "$bashrc"
  backup_if_exists "$bash_profile"

  cat > "$bash_aliases" <<'EOF'
alias ls='ls -G'
alias ll='ls -al'
alias la='ls -A'
alias l='ls -CF'
alias ping2='ping -i 0.1'
EOF

  cat > "$bashrc" <<'EOF'
export PATH="$HOME/.local/bin:$PATH"

# Only set prompt for interactive shells.
case $- in
  *i*) ;;
  *) return ;;
esac

# Git branch helper for prompt.
__prompt_git_branch() {
  local branch
  branch=$(git symbolic-ref --quiet --short HEAD 2>/dev/null) || \
  branch=$(git rev-parse --short HEAD 2>/dev/null) || return 0
  printf '%s' "$branch"
}

__prompt_command() {
  local last_exit="$?"

  local reset='\[\e[0m\]'
  local red='\[\e[31m\]'
  local green='\[\e[32m\]'
  local yellow='\[\e[33m\]'
  local blue='\[\e[34m\]'
  local magenta='\[\e[35m\]'

  local status=''
  local git_branch=''

  if [[ "$last_exit" -ne 0 ]]; then
    status="${red}[exit:${last_exit}]${reset} "
  fi

  git_branch="$(__prompt_git_branch)"
  if [[ -n "$git_branch" ]]; then
    git_branch=" ${magenta}(${git_branch})${reset}"
  fi

  PS1="${status}${green}\u${reset}@${yellow}\h${reset}:${blue}\w${reset}${git_branch}\n\\$ "
}

PROMPT_COMMAND=__prompt_command

if [[ -f "$HOME/.bash_aliases" ]]; then
  . "$HOME/.bash_aliases"
fi
EOF

  cat > "$bash_profile" <<'EOF'
# Homebrew environment.
if [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -x /usr/local/bin/brew ]]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi

set -o vi

if [[ -f "$HOME/.bashrc" ]]; then
  . "$HOME/.bashrc"
fi
EOF

  log "Configured ~/.bash_aliases, ~/.bashrc, and ~/.bash_profile."
}

install_uv() {
  if command -v uv >/dev/null 2>&1; then
    log "uv already installed: $(uv --version)"
    return
  fi

  log "Installing uv via standalone installer..."
  curl -LsSf https://astral.sh/uv/install.sh | sh
}

install_common_tools() {
  log "Installing common tools..."
  install_uv
  install_cask_if_missing "visual-studio-code" "/Applications/Visual Studio Code.app"
}

install_cask_if_missing() {
  local cask="$1"
  local app_path="$2"

  if brew list --cask "$cask" >/dev/null 2>&1; then
    log "Cask already installed: $cask"
    return
  fi

  if [[ -d "$app_path" ]]; then
    log "App already present at $app_path. Skipping cask install for $cask."
    return
  fi

  brew install --cask "$cask"
}

install_optional_tools() {
  if [[ "$INSTALL_DEV_TOOLS" -eq 1 ]]; then
    log "Installing optional dev tools..."
    brew install git jq fzf ripgrep tmux
  fi

  if [[ "$INSTALL_GO_TOOLS" -eq 1 ]]; then
    log "Installing optional Go tools..."
    brew install go
  fi

  if [[ "$INSTALL_JS_TS_TOOLS" -eq 1 ]]; then
    log "Installing optional JavaScript/TypeScript tools..."
    if [[ "$MACOS_MAJOR_VERSION" -lt 13 ]]; then
      log "macOS < 13 detected; installing node@22 (LTS) instead of latest."
      brew install node@22 pnpm
      brew link --overwrite node@22
    else
      brew install node pnpm
    fi
  fi
}

print_summary() {
  log "Setup complete."
  printf '\nVersions:\n'
  brew --version | head -n1 || true
  bash --version | head -n1 || true
  uv --version || true
  if [[ "$INSTALL_DEV_TOOLS" -eq 1 ]]; then
    git --version || true
    jq --version || true
  fi
  if [[ "$INSTALL_GO_TOOLS" -eq 1 ]]; then
    go version || true
  fi
  if [[ "$INSTALL_JS_TS_TOOLS" -eq 1 ]]; then
    node --version || true
    pnpm --version || true
  fi
  printf '\nNext steps:\n'
  printf '1) Restart Terminal (or run: exec "$SHELL" -l)\n'
  printf '2) Verify shell: echo "$SHELL"\n'
}

main() {
  parse_args "$@"
  require_macos
  ensure_xcode_clt
  install_homebrew
  load_brew_shellenv
  install_latest_bash
  configure_bash_files
  install_common_tools
  install_optional_tools
  print_summary
}

main "$@"
