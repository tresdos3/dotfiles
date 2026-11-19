#!/usr/bin/env bash
#
# install-git.sh — install git and configure identity/auth on macOS or Linux.
#
# Usage:
#   ./install-git.sh                    # install (if needed) + configure interactively
#   ./install-git.sh --no-auth          # do not configure the credential helper
#   ./install-git.sh --help
#
# If git is already installed, installation is skipped. The script always shows
# your current global name/email and asks for new ones (press ENTER to keep a
# value), then writes them with `git config --global`.
#
# It also disables commit signing globally (avoids failures from a missing SSH
# signing key) and configures an HTTPS credential helper so GitHub works over
# HTTPS with a Personal Access Token — no SSH keys involved.

set -euo pipefail

C='\033[0m'; G='\033[0;32m'; Y='\033[0;33m'; B='\033[0;34m'; R='\033[0;31m'
info() { printf '%b\n' "$*"; }
ok()   { info "  ${G}OK${C} $*"; }
warn() { info "  ${Y}WARN${C} $*"; }
fail() { info "  ${R}ERROR${C} $*" >&2; exit 1; }

usage() { sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; }

SET_AUTH=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-auth) SET_AUTH=0; shift ;;
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
info "${B}Detected OS:${C} $OS"

# ---------------------------------------------------------------------------
# 1. Install git only if missing
# ---------------------------------------------------------------------------
if command -v git >/dev/null 2>&1; then
  ok "git already installed: $(git --version) at $(command -v git)"
else
  info "  Installing git ..."
  case "$OS" in
    macos)
      command -v brew >/dev/null 2>&1 || fail "Homebrew is required on macOS — install it from https://brew.sh"
      brew install git
      ;;
    linux)
      SUDO=""
      [[ $EUID -eq 0 ]] || { command -v sudo >/dev/null 2>&1 && SUDO="sudo" || fail "need root or sudo"; }
      if command -v apt-get >/dev/null 2>&1; then
        $SUDO apt-get update -qq && $SUDO apt-get install -y git
      elif command -v dnf >/dev/null 2>&1; then
        $SUDO dnf install -y git
      elif command -v pacman >/dev/null 2>&1; then
        $SUDO pacman -S --noconfirm --needed git
      elif command -v zypper >/dev/null 2>&1; then
        $SUDO zypper --non-interactive install git
      elif command -v apk >/dev/null 2>&1; then
        $SUDO apk add --no-cache git
      else
        fail "no supported package manager found — install git manually"
      fi
      ;;
  esac
  command -v git >/dev/null 2>&1 || fail "git installation failed"
  ok "git installed: $(git --version)"
fi

# ---------------------------------------------------------------------------
# 2. Identity — show current values, ask, then write globally
# ---------------------------------------------------------------------------
info ""
info "${B}Git identity (global)${C}"
CUR_NAME="$(git config --global --get user.name 2>/dev/null || true)"
CUR_EMAIL="$(git config --global --get user.email 2>/dev/null || true)"
info "  current name:  ${CUR_NAME:-<not set>}"
info "  current email: ${CUR_EMAIL:-<not set>}"

printf '  New name  [press ENTER to keep "%s"]: ' "${CUR_NAME:-}"
read -r NEW_NAME
NEW_NAME="${NEW_NAME:-$CUR_NAME}"
[[ -n "$NEW_NAME" ]] || fail "a name is required"

printf '  New email [press ENTER to keep "%s"]: ' "${CUR_EMAIL:-}"
read -r NEW_EMAIL
NEW_EMAIL="${NEW_EMAIL:-$CUR_EMAIL}"
[[ -n "$NEW_EMAIL" ]] || fail "an email is required"

git config --global user.name  "$NEW_NAME"
git config --global user.email "$NEW_EMAIL"
ok "global identity set to: $NEW_NAME <$NEW_EMAIL>"

# ---------------------------------------------------------------------------
# 3. Disable commit signing globally (missing signing keys break commits)
# ---------------------------------------------------------------------------
git config --global commit.gpgsign false
ok "commit signing disabled globally (commit.gpgsign=false)"

# ---------------------------------------------------------------------------
# 4. HTTPS credential helper (no SSH keys)
# ---------------------------------------------------------------------------
if [[ $SET_AUTH -eq 1 ]]; then
  info ""
  info "${B}HTTPS credentials${C}"
  if [[ "$OS" == "macos" ]]; then
    git config --global credential.helper osxkeychain
    ok "credential.helper = osxkeychain (macOS Keychain)"
  else
    if command -v git-credential-libsecret >/dev/null 2>&1 || \
       [[ -f /usr/lib/git-core/git-credential-libsecret || -f /usr/libexec/git-core/git-credential-libsecret ]]; then
      git config --global credential.helper libsecret
      ok "credential.helper = libsecret"
    else
      warn "libsecret helper not found — install 'git-credential-libsecret' / 'libsecret' for your distro"
      warn "or run: git config --global credential.helper <helper-of-your-choice>"
    fi
  fi
  info ""
  info "  For GitHub over HTTPS you need a Personal Access Token (PAT):"
  info "    GitHub -> Settings -> Developer settings -> Personal access tokens -> Tokens (classic)"
  info "    Enable the 'repo' scope, copy the token, and paste it as the password on your first push."
  info "  The helper stores it securely so you won't be asked again."
fi

info ""
info "${B}Done.${C} Your repos now use HTTPS + PAT — no SSH keys required."
