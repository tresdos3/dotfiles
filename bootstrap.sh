#!/usr/bin/env bash
#
# bootstrap.sh — prepare a fresh Linux OR macOS machine, then pull dotfiles
# with chezmoi. Uses your distro package manager on Linux, Homebrew on macOS.
#
# Usage:
#   ./bootstrap.sh [options] [git-repo-url]
#
# Options:
#   --no-rust      skip the Rust/rustup install
#   -h, --help     show this help
#
# Examples:
#   ./bootstrap.sh https://github.com/YOUR_USER/dotfiles.git
#   ./bootstrap.sh --no-rust                 # prompts for the URL
#
# What it does:
#   1. detects your OS and package manager (Homebrew on macOS)
#   2. installs only the MISSING packages (zsh, git, nvim, wezterm, font,
#      git-lfs, ...) — anything already present is skipped
#   3. installs chezmoi (skipped if already installed)
#   4. installs missing dev tools: fnm, p10k, zsh plugins, Rust (via rustup)
#   5. writes ~/.config/chezmoi/chezmoi.toml with your machine-specific values
#   6. chezmoi init <repo> -> chezmoi diff -> confirm -> chezmoi apply
#
# It never runs destructive commands against your data and asks before applying
# dotfiles over anything that already exists in $HOME.

set -euo pipefail

REPO_URL=""
SKIP_RUST=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-rust)   SKIP_RUST=1; shift ;;
    -h|--help)   sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)          { printf 'Unknown option: %s\n' "$1" >&2; exit 2; } ;;
    *)
      if [[ -z "$REPO_URL" ]]; then REPO_URL="$1"; shift
      else printf 'Too many arguments\n' >&2; exit 2; fi
      ;;
  esac
done

C='\033[0m'; G='\033[0;32m'; Y='\033[0;33m'; B='\033[0;34m'; R='\033[0;31m'
info()  { printf '%b\n' "$*"; }
lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }   # Bash 3.2 compatible
ok()    { info "  ${G}OK${C} $*"; }
warn()  { info "  ${Y}WARN${C} $*"; }
fail()  { info "  ${R}ERROR${C} $*" >&2; exit 1; }
step()  { info ""; info "${B}$*${C}"; }

# ---------------------------------------------------------------------------
# 0. Preconditions
# ---------------------------------------------------------------------------
UNAME_S="$(uname -s)"
case "$UNAME_S" in
  Linux)  OS=linux ;;
  Darwin) OS=macos ;;
  *)      fail "unsupported OS: $UNAME_S (this script handles macOS and Linux)" ;;
esac
info "${B}Detected OS:${C} $OS"

if [[ $EUID -eq 0 ]]; then
  SUDO=""
elif command -v sudo >/dev/null 2>&1; then
  SUDO="sudo"
else
  fail "Need root or sudo to install packages."
fi

# ---------------------------------------------------------------------------
# 1. Detect package manager
# ---------------------------------------------------------------------------
step "[1/7] Detecting package manager"
if [[ "$OS" == "macos" ]]; then
  command -v brew >/dev/null 2>&1 || fail "Homebrew is required on macOS — install it from https://brew.sh, then re-run"
  PM=brew;   FONT_PKG=font-jetbrains-mono
elif command -v apt-get >/dev/null 2>&1; then
  PM=apt;    FONT_PKG=fonts-jetbrains-mono
elif command -v dnf >/dev/null 2>&1; then
  PM=dnf;    FONT_PKG=jetbrains-mono-fonts
elif command -v pacman >/dev/null 2>&1; then
  PM=pacman; FONT_PKG=ttf-jetbrains-mono
elif command -v zypper >/dev/null 2>&1; then
  PM=zypper; FONT_PKG=jetbrains-mono-fonts
elif command -v apk >/dev/null 2>&1; then
  PM=apk;    FONT_PKG=font-jetbrains-mono
else
  fail "Unsupported package manager. Install these manually: zsh git curl wget git-lfs neovim wezterm chezmoi"
