#!/usr/bin/env bash
#
# install-fnm.sh — install (or upgrade) fnm, the Node version manager,
# on macOS or Linux.
#
# Usage:
#   ./install-fnm.sh                  # install fnm (Homebrew on macOS, binary on Linux)
#   ./install-fnm.sh --dir ~/bin      # choose the install directory (Linux)
#   ./install-fnm.sh --no-brew        # force a direct binary install on macOS
#   ./install-fnm.sh --force          # re-run the installer even if fnm exists
#
# --skip-shell is always used: your managed ~/.zshrc already contains
# `eval "$(fnm env --use-on-cd --shell zsh)"`, so the installer must not add
# another copy to your shell profile.

set -euo pipefail

C='\033[0m'; G='\033[0;32m'; Y='\033[0;33m'; B='\033[0;34m'; R='\033[0;31m'
info() { printf '%b\n' "$*"; }
ok()   { info "  ${G}OK${C} $*"; }
warn() { info "  ${Y}WARN${C} $*"; }
fail() { info "  ${R}ERROR${C} $*" >&2; exit 1; }

usage() { sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; }

FORCE=0
NO_BREW=0
INSTALL_DIR="$HOME/.local/bin"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --force)   FORCE=1; shift ;;
    --no-brew) NO_BREW=1; shift ;;
    --dir)     INSTALL_DIR="${2:?--dir needs a path}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *)         fail "unknown option: $1 (try --help)" ;;
  esac
done

UNAME_S="$(uname -s)"
case "$UNAME_S" in
  Darwin) OS=macos ;;
  Linux)  OS=linux ;;
  *)      fail "unsupported OS: $UNAME_S (this script handles macOS and Linux)" ;;
esac
info "${B}Detected:${C} $OS"

if command -v fnm >/dev/null 2>&1 && [[ $FORCE -eq 0 ]]; then
  ok "fnm already installed: $(fnm --version) at $(command -v fnm)"
  info "  Use --force to re-run the installer."
  exit 0
fi

TMP="$(mktemp)"
if ! curl -fsSL https://fnm.vercel.app/install -o "$TMP"; then
  rm -f "$TMP"
  fail "could not download the fnm installer"
fi

FLAGS=(--skip-shell)
if [[ "$OS" == "linux" ]]; then
  FLAGS+=(--install-dir "$INSTALL_DIR")
elif [[ $NO_BREW -eq 1 ]]; then
  FLAGS+=(--force-no-brew --install-dir "$INSTALL_DIR")
else
  # macOS: the official installer uses Homebrew and ignores --install-dir.
  command -v brew >/dev/null 2>&1 || warn "Homebrew not found — falling back to a direct binary install"
  [[ $NO_BREW -eq 1 || ! -x "$(command -v brew 2>/dev/null || echo /nonexistent)" ]] && \
    FLAGS+=(--force-no-brew --install-dir "$INSTALL_DIR")
fi

bash "$TMP" "${FLAGS[@]}" || { rm -f "$TMP"; fail "fnm installer failed"; }
rm -f "$TMP"

# fnm may be installed to Homebrew's prefix on macOS, or to INSTALL_DIR on Linux.
if command -v brew >/dev/null 2>&1 && [[ "$OS" == "macos" && $NO_BREW -eq 0 ]]; then
  BREW_BIN="$(brew --prefix fnm 2>/dev/null)/bin"
  [[ -n "$BREW_BIN" && "$BREW_BIN" != "/bin" ]] && export PATH="$BREW_BIN:$PATH"
fi
export PATH="$INSTALL_DIR:$PATH"

if command -v fnm >/dev/null 2>&1; then
  ok "fnm ready: $(fnm --version) at $(command -v fnm)"
  info "  Your ~/.zshrc already evaluates fnm, so no profile changes are needed."
else
  warn "fnm installed but not on PATH in this shell"
  info "  Add this to your shell profile: export PATH=\"$INSTALL_DIR:\$PATH\""
  exit 1
fi
