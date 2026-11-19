#!/usr/bin/env bash
#
# install-chezmoi.sh — install (or upgrade) chezmoi on macOS or Linux.
#
# Usage:
#   ./install-chezmoi.sh                 # auto: Homebrew if present, else official binary
#   ./install-chezmoi.sh --brew          # force Homebrew (macOS or Linuxbrew)
#   ./install-chezmoi.sh --pkg           # force your distro package manager (Linux)
#   ./install-chezmoi.sh --script        # force official binary installer -> ~/.local/bin
#   ./install-chezmoi.sh --dir ~/bin     # choose binary install directory
#   ./install-chezmoi.sh --force         # reinstall/upgrade even if already installed
#
# The script is idempotent: if chezmoi is already on PATH it exits unless
# --force is given. It never modifies your shell profile — if the binary is
# installed to a directory not on PATH, it prints the line to add yourself.

set -euo pipefail

C='\033[0m'; G='\033[0;32m'; Y='\033[0;33m'; B='\033[0;34m'; R='\033[0;31m'
info() { printf '%b\n' "$*"; }
ok()   { info "  ${G}OK${C} $*"; }
warn() { info "  ${Y}WARN${C} $*"; }
fail() { info "  ${R}ERROR${C} $*" >&2; exit 1; }

METHOD="auto"
FORCE=0
INSTALL_DIR="$HOME/.local/bin"

usage() { sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --brew)   METHOD="brew"; shift ;;
    --pkg)    METHOD="pkg"; shift ;;
    --script) METHOD="script"; shift ;;
    --dir)    INSTALL_DIR="${2:?--dir needs a path}"; shift 2 ;;
    --force)  FORCE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) fail "unknown option: $1 (try --help)" ;;
  esac
done

# ---------------------------------------------------------------------------
# Detect OS / architecture
# ---------------------------------------------------------------------------
UNAME_S="$(uname -s)"
case "$UNAME_S" in
  Darwin) OS="macos" ;;
  Linux)  OS="linux" ;;
  *)      fail "unsupported OS: $UNAME_S (this script handles macOS and Linux)" ;;
esac
ARCH="$(uname -m)"
case "$ARCH" in
  arm64|aarch64) ARCH_LABEL="arm64" ;;
  x86_64|amd64)  ARCH_LABEL="amd64" ;;
  *)             ARCH_LABEL="$ARCH" ;;
esac
info "${B}Detected:${C} $OS / $ARCH ($ARCH_LABEL)"

# ---------------------------------------------------------------------------
# Already installed?
# ---------------------------------------------------------------------------
if command -v chezmoi >/dev/null 2>&1 && [[ $FORCE -eq 0 ]]; then
  ok "chezmoi already installed: $(chezmoi --version) at $(command -v chezmoi)"
  info "  Use ${Y}--force${C} to upgrade."
  exit 0
fi

# ---------------------------------------------------------------------------
# Resolve method
# ---------------------------------------------------------------------------
if [[ "$METHOD" == "auto" ]]; then
  if command -v brew >/dev/null 2>&1; then
    METHOD="brew"
  else
    METHOD="script"
  fi
fi
info "  Method: $METHOD"

install_with_brew() {
  command -v brew >/dev/null 2>&1 || fail "--brew requested but Homebrew was not found"
  brew install chezmoi
  if [[ $FORCE -eq 1 ]]; then brew upgrade chezmoi 2>/dev/null || true; fi
}

install_with_pkg() {
  [[ "$OS" == "linux" ]] || fail "--pkg is for Linux; on macOS use --brew or --script"
  local SUDO=""
  [[ $EUID -eq 0 ]] || { command -v sudo >/dev/null 2>&1 && SUDO="sudo" || fail "need root or sudo"; }
  if command -v apt-get >/dev/null 2>&1; then
    $SUDO apt-get update -qq && $SUDO apt-get install -y chezmoi
  elif command -v dnf >/dev/null 2>&1; then
    $SUDO dnf install -y chezmoi
  elif command -v pacman >/dev/null 2>&1; then
    $SUDO pacman -S --noconfirm --needed chezmoi
  elif command -v zypper >/dev/null 2>&1; then
    $SUDO zypper --non-interactive install chezmoi
  elif command -v apk >/dev/null 2>&1; then
    $SUDO apk add --no-cache chezmoi
  else
    fail "no supported package manager found — use --script"
  fi
}

install_with_script() {
  # The /lb endpoint installs to ~/.local/bin; -b overrides the directory.
  local tmp
  tmp="$(mktemp)"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL https://get.chezmoi.io/lb -o "$tmp" || fail "could not download the chezmoi installer"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$tmp" https://get.chezmoi.io/lb || fail "could not download the chezmoi installer"
  else
    fail "need curl or wget to install chezmoi"
  fi
  # Important: do NOT insert a `--` before -b. The official script uses POSIX
  # getopts, so a leading `--` stops option parsing and the -b flag is ignored.
  sh "$tmp" -b "$INSTALL_DIR" || fail "chezmoi installer failed"
  rm -f "$tmp"
  export PATH="$INSTALL_DIR:$PATH"
  case ":$PATH:" in
    *":$INSTALL_DIR:"*) ;;
    *) warn "add this to your shell profile so chezmoi is found in new shells:"
       info "     export PATH=\"$INSTALL_DIR:\$PATH\"" ;;
  esac
}

case "$METHOD" in
  brew)   install_with_brew ;;
  pkg)    install_with_pkg ;;
  script) install_with_script ;;
  *)      fail "invalid method: $METHOD" ;;
esac

# ---------------------------------------------------------------------------
# Verify
# ---------------------------------------------------------------------------
if command -v chezmoi >/dev/null 2>&1; then
  ok "chezmoi ready: $(chezmoi --version) at $(command -v chezmoi)"
else
  warn "installed, but 'chezmoi' is not on PATH in this shell"
  info "  Try: export PATH=\"$INSTALL_DIR:\$PATH\""
  info "  Or reopen your terminal after adding the line above to your profile."
  exit 1
fi

info ""
info "Next:"
info "  chezmoi init                       # on this machine (first time)"
info "  chezmoi init <repo-url>            # on a new machine"
