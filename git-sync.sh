#!/usr/bin/env bash
#
# git-sync.sh — commit local changes, pull with rebase, and push. HTTPS only.
#
# Usage:
#   ./git-sync.sh [repo-path] [options]
#
# Options:
#   -m, --message TEXT   commit message (default: "auto: YYYY-MM-DD HH:MM:SS")
#       --dry-run        show what would happen, change nothing
#   -h, --help           show this help
#
# Examples:
#   ./git-sync.sh                         # sync the current directory's repo
#   ./git-sync.sh ~/Documents/dotfiles-kit
#   ./git-sync.sh -m "update zsh config"
#
# Safety: it commits first, then pulls with --rebase, never force-pushes, and
# aborts with a clear message if there is a conflict or no remote configured.

set -euo pipefail

C='\033[0m'; G='\033[0;32m'; Y='\033[0;33m'; B='\033[0;34m'; R='\033[0;31m'
info() { printf '%b\n' "$*"; }
ok()   { info "  ${G}OK${C} $*"; }
warn() { info "  ${Y}WARN${C} $*"; }
fail() { info "  ${R}ERROR${C} $*" >&2; exit 1; }

usage() { sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; }

REPO_PATH=""
MESSAGE=""
DRY_RUN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    -m|--message) MESSAGE="${2:?--message needs text}"; shift 2 ;;
    --dry-run)    DRY_RUN=1; shift ;;
    -h|--help)    usage; exit 0 ;;
    -*)           fail "unknown option: $1 (try --help)" ;;
    *)
      if [[ -z "$REPO_PATH" ]]; then REPO_PATH="$1"; shift
      else fail "too many arguments"; fi
      ;;
  esac
done

REPO_PATH="${REPO_PATH:-.}"
[[ -d "$REPO_PATH" ]] || fail "not a directory: $REPO_PATH"
cd "$REPO_PATH"

# 1. Verify this is a git repo
git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || fail "not a git repository: $(pwd)  (run 'git init' first)"

# 2. Verify a remote exists
git remote get-url origin >/dev/null 2>&1 \
  || fail "no 'origin' remote configured (run 'git remote add origin <https-url>')"
REMOTE_URL="$(git remote get-url origin)"
[[ "$REMOTE_URL" == http* ]] || warn "origin is not an HTTPS URL: $REMOTE_URL"

# symbolic-ref works even before the first commit (unlike rev-parse HEAD).
BRANCH="$(git symbolic-ref --short HEAD 2>/dev/null || true)"
[[ -n "$BRANCH" ]] || fail "detached HEAD — check out a branch first"
info "${B}Repo:${C} $(pwd)  ${B}Branch:${C} $BRANCH"
info "  Remote: $REMOTE_URL"

run() {
  if [[ $DRY_RUN -eq 1 ]]; then
    info "  ${Y}[dry-run]${C} $*"
    return 0
  fi
  info "  ${B}\$${C} $*"
  "$@"
}

# 3. Stage and commit local changes FIRST, so pull --rebase has a clean tree.
if [[ $DRY_RUN -eq 1 ]]; then
  if [[ -n "$(git status --porcelain)" ]]; then
    info "  ${Y}[dry-run]${C} would stage and commit local changes"
  else
    info "  ${Y}Nothing to commit${C} — working tree is clean"
  fi
else
  run git add -A
  if git diff --cached --quiet; then
    info "  ${Y}Nothing to commit${C} — working tree is clean"
  else
    [[ -n "$MESSAGE" ]] || MESSAGE="auto: $(date '+%Y-%m-%d %H:%M:%S')"
    run git commit -m "$MESSAGE" || fail "commit failed"
    ok "committed changes"
  fi
fi

# 4. Pull with rebase (skip if the remote branch does not exist yet)
if git ls-remote --exit-code --heads origin "$BRANCH" >/dev/null 2>&1; then
  if ! run git pull --rebase origin "$BRANCH"; then
    [[ $DRY_RUN -eq 1 ]] || git rebase --abort >/dev/null 2>&1 || true
    fail "pull/rebase failed — resolve conflicts manually, then re-run"
  fi
  ok "pulled latest changes"
else
  info "  Remote branch '$BRANCH' does not exist yet — skipping pull"
fi

# 5. Push (set upstream the first time)
if git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
  run git push || fail "push failed — check your HTTPS credentials/PAT"
else
  run git push -u origin "$BRANCH" || fail "push failed — check your HTTPS credentials/PAT"
fi
ok "sync complete"
