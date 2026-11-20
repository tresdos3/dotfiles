#!/usr/bin/env bash
#
# bootstrap.sh — prepare a fresh Linux OR macOS machine, then apply the dotfiles
# you select with chezmoi. Uses your distro package manager on Linux and
# Homebrew on macOS.
#
# Usage:
#   ./bootstrap.sh [options] [git-repo-url]
#
# Options:
#   --no-rust      disable the Rust component (kept for compatibility)
#   -y, --yes      accept all menu defaults without prompting
#   -h, --help     show this help and exit
#
# Two interactive checklists let you choose which components to install and
# which dotfiles to apply. Press ENTER to keep the shown default, type 'y'/'n'
# for a single item, 'a' to accept all, or 'x' to accept none.
#
# Examples:
#   ./bootstrap.sh https://github.com/YOUR_USER/dotfiles.git
#   ./bootstrap.sh --yes https://github.com/YOUR_USER/dotfiles.git
#   ./bootstrap.sh --no-rust                 # prompts for the URL
#
# What it does:
#   1. asks which components / dotfiles you want
#   2. detects the OS and package manager (adds the WezTerm apt repo when needed)
#   3. installs only the SELECTED packages that are missing
#   4. installs chezmoi, then the selected tools (fnm, p10k, plugins, Rust, ...)
#   5. clones (or reuses) the repo and writes ~/.config/chezmoi/chezmoi.toml
#   6. previews the selected dotfiles, asks, then runs chezmoi apply on them
#
# It never runs destructive commands against your data and asks before applying
# dotfiles over anything that already exists in $HOME.

set -euo pipefail

usage() {
  cat <<'USAGE'
bootstrap.sh — prepare a fresh Linux or macOS machine, then apply selected dotfiles.

Usage:
  ./bootstrap.sh [options] [git-repo-url]

Options:
  --no-rust      disable the Rust component (kept for compatibility)
  -y, --yes      accept all menu defaults without prompting
  -h, --help     show this help and exit

Selection:
  Two interactive checklists let you choose which components to install and
  which dotfiles to apply. ENTER keeps the shown default, y/n toggles one item,
  'a' accepts all and 'x' accepts none. --yes accepts every default.

Examples:
  ./bootstrap.sh https://github.com/YOUR_USER/dotfiles.git
  ./bootstrap.sh --yes https://github.com/YOUR_USER/dotfiles.git
  ./bootstrap.sh --no-rust
USAGE
}

REPO_URL=""
SKIP_RUST=0
ASSUME_YES=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-rust)   SKIP_RUST=1; shift ;;
    -y|--yes)    ASSUME_YES=1; shift ;;
    -h|--help)   usage; exit 0 ;;
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

BOOTSTRAP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Component registry (parallel arrays — Bash 3.2 compatible, works on macOS)
# ---------------------------------------------------------------------------
COMP_KEYS=(zsh gitlfs nvim fish wezterm font fnm p10k plugins rust credential uv ghostty)
COMP_LABELS=(
  "zsh shell"
  "Git LFS"
  "Neovim editor"
  "fish shell"
  "WezTerm terminal"
  "JetBrains Mono font"
  "fnm + Node + pnpm"
  "powerlevel10k theme"
  "zsh plugins (autosuggest, highlight)"
  "Rust (rustup)"
  "Git credential helper (oauth/libsecret)"
  "uv (Python tooling)"
  "Ghostty terminal"
)
COMP_DEFAULT=(1 1 1 1 1 1 1 1 1 1 1 0 0)
COMP_ON=("${COMP_DEFAULT[@]}")

# Dotfile groups mapped to the targets passed to `chezmoi diff` / `chezmoi apply`.
DOT_KEYS=(zsh git wezterm nvim ghostty fish warp)
DOT_LABELS=(
  "zsh (.zshrc, .zprofile, .p10k.zsh)"
  "git (.gitconfig, ignore files, commit template)"
  "WezTerm (.wezterm.lua)"
  "Neovim (~/.config/nvim)"
  "Ghostty (~/.config/ghostty)"
  "fish (~/.config/fish)"
  "Warp (~/.warp, macOS only)"
)
DOT_DEFAULT=(1 1 1 1 1 1 1)
DOT_ON=("${DOT_DEFAULT[@]}")