fi
ok "package manager: $PM"

# Each entry is "command:package" — the command is what we test for.
REQUIRED=( "zsh:zsh" "git:git" "curl:curl" "wget:wget" "git-lfs:git-lfs" "nvim:neovim" "wezterm:wezterm" )
OPTIONAL=( "fish:fish" )

install_pkgs() {
  case "$PM" in
    brew)
      local p
      for p in "$@"; do
        case "$p" in
          wezterm|font-jetbrains-mono) brew install --cask "$p" ;;
          *)                          brew install "$p" ;;
        esac
      done
      ;;
    apt)    $SUDO apt-get install -y "$@" ;;
    dnf)    $SUDO dnf install -y "$@" ;;
    pacman) $SUDO pacman -S --noconfirm --needed "$@" ;;
    zypper) $SUDO zypper --non-interactive install "$@" ;;
    apk)    $SUDO apk add --no-cache "$@" ;;
  esac
}

# Install a package only if its command is missing. One failure never blocks
# the remaining packages.
ensure_cmd() {
  local cmd="$1" pkg="$2"
  if command -v "$cmd" >/dev/null 2>&1; then
    ok "$cmd already installed — skipping"
    return 0
  fi
  info "  Installing $cmd (package: $pkg) ..."
  if install_pkgs "$pkg"; then
    command -v "$cmd" >/dev/null 2>&1 && ok "$cmd installed" || warn "$pkg installed but '$cmd' still not on PATH"
  else
    warn "could not install $pkg — continuing"
  fi
}

# ---------------------------------------------------------------------------
# 2. Packages (only the missing ones)
# ---------------------------------------------------------------------------
step "[2/7] Checking packages (already-installed apps are skipped)"
if [[ "$PM" == "apt" ]]; then
  info "  refreshing apt package lists ..."
  $SUDO apt-get update -qq || warn "apt-get update failed — continuing with cached lists"
fi

for pair in "${REQUIRED[@]}"; do
  ensure_cmd "${pair%%:*}" "${pair#*:}"
done

# Font: fontconfig on Linux, font directories on macOS.
font_installed() {
  if command -v fc-list >/dev/null 2>&1 && fc-list 2>/dev/null | grep -qi 'JetBrains Mono'; then
    return 0
  fi
  if [[ "$OS" == "macos" ]]; then
    local d
    for d in /Library/Fonts "$HOME/Library/Fonts" /System/Library/Fonts; do
      compgen -G "$d/*JetBrains*Mono*" >/dev/null 2>&1 && return 0
    done
  fi
  return 1
}

if font_installed; then
  ok "JetBrains Mono font already installed — skipping"
else
  info "  Installing JetBrains Mono font (package: $FONT_PKG) ..."
  install_pkgs "$FONT_PKG" >/dev/null 2>&1 \
    && ok "JetBrains Mono installed" \
    || warn "could not install $FONT_PKG — install a monospace font manually"
fi

for pair in "${OPTIONAL[@]}"; do
  ensure_cmd "${pair%%:*}" "${pair#*:}"
done

if ! command -v wezterm >/dev/null 2>&1; then
  warn "wezterm is not on PATH. If it is not available from your package source, see https://wezterm.org/install"
fi

# ---------------------------------------------------------------------------
# 3. chezmoi
# ---------------------------------------------------------------------------
step "[3/7] Installing chezmoi"
BOOTSTRAP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$BOOTSTRAP_DIR/install-chezmoi.sh" ]]; then
  # Prefer the shared cross-platform installer when it was copied alongside.
  bash "$BOOTSTRAP_DIR/install-chezmoi.sh" || fail "chezmoi installation failed"
  export PATH="$HOME/.local/bin:$PATH"
elif command -v chezmoi >/dev/null 2>&1; then
  ok "chezmoi already installed: $(chezmoi --version)"
