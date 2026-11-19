#!/usr/bin/env bash
#
# install-rust.sh — install (or upgrade) Rust with rustup on macOS or Linux.
#
# Usage:
#   ./install-rust.sh                    # install stable, minimal profile
#   ./install-rust.sh --profile default # include rustfmt/clippy/docs
#   ./install-rust.sh --force            # re-run rustup even if Rust exists
#   ./install-rust.sh --modify-path      # let rustup edit your shell profile
#
# By default --no-modify-path is used: this dotfiles setup already adds
# ~/.cargo/bin to PATH in ~/.zshrc, so rustup does not need to edit profiles.

set -euo pipefail

C='\033[0m'; G='\033[0;32m'; Y='\033[0;33m'; B='\033[0;34m'; R='\033[0;31m'
info() { printf '%b\n' "$*"; }
ok()   { info "  ${G}OK${C} $*"; }
warn() { info "  ${Y}WARN${C} $*"; }
fail() { info "  ${R}ERROR${C} $*" >&2; exit 1; }

usage() { sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; }

FORCE=0
PROFILE="minimal"
MODIFY_PATH=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --force)       FORCE=1; shift ;;
    --profile)     PROFILE="${2:?--profile needs a value (minimal|default|full)}"; shift 2 ;;
    --modify-path) MODIFY_PATH=1; shift ;;
    -h|--help)     usage; exit 0 ;;
    *)             fail "unknown option: $1 (try --help)" ;;
  esac
done

case "$(uname -s)" in
  Darwin) info "${B}Detected:${C} macOS" ;;
  Linux)  info "${B}Detected:${C} Linux" ;;
  *)      fail "unsupported OS — this script handles macOS and Linux" ;;
esac

if command -v cargo >/dev/null 2>&1 && command -v rustc >/dev/null 2>&1 && [[ $FORCE -eq 0 ]]; then
  ok "Rust already installed: $(rustc --version) at $(command -v cargo)"
  info "  Use --force to re-run rustup."
  exit 0
fi

if command -v rustup >/dev/null 2>&1 && [[ $FORCE -eq 0 ]]; then
  warn "rustup exists but cargo/rustc are missing — installing the stable toolchain"
  rustup toolchain install stable --profile "$PROFILE" || fail "rustup toolchain install failed"
  rustup default stable || fail "could not set stable as default"
else
  TMP="$(mktemp)"
  if command -v curl >/dev/null 2>&1; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs -o "$TMP" || fail "could not download rustup"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$TMP" https://sh.rustup.rs || fail "could not download rustup"
  else
    fail "need curl or wget to install Rust"
  fi

  NO_MODIFY_FLAG=""
  [[ $MODIFY_PATH -eq 0 ]] && NO_MODIFY_FLAG="--no-modify-path"

  sh "$TMP" -y --default-toolchain stable --profile "$PROFILE" $NO_MODIFY_FLAG \
    || fail "rustup installation failed"
  rm -f "$TMP"
fi

export PATH="$HOME/.cargo/bin:$PATH"
if command -v rustc >/dev/null 2>&1; then
  ok "Rust ready: $(rustc --version)"
  ok "Cargo: $(command -v cargo)"
  if [[ $MODIFY_PATH -eq 0 ]]; then
    info "  ~/.cargo/bin is added to PATH by your managed ~/.zshrc."
    info "  For other shells, add: export PATH=\"\$HOME/.cargo/bin:\$PATH\""
  fi
else
  fail "rustc still not found — check ~/.cargo/bin"
fi