dot_targets_for() {
  case "$1" in
    zsh)     printf '%s\n' "$HOME/.zshrc" "$HOME/.zprofile" "$HOME/.p10k.zsh" ;;
    git)     printf '%s\n' "$HOME/.gitconfig" "$HOME/.gitignore_global" "$HOME/.hgignore_global" "$HOME/.stCommitMsg" ;;
    wezterm) printf '%s\n' "$HOME/.wezterm.lua" ;;
    nvim)    printf '%s\n' "$HOME/.config/nvim" ;;
    ghostty) printf '%s\n' "$HOME/.config/ghostty" ;;
    fish)    printf '%s\n' "$HOME/.config/fish" ;;
    warp)    printf '%s\n' "$HOME/.warp" ;;
  esac
}

comp_on() {
  local i
  for i in "${!COMP_KEYS[@]}"; do
    [[ "${COMP_KEYS[$i]}" == "$1" && ${COMP_ON[$i]} -eq 1 ]] && return 0
  done
  return 1
}

dot_on() {
  local i
  for i in "${!DOT_KEYS[@]}"; do
    [[ "${DOT_KEYS[$i]}" == "$1" && ${DOT_ON[$i]} -eq 1 ]] && return 0
  done
  return 1
}

select_components() {
  local i j ans def
  info "  ${B}Components to install${C}"
  info "  ENTER = keep default | y/n = toggle one | a = all | x = none"
  for i in "${!COMP_KEYS[@]}"; do
    if [[ ${COMP_DEFAULT[$i]} -eq 1 ]]; then def="y"; else def="n"; fi
    ans="$def"
    if [[ $ASSUME_YES -eq 0 ]]; then
      printf '  [%2d] %-40s [%s]: ' "$((i + 1))" "${COMP_LABELS[$i]}" "$def"
      read -r ans || ans="$def"
      ans="${ans:-$def}"
    fi
    case "$ans" in
      a|A)
        for j in "${!COMP_KEYS[@]}"; do COMP_ON[$j]=1; done
        break
        ;;
      x|X)
        for j in "${!COMP_KEYS[@]}"; do COMP_ON[$j]=0; done
        break
        ;;
    esac
    case "$ans" in
      y|Y|yes|YES) COMP_ON[$i]=1 ;;
      *)           COMP_ON[$i]=0 ;;
    esac
  done

  if [[ $SKIP_RUST -eq 1 ]]; then
    for i in "${!COMP_KEYS[@]}"; do
      [[ "${COMP_KEYS[$i]}" == "rust" ]] && COMP_ON[$i]=0
    done
    info "  ${Y}--no-rust${C}: Rust disabled"
  fi
}

select_dotfiles() {
  local i j ans def
  info ""
  info "  ${B}Dotfiles to apply${C}"
  info "  ENTER = keep default | y/n = toggle one | a = all | x = none"
  for i in "${!DOT_KEYS[@]}"; do
    if [[ ${DOT_DEFAULT[$i]} -eq 1 ]]; then def="y"; else def="n"; fi
    ans="$def"
    if [[ $ASSUME_YES -eq 0 ]]; then
      printf '  [%2d] %-45s [%s]: ' "$((i + 1))" "${DOT_LABELS[$i]}" "$def"
      read -r ans || ans="$def"
      ans="${ans:-$def}"
    fi
    case "$ans" in
      a|A)
        for j in "${!DOT_KEYS[@]}"; do DOT_ON[$j]=1; done
        break
        ;;
      x|X)
        for j in "${!DOT_KEYS[@]}"; do DOT_ON[$j]=0; done
        break
        ;;
    esac
    case "$ans" in
      y|Y|yes|YES) DOT_ON[$i]=1 ;;
      *)           DOT_ON[$i]=0 ;;
    esac
  done
}

