#!/usr/bin/env bash
#
# install-rust.sh — install Rust with the official rustup command.
#
# Usage:
#   ./install-rust.sh              # install stable via rustup (plain curl | sh)
#   ./install-rust.sh --force      # re-run rustup even if cargo/rustc exist
#   ./install-rust.sh --help
#
# The script is idempotent: if cargo and rustc are already on PATH it does
# nothing (unless --force is given). It uses the plain official command:
#   curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
# rustup uses its default profile and adds ~/.cargo/bin to your shell startup
# files. Your managed ~/.zshrc also adds ~/.cargo/bin, so the entries are
# harmless duplicates.

set -euo pipefail

C='\033[0m'; G='\033[0;32m'; Y='\033[0;33m'; B='\033[0;34m'; R='\033[0;31m'
info() { printf '%b\n' "$*"; }
ok()   { info "  ${G}OK${C} $*"; }
warn() { info "  ${Y}WARN${C} $*"; }
fail() { info "  ${R}ERROR${C} $*" >&2; exit 1; }

usage() { sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; }

FORCE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --force)   FORCE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *)         fail "unknown option: $1 (try --help)" ;;
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

command -v curl >/dev/null 2>&1 || fail "need curl to install Rust (curl --proto ... | sh)"
info "  Installing Rust with rustup (plain official command) ..."
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh || fail "rustup installation failed"

export PATH="$HOME/.cargo/bin:$PATH"
if command -v rustc >/dev/null 2>&1; then
  ok "Rust ready: $(rustc --version)"
  ok "Cargo: $(command -v cargo)"
  info "  rustup adds ~/.cargo/bin to your shell profile; ~/.zshrc does too (harmless)."
else
  fail "rustc still not found — check ~/.cargo/bin"
fi
