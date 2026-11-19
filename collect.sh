#!/usr/bin/env bash
#
# collect.sh — (re-)import your dotfiles into chezmoi from $HOME.
#
# Safe by design:
#   * files marked "tmpl" are skipped once the .tmpl file exists, so your
#     hand-written macOS/Linux guards are never destroyed by a normal run.
#   * all other files are refreshed from $HOME every run.
#   * .chezmoiignore is regenerated from a fixed list on every run.
#
# Usage:
#   ./collect.sh              # safe recollect
#   ./collect.sh --dry-run    # preview only, change nothing
#   ./collect.sh --force      # re-add templates too (backs them up to *.bak.TIMESTAMP)
#
# Collected data is always written to ./config inside this repo (the kit folder).
# This script does NOT commit or push. After running it, from the kit folder:
#   ./git-sync.sh -m "update collected dotfiles"

set -euo pipefail

DRY_RUN=0
FORCE=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --force)   FORCE=1 ;;
    -h|--help)
      sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "Unknown option: $arg" >&2
      exit 2
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Manifest: MODE|HOME_PATH|CHEZMOI_SOURCE_NAME
#   raw  = copy verbatim, refresh every run
#   tmpl = chezmoi template, skip if already templated (unless --force)
#   dir  = directory, refresh every run
# ---------------------------------------------------------------------------
ENTRIES=(
  "tmpl|$HOME/.zshrc|dot_zshrc"
  "tmpl|$HOME/.zprofile|dot_zprofile"
  "raw|$HOME/.p10k.zsh|dot_p10k.zsh"
  "tmpl|$HOME/.wezterm.lua|dot_wezterm.lua"
  "tmpl|$HOME/.gitconfig|dot_gitconfig"
  "dir|$HOME/.config/nvim|dot_config/nvim"
  "raw|$HOME/.gitignore_global|dot_gitignore_global"
  "raw|$HOME/.hgignore_global|dot_hgignore_global"
  "raw|$HOME/.stCommitMsg|dot_stCommitMsg"
  "raw|$HOME/.config/ghostty/config|dot_config/ghostty/config"
  "raw|$HOME/.warp/settings.toml|dot_warp/settings.toml"
  "dir|$HOME/.config/fish/conf.d|dot_config/fish/conf.d"
)

# Patterns written to .chezmoiignore in the chezmoi source directory.
# Paths are TARGET paths (relative to $HOME), not chezmoi source names.
read -r -d '' IGNORE_CONTENT <<'EOF' || true
# --- Secrets: never sync -----------------------------------------------------
.ssh/**
.gnupg/**
.gnupg_pre_2.1/**
.id
.username
.helper
.emulator_console_auth_token
.claude.json
.config/github-copilot/**
.config/opencode/**
.wakatime/**

# --- Histories and local state ----------------------------------------------
.zsh_history*
.bash_history
.python_history
.lesshst
.viminfo
.zsh_sessions/**
.wget-hsts

# --- Caches / tool data (guards in case broader dirs are added later) -------
.cache/**
.local/share/**
.android/**
.codeium/**
.gradle/**
.pub-cache/**
.vscode/**
.cursor/**
.trae/**
.bun/**
.cargo/**
.npm/**
.yarn/**
.gem/**
.gemini/**
.spicetify/**

# --- Internal helper files (kept in the repo, not applied to $HOME) ----------
scripts/**

# --- Backups, leftovers, macOS-only junk ------------------------------------
*.backup-*
*.bak
.DS_Store
.CFUserTextEncoding
.Trash/**
.zshrc.pre-oh-my-zsh
.shell.pre-oh-my-zsh
.gitflow_export

# --- Nested data inside directories we DO manage ----------------------------
.config/nvim/.git
.config/zed/conversations/**
.config/zed/embeddings/**
.config/zed/.tmp*
.config/zed/settings_backup.json
EOF

# A starter scaffold prepended to newly-created templates. It is a Go-template
# comment, so it renders to nothing and is valid in shell, Lua, and gitconfig.
read -r -d '' TEMPLATE_SCAFFOLD <<'EOF' || true
{{- /*
================================================================================
chezmoi template scaffold — EDIT ME
================================================================================
Wrap machine-specific lines with OS guards, for example:

    {{- if eq .chezmoi.os "darwin" }}
    source /opt/homebrew/share/powerlevel10k/powerlevel10k.zsh
    {{- else if eq .chezmoi.os "linux" }}
    source "${XDG_DATA_HOME:-$HOME/.local/share}/powerlevel10k/powerlevel10k.zsh"
    {{- end }}

Portable helpers you can use anywhere in this file:
    {{ .chezmoi.homeDir }}   -> /Users/<user> on macOS, /home/<user> on Linux
    {{ .chezmoi.os }}        -> "darwin" | "linux"
    {{ .email }}             -> value from chezmoi.toml

Known macOS-only lines in this file (check each one):
    /opt/homebrew/...          (Homebrew paths)
    $HOME/Library/...          (Android SDK, pnpm, JetBrains Toolbox)
    /Users/<user>/...          (hardcoded absolute paths)
    DYLD_LIBRARY_PATH          (macOS only)
    opendiff / Sourcetree      (macOS only)
    macos_window_background_blur (WezTerm, use wezterm.target_triple guard)
================================================================================
*/ -}}
EOF