print_selection() {
  local i chosen=""
  for i in "${!COMP_KEYS[@]}"; do
    [[ ${COMP_ON[$i]} -eq 1 ]] && chosen="$chosen ${COMP_KEYS[$i]}"
  done
  ok "components:${chosen:- <none>}"

  chosen=""
  for i in "${!DOT_KEYS[@]}"; do
    [[ ${DOT_ON[$i]} -eq 1 ]] && chosen="$chosen ${DOT_KEYS[$i]}"
  done
  ok "dotfiles:${chosen:- <none>}"
}

# ---------------------------------------------------------------------------
# 1. Selection
# ---------------------------------------------------------------------------
step "[1/8] Selecting what to install"
select_components
select_dotfiles
print_selection

# ---------------------------------------------------------------------------
# 2. Preconditions and package manager
# ---------------------------------------------------------------------------
step "[2/8] Detecting OS and package manager"
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
# 3. Repositories and selected packages
# ---------------------------------------------------------------------------
step "[3/8] Preparing repositories and installing selected packages"

# WezTerm is not in Ubuntu's default repos. Add the official apt.fury.io repo
# (idempotently) before the single apt-get update below.
setup_wezterm_repo() {
  [[ "$PM" == "apt" ]] || return 0
  local list=/etc/apt/sources.list.d/wezterm.list
  local key=/usr/share/keyrings/wezterm-fury.gpg
  local tmpkey tmpdearmored

  if [[ -f "$list" ]] && grep -q 'apt.fury.io/wez' "$list" 2>/dev/null; then
    ok "WezTerm apt repo already configured"
    return 0
  fi
  command -v curl >/dev/null 2>&1 || { warn "curl missing — cannot add WezTerm repo"; return 1; }
  command -v gpg >/dev/null 2>&1 || { warn "gpg missing — cannot add WezTerm repo"; return 1; }

  info "  Adding WezTerm apt repository (https://apt.fury.io/wez/) ..."
  tmpkey="$(mktemp)"
  tmpdearmored="$(mktemp)"
  if ! curl -fsSL https://apt.fury.io/wez/gpg.key -o "$tmpkey"; then
    rm -f "$tmpkey" "$tmpdearmored"
    warn "could not download the WezTerm GPG key — skipping repo setup"
    return 1
  fi
  if ! gpg --yes --dearmor -o "$tmpdearmored" "$tmpkey"; then
    rm -f "$tmpkey" "$tmpdearmored"
    warn "could not dearmor the WezTerm GPG key"
    return 1
  fi
  $SUDO install -m 644 "$tmpdearmored" "$key" || { rm -f "$tmpkey" "$tmpdearmored"; warn "could not install $key"; return 1; }
  if ! printf '%s\n' 'deb [signed-by=/usr/share/keyrings/wezterm-fury.gpg] https://apt.fury.io/wez/ * *' | $SUDO tee "$list" >/dev/null; then
    rm -f "$tmpkey" "$tmpdearmored"
    warn "could not write $list"
    return 1
  fi
  rm -f "$tmpkey" "$tmpdearmored"
  ok "WezTerm apt repo added ($list)"
}

if comp_on wezterm; then
  setup_wezterm_repo || warn "WezTerm repo setup failed — apt install wezterm may not work"
fi

if [[ "$PM" == "apt" ]]; then
  info "  refreshing apt package lists ..."
  $SUDO apt-get update -qq || warn "apt-get update failed — continuing with cached lists"
fi

# One entry per component that maps to a package: KEY:COMMAND:PACKAGE
PKG_PAIRS=()
comp_on zsh       && PKG_PAIRS+=("zsh:zsh")
comp_on gitlfs    && PKG_PAIRS+=("git-lfs:git-lfs")
comp_on nvim      && PKG_PAIRS+=("nvim:neovim")
comp_on fish      && PKG_PAIRS+=("fish:fish")
comp_on wezterm   && PKG_PAIRS+=("wezterm:wezterm")
comp_on credential && PKG_PAIRS+=("git-credential-oauth:git-credential-oauth")
comp_on uv        && PKG_PAIRS+=("uv:uv")
comp_on ghostty   && PKG_PAIRS+=("ghostty:ghostty")

