#!/usr/bin/env bash
set -euo pipefail

INSTALL_DEV_TOOLS=0

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
}

print_usage() {
  cat <<'EOF'
Usage: ./setup_new_mac.sh [options]

Options:
  --dev-tools   Install optional dev tools: git, jq, fzf, ripgrep, tmux
  --all         Install all optional groups (currently same as --dev-tools)
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
      --all)
        INSTALL_DEV_TOOLS=1
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
  warn "If prompted, finish the GUI install, then run this script again."
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
  if command -v brew >/dev/null 2>&1; then
    eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || true)"
    eval "$(/usr/local/bin/brew shellenv 2>/dev/null || true)"
    eval "$(brew shellenv)"
  fi
}

install_latest_bash() {
  log "Installing latest Bash via Homebrew..."
  brew install bash

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

install_common_tools() {
  log "Installing common tools..."
  brew install uv
  brew install --cask visual-studio-code
}

install_optional_tools() {
  if [[ "$INSTALL_DEV_TOOLS" -eq 1 ]]; then
    log "Installing optional dev tools..."
    brew install git jq fzf ripgrep tmux
  fi
}

print_summary() {
  log "Setup complete."
  printf '\nVersions:\n'
  brew --version | head -n1 || true
  bash --version | head -n1 || true
  uv --version || true
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