# ---------------------------------------------------------------------------
# Preconditions
# ---------------------------------------------------------------------------
if ! command -v chezmoi >/dev/null 2>&1; then
  echo "ERROR: chezmoi is not installed. Install it first:" >&2
  echo "  sh -c \"\$(curl -fsSL https://get.chezmoi.io)\"" >&2
  exit 1
fi

if ! SRC="$(chezmoi source-path 2>/dev/null)"; then
  echo "ERROR: chezmoi could not report its source directory." >&2
  echo "Create the folder and point chezmoi at it in ~/.config/chezmoi/chezmoi.toml:" >&2
  echo "  sourceDir = \"$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/config\"" >&2
  exit 1
fi

# Collected data must ALWAYS live in the kit repo's config/ folder.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXPECTED_SRC="$SCRIPT_DIR/config"
SRC_REAL="$(cd "$SRC" 2>/dev/null && pwd -P || printf '%s' "$SRC")"
EXPECTED_REAL="$(cd "$EXPECTED_SRC" 2>/dev/null && pwd -P || printf '%s' "$EXPECTED_SRC")"
if [[ "$SRC_REAL" != "$EXPECTED_REAL" ]]; then
  echo "ERROR: chezmoi source dir is '$SRC' but must be '$EXPECTED_SRC'." >&2
  echo "Add this to ~/.config/chezmoi/chezmoi.toml, then re-run:" >&2
  echo "  sourceDir = \"$EXPECTED_SRC\"" >&2
  exit 1
fi

C='\033[0m'; G='\033[0;32m'; Y='\033[0;33m'; B='\033[0;34m'; R='\033[0;31m'
info() { printf '%b\n' "$*"; }
run() {
  if [[ $DRY_RUN -eq 1 ]]; then
    info "  ${Y}[dry-run]${C} $*"
    return 0
  fi
  info "  ${B}\$${C} $*"
  "$@"
}

info "${B}chezmoi source:${C} $SRC"
info ""

# ---------------------------------------------------------------------------
# 1. Write .chezmoiignore first so `chezmoi add` skips ignored sub-paths
#    (e.g. nvim's .git).
# ---------------------------------------------------------------------------
info "${B}[1/3]${C} Writing .chezmoiignore"
if [[ $DRY_RUN -eq 1 ]]; then
  info "  ${Y}[dry-run]${C} would write $SRC/.chezmoiignore ($(printf '%s\n' "$IGNORE_CONTENT" | wc -l | tr -d ' ') lines)"