else
  INSTALLER="$(mktemp)"
  curl -fsSL https://get.chezmoi.io/lb -o "$INSTALLER" || fail "could not download the chezmoi installer"
  sh "$INSTALLER" -b "$HOME/.local/bin" || fail "chezmoi installer failed"
  rm -f "$INSTALLER"
  export PATH="$HOME/.local/bin:$PATH"
  command -v chezmoi >/dev/null 2>&1 || fail "chezmoi install failed — check ~/.local/bin in PATH"
  ok "chezmoi installed: $(chezmoi --version)"
fi

# ---------------------------------------------------------------------------
# 4. zsh ecosystem (fnm, powerlevel10k, plugins) — skip what already exists
# ---------------------------------------------------------------------------
step "[4/7] Installing zsh tools (fnm, powerlevel10k, plugins)"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"

# fnm (Node version manager)
if [[ -f "$BOOTSTRAP_DIR/install-fnm.sh" ]]; then
  bash "$BOOTSTRAP_DIR/install-fnm.sh" || warn "fnm installer failed — see https://fnm.vercel.app"
elif command -v fnm >/dev/null 2>&1; then
  ok "fnm already installed"
else
  curl -fsSL https://fnm.vercel.app/install | bash -s -- --skip-shell --install-dir "$HOME/.local/bin" \
    && ok "fnm installed" \
    || warn "fnm install failed — install it from https://fnm.vercel.app"
fi
export PATH="$HOME/.local/bin:$PATH"

# powerlevel10k — also accept an existing Homebrew install on macOS.
if [[ -f "$DATA/powerlevel10k/powerlevel10k.zsh" \
   || -f /opt/homebrew/share/powerlevel10k/powerlevel10k.zsh \
   || -f /usr/local/share/powerlevel10k/powerlevel10k.zsh ]]; then
  ok "powerlevel10k already installed"
else
  mkdir -p "$DATA"
  git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$DATA/powerlevel10k" \
    && ok "powerlevel10k installed" \
    || warn "powerlevel10k install failed"
fi

# zsh plugins — also accept existing Homebrew copies.
mkdir -p "$DATA/zsh/plugins"
for plugin in zsh-autosuggestions zsh-syntax-highlighting; do
  if [[ -d "$DATA/zsh/plugins/$plugin" \
     || -d "/opt/homebrew/share/$plugin" \
     || -d "/usr/local/share/$plugin" ]]; then
    ok "$plugin already installed"
  else
    git clone --depth=1 "https://github.com/zsh-users/$plugin.git" "$DATA/zsh/plugins/$plugin" \
      && ok "$plugin installed" \
      || warn "$plugin install failed"
  fi
done

# pnpm via corepack (Node must be installed with fnm first)
if command -v corepack >/dev/null 2>&1; then
  corepack enable 2>/dev/null && corepack prepare pnpm@latest --activate 2>/dev/null \
    && ok "pnpm enabled via corepack" \
    || warn "could not enable pnpm — run 'corepack enable' once Node is installed"
else
  warn "corepack not found — install Node with fnm, then run: corepack enable && corepack prepare pnpm@latest --activate"
fi

git lfs install >/dev/null 2>&1 && ok "git-lfs initialized" || warn "git lfs install failed"

# ---------------------------------------------------------------------------
# 6. Rust (via rustup) — skipped if already installed
# ---------------------------------------------------------------------------
step "[5/7] Installing Rust (rustup)"
if [[ $SKIP_RUST -eq 1 ]]; then
  info "  ${Y}SKIP${C}    Rust (--no-rust)"
elif [[ -f "$BOOTSTRAP_DIR/install-rust.sh" ]]; then
  bash "$BOOTSTRAP_DIR/install-rust.sh" || fail "Rust installation failed"
  export PATH="$HOME/.cargo/bin:$PATH"
elif command -v cargo >/dev/null 2>&1 && command -v rustc >/dev/null 2>&1; then
  ok "Rust already installed: $(rustc --version)"