if [[ ${#PKG_PAIRS[@]} -gt 0 ]]; then
  for pair in "${PKG_PAIRS[@]}"; do
    cmd="${pair%%:*}"; rest="${pair#*:}"; pkg="${rest#*:}"
    ensure_cmd "$cmd" "$pkg"
  done
fi

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

if comp_on font; then
  if font_installed; then
    ok "JetBrains Mono font already installed — skipping"
  else
    info "  Installing JetBrains Mono font (package: $FONT_PKG) ..."
    install_pkgs "$FONT_PKG" >/dev/null 2>&1 \
      && ok "JetBrains Mono installed" \
      || warn "could not install $FONT_PKG — install a monospace font manually"
  fi
fi

if comp_on wezterm && ! command -v wezterm >/dev/null 2>&1; then
  warn "wezterm is not on PATH. On Ubuntu, make sure the apt.fury.io repo was added, or see https://wezterm.org/install"
fi

# ---------------------------------------------------------------------------
# 4. chezmoi (always required)
# ---------------------------------------------------------------------------
step "[4/8] Installing chezmoi"
if [[ -f "$BOOTSTRAP_DIR/install-chezmoi.sh" ]]; then
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
# 5. Selected dev tools
# ---------------------------------------------------------------------------
step "[5/8] Installing selected developer tools"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"

# fnm + Node + pnpm via corepack
if comp_on fnm; then
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

  if command -v fnm >/dev/null 2>&1; then
    fnm install lts >/dev/null 2>&1 && fnm default lts >/dev/null 2>&1 \
      && ok "Node LTS installed via fnm" \
      || warn "could not install Node LTS — run 'fnm install lts' manually"
    # Put the fnm-managed node on PATH for this shell, then enable pnpm.
    eval "$(fnm env --shell bash 2>/dev/null)" || true
  fi
  if command -v corepack >/dev/null 2>&1; then
    corepack enable 2>/dev/null && corepack prepare pnpm@latest --activate 2>/dev/null \
      && ok "pnpm enabled via corepack" \
      || warn "could not enable pnpm — run 'corepack enable && corepack prepare pnpm@latest --activate'"
  else
    warn "corepack not found — Node must be installed before pnpm can be enabled"
  fi
fi

# powerlevel10k
if comp_on p10k; then
  if [[ -f "$DATA/powerlevel10k/powerlevel10k.zsh" \
     || -f "$DATA/powerlevel10k/powerlevel10k.zsh-theme" \
     || -f /opt/homebrew/share/powerlevel10k/powerlevel10k.zsh \
     || -f /usr/local/share/powerlevel10k/powerlevel10k.zsh ]]; then
    ok "powerlevel10k already installed"
  else
    mkdir -p "$DATA"
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$DATA/powerlevel10k" \
      && ok "powerlevel10k installed" \
      || warn "powerlevel10k install failed"
  fi
fi

# zsh plugins
if comp_on plugins; then
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
fi

# Rust — plain official rustup command (see install-rust.sh)
if comp_on rust; then
  if [[ -f "$BOOTSTRAP_DIR/install-rust.sh" ]]; then
    bash "$BOOTSTRAP_DIR/install-rust.sh" || fail "Rust installation failed"
    export PATH="$HOME/.cargo/bin:$PATH"
  elif command -v cargo >/dev/null 2>&1 && command -v rustc >/dev/null 2>&1; then
    ok "Rust already installed: $(rustc --version)"
  else
    command -v curl >/dev/null 2>&1 || fail "need curl to install Rust"
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh || fail "rustup installation failed"
    export PATH="$HOME/.cargo/bin:$PATH"
    ok "Rust installed: $(rustc --version)"
  fi
fi

# Git LFS initialization
if comp_on gitlfs; then
  git lfs install >/dev/null 2>&1 && ok "git-lfs initialized" || warn "git lfs install failed"
fi

# Git credential helper (PAT caching) — oauth first, libsecret fallback
if comp_on credential && command -v git >/dev/null 2>&1; then
  if command -v git-credential-oauth >/dev/null 2>&1; then
    git config --global credential.helper oauth && ok "credential.helper = oauth"
  elif command -v git-credential-libsecret >/dev/null 2>&1 \
       || [[ -f /usr/lib/git-core/git-credential-libsecret || -f /usr/libexec/git-core/git-credential-libsecret ]]; then
    git config --global credential.helper libsecret && ok "credential.helper = libsecret"
  else
    warn "no credential helper found — install 'git-credential-oauth' (apt) so your PAT is cached"
  fi
fi

# uv (optional)
if comp_on uv; then
  ensure_cmd uv uv
fi

# Ghostty (optional)
if comp_on ghostty; then
  ensure_cmd ghostty ghostty
  command -v ghostty >/dev/null 2>&1 || warn "Ghostty not on PATH — see https://ghostty.org/docs/install"
fi

# ---------------------------------------------------------------------------
# 6. chezmoi config and repo
# ---------------------------------------------------------------------------
step "[6/8] Machine-specific chezmoi config and repo"
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
  read -r -p "  Kit repo URL [https://github.com/YOUR_USER/dotfiles.git]: " REPO_URL
fi
[[ -n "$REPO_URL" ]] || fail "No repo URL provided."

# Prefer the checkout this script lives in when it already contains config/.
# That keeps chezmoi's sourceDir consistent with collect.sh's guard without
# having to modify collect.sh. Otherwise clone into the default kit folder.
if [[ -n "${KIT_DIR:-}" ]]; then
  :   # respect an explicit override
elif [[ -d "$BOOTSTRAP_DIR/config" && -d "$BOOTSTRAP_DIR/.git" ]]; then
  KIT_DIR="$BOOTSTRAP_DIR"
  ok "using existing checkout as kit dir: $KIT_DIR"
else
  KIT_DIR="$HOME/Documents/dotfiles-kit"
fi

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
# 7. Review and apply the SELECTED dotfiles
# ---------------------------------------------------------------------------
step "[7/8] Review and apply selected dotfiles"
TARGETS=()
for i in "${!DOT_KEYS[@]}"; do
  [[ ${DOT_ON[$i]} -eq 1 ]] || continue
  while IFS= read -r target; do
    [[ -n "$target" ]] && TARGETS+=("$target")
  done < <(dot_targets_for "${DOT_KEYS[$i]}")
done

if [[ ${#TARGETS[@]} -eq 0 ]]; then
  warn "no dotfiles selected — skipping chezmoi diff/apply"
else
  info "  Previewing selected changes (chezmoi diff) ..."
  chezmoi diff "${TARGETS[@]}" || true

  if dot_on wezterm || comp_on p10k; then
    info ""
    info "  ${Y}ADOPT${C} — these template paths on Linux (the bootstrap installed them):"
    info "    p10k theme:   $DATA/powerlevel10k/powerlevel10k.zsh-theme"
    info "    autosuggest:  $DATA/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh"
    info "    highlighting: $DATA/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
    info "  ${Y}CHANGE${C} — if your templates still point at /opt/homebrew, edit with:"
    info "    chezmoi edit ~/.zshrc && chezmoi apply"
  fi
  if dot_on warp && [[ "$OS" == "linux" ]]; then
    warn "Warp is macOS-only — ~/.warp/settings.toml will be written but the app cannot run here"
  fi

  info ""
  read -r -p "  Apply selected dotfiles over $HOME now? [y/N] " APPLY
  if [[ "$(lower "$APPLY")" == "y" || "$(lower "$APPLY")" == "yes" ]]; then
    chezmoi apply "${TARGETS[@]}" || fail "chezmoi apply failed"
    ok "selected dotfiles applied"
  else
    warn "skipped 'chezmoi apply' — run it yourself when ready"
  fi
fi

# ---------------------------------------------------------------------------
# 8. Done
# ---------------------------------------------------------------------------
step "[8/8] Done — final manual steps"
info "  1. Open nvim once; LazyVim will bootstrap plugins (needs internet)."
info "  2. Install JetBrains Mono if your terminal did not pick it up."
info "  3. To refresh configs later: chezmoi cd && git pull && chezmoi apply"
info "     (or use ./git-sync.sh in the chezmoi source repo to pull + commit + push)"