else
  printf '%s\n' "$IGNORE_CONTENT" > "$SRC/.chezmoiignore"
  info "  ${G}OK${C} $SRC/.chezmoiignore"
fi
info ""

# ---------------------------------------------------------------------------
# 2. Add files
# ---------------------------------------------------------------------------
info "${B}[2/3]${C} Collecting files"
added=0; skipped=0; failed=0

for entry in "${ENTRIES[@]}"; do
  IFS='|' read -r mode path name <<< "$entry"

  if [[ ! -e "$path" ]]; then
    info "  ${Y}MISSING${C} $path (skipped)"
    skipped=$((skipped + 1))
    continue
  fi

  if [[ "$mode" == "tmpl" ]]; then
    tmpl_file="$SRC/${name}.tmpl"
    # chezmoi may use an "empty_" prefix for zero-byte files.
    empty_tmpl_file="$SRC/empty_${name}.tmpl"
    if [[ -f "$tmpl_file" || -f "$empty_tmpl_file" ]] && [[ $FORCE -eq 0 ]]; then
      info "  ${Y}SKIP${C}     $path  (template exists — use --force to refresh)"
      skipped=$((skipped + 1))
      continue
    fi

    if [[ $FORCE -eq 1 && ( -f "$tmpl_file" || -f "$empty_tmpl_file" ) ]]; then
      old_template="$tmpl_file"
      [[ -f "$old_template" ]] || old_template="$empty_tmpl_file"
      backup="${old_template}.bak.$(date +%Y%m%d%H%M%S)"
      info "  ${Y}BACKUP${C}   $old_template -> $backup"
      [[ $DRY_RUN -eq 1 ]] || cp "$old_template" "$backup"
    fi

    # Remove any previous source (plain or template) so chezmoi can re-add cleanly.
    [[ $DRY_RUN -eq 1 ]] || rm -f "$SRC/$name" "$SRC/empty_$name" \
      "$SRC/${name}.tmpl" "$SRC/empty_${name}.tmpl"

    info "  ${G}TMPL${C}     $path -> ${name}.tmpl"
    run chezmoi add --template "$path"

    target="${tmpl_file}"
    [[ -f "$target" ]] || target="${empty_tmpl_file}"
    if [[ $DRY_RUN -eq 0 && -f "$target" ]]; then
      {
        printf '%s\n' "$TEMPLATE_SCAFFOLD"
        cat "$target"
      } > "${target}.new"
      mv "${target}.new" "$target"
      info "  ${G}SCAFFOLD${C} added to $target"
    fi
    added=$((added + 1))
    continue
  fi

  # raw / dir: always refresh from $HOME
  info "  ${G}ADD${C}      $path -> $name"
  if run chezmoi add "$path"; then
    added=$((added + 1))
  else
    info "  ${R}FAIL${C}    $path"
    failed=$((failed + 1))
  fi
done

info ""
info "  ${B}Result:${C} $added added/refreshed, $skipped skipped, $failed failed"

# ---------------------------------------------------------------------------
# 3. Keep a copy of this script inside the source repo so it syncs to Linux
# ---------------------------------------------------------------------------
info ""
info "${B}[3/3]${C} Copying collect.sh into the chezmoi source repo"
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
if [[ $DRY_RUN -eq 1 ]]; then
  info "  ${Y}[dry-run]${C} would copy $SELF -> $SRC/scripts/collect.sh"
else
  mkdir -p "$SRC/scripts"
  cp "$SELF" "$SRC/scripts/collect.sh"
  chmod +x "$SRC/scripts/collect.sh"
  info "  ${G}OK${C} $SRC/scripts/collect.sh"
fi

info ""
info "${B}Done.${C} Next steps:"
info "  chezmoi diff"
info "  chezmoi apply"
info "  ./git-sync.sh -m 'update collected dotfiles'   # from the kit folder (one repo)"
info "  ${Y}Remember:${C} the seeded *.tmpl files are scaffolding — fill in the OS guards manually."

[[ $failed -eq 0 ]]