else
  RUSTUP_TMP="$(mktemp)"
  if command -v curl >/dev/null 2>&1; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs -o "$RUSTUP_TMP" \
      || fail "could not download rustup"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$RUSTUP_TMP" https://sh.rustup.rs || fail "could not download rustup"
  else
    fail "need curl or wget to install Rust"
  fi
  # --no-modify-path: your managed ~/.zshrc already adds ~/.cargo/bin to PATH.
  sh "$RUSTUP_TMP" -y --default-toolchain stable --profile minimal --no-modify-path \
    || fail "rustup installation failed"
  rm -f "$RUSTUP_TMP"
  export PATH="$HOME/.cargo/bin:$PATH"
  ok "Rust installed: $(rustc --version)"
fi

# ---------------------------------------------------------------------------
# 6. chezmoi config with machine-specific values
# ---------------------------------------------------------------------------
step "[6/7] Machine-specific chezmoi config"
mkdir -p "$HOME/.config/chezmoi"
CONFIG="$HOME/.config/chezmoi/chezmoi.toml"
if [[ -f "$CONFIG" ]]; then
  warn "$CONFIG already exists — leaving it untouched"
else
  read -r -p "  Git email [you@example.com]: " EMAIL
  EMAIL="${EMAIL:-you@example.com}"
  cat > "$CONFIG" <<EOF
[data]
    email = "$EMAIL"
EOF
  ok "wrote $CONFIG"
fi

if [[ -z "$REPO_URL" ]]; then
  read -r -p "  Kit repo URL [https://github.com/YOUR_USER/dotfiles-kit.git]: " REPO_URL
fi
[[ -n "$REPO_URL" ]] || fail "No repo URL provided."

# The kit repo contains both the scripts and the collected dotfiles in config/.
KIT_DIR="${KIT_DIR:-$HOME/Documents/dotfiles-kit}"
if [[ ! -d "$KIT_DIR" ]]; then
  git clone "$REPO_URL" "$KIT_DIR" \
    || fail "git clone failed. Check the URL and your HTTPS credentials (PAT)."
  ok "cloned kit repo to $KIT_DIR"
else
  warn "kit folder already exists at $KIT_DIR — skipping clone"
fi
mkdir -p "$KIT_DIR/config"

if grep -q '^sourceDir' "$CONFIG" 2>/dev/null; then
  warn "sourceDir already set in $CONFIG — leaving it untouched"
else
  TMP_CFG="${CONFIG}.tmp"
  printf 'sourceDir = "%s/config"\n\n' "$KIT_DIR" > "$TMP_CFG"
  if [[ -f "$CONFIG" ]]; then cat "$CONFIG" >> "$TMP_CFG"; fi
  mv "$TMP_CFG" "$CONFIG"
  ok "chezmoi sourceDir = $KIT_DIR/config"
fi

# ---------------------------------------------------------------------------
# 7. Review and apply
# ---------------------------------------------------------------------------
step "[7/7] Review and apply"
info "  Previewing changes (chezmoi diff) ..."
chezmoi diff || true

info ""
info "  ${Y}ADOPT${C} — these template paths on Linux (the bootstrap installed them):"
info "    p10k:         $DATA/powerlevel10k/powerlevel10k.zsh"
info "    autosuggest:  $DATA/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh"
info "    highlighting: $DATA/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
info "  ${Y}CHANGE${C} — if your templates still point at /opt/homebrew, edit them with:"
info "    chezmoi edit ~/.zshrc && chezmoi apply"
info ""

read -r -p "  Apply dotfiles over $HOME now? [y/N] " APPLY
if [[ "$(lower "$APPLY")" == "y" || "$(lower "$APPLY")" == "yes" ]]; then
  chezmoi apply || fail "chezmoi apply failed"
  ok "dotfiles applied"
else
  warn "skipped 'chezmoi apply' — run it yourself when ready"
fi

step "Done — final manual steps"
info "  1. Open nvim once; LazyVim will bootstrap plugins (needs internet)."
info "  2. Install JetBrains Mono if your terminal did not pick it up."
info "  3. To refresh configs later: chezmoi cd && git pull && chezmoi apply"
info "     (or use ./git-sync.sh in the chezmoi source repo to pull + commit + push)"
