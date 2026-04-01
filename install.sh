#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------------------------
# install.sh — Install the four-engineer review kit
#
# Two modes:
#
#   ./install.sh --user           User-wide: installs to ~/.claude/
#                                 Works in every repo. One-time setup.
#
#   ./install.sh /path/to/repo    Per-repo: installs to <repo>/.claude/
#                                 Only available in that repo.
#
# Options:
#   --force    Overwrite existing files
#   --user     Install to ~/.claude/ (user-wide, all repos)
#
# -------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORCE=false
USER_WIDE=false
TARGET=""

usage() {
  echo "Usage:"
  echo "  $0 --user [--force]              Install user-wide (~/.claude/)"
  echo "  $0 [--force] <target-repo-path>  Install into a specific repo"
  echo ""
  echo "Options:"
  echo "  --user     Install to ~/.claude/ so it works in every repo (recommended)"
  echo "  --force    Overwrite existing files"
  echo ""
  echo "Examples:"
  echo "  $0 --user                    # One-time setup, works everywhere"
  echo "  $0 --user --force            # Update after git pull"
  echo "  $0 ~/repos/my-api           # Single repo only"
  echo ""
  echo "After install, open Claude Code in any repo and run:"
  echo "  /multi-agent-review src/your/target/path"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --user) USER_WIDE=true; shift ;;
    --force) FORCE=true; shift ;;
    -h|--help) usage ;;
    -*) echo "Error: Unknown option: $1"; usage ;;
    *) TARGET="$1"; shift ;;
  esac
done

if [[ "$USER_WIDE" == false && -z "$TARGET" ]]; then
  echo "Error: Provide --user for user-wide install, or a target repo path."
  echo ""
  usage
fi

if [[ "$USER_WIDE" == true && -n "$TARGET" ]]; then
  echo "Error: Cannot use --user and a target path together. Pick one."
  exit 1
fi

copy_file() {
  local src="$1"
  local dst="$2"
  local dst_dir
  dst_dir="$(dirname "$dst")"

  mkdir -p "$dst_dir"

  if [[ -f "$dst" && "$FORCE" != true ]]; then
    echo "  SKIP  $dst (exists, use --force to overwrite)"
    return
  fi

  cp "$src" "$dst"
  echo "  COPY  $dst"
}

# ------------------------------------------------------------------
# User-wide install: ~/.claude/
# ------------------------------------------------------------------
if [[ "$USER_WIDE" == true ]]; then
  DEST="$HOME/.claude"

  echo ""
  echo "Installing four-engineer review kit (user-wide)"
  echo "Target: $DEST"
  echo "================================================="
  echo ""
  echo "This will be available in every repo you open with Claude Code."
  echo ""

  echo "Skill:"
  copy_file \
    "$SCRIPT_DIR/.claude/skills/four-engineer-review/SKILL.md" \
    "$DEST/skills/four-engineer-review/SKILL.md"

  echo ""
  echo "Command:"
  copy_file \
    "$SCRIPT_DIR/.claude/commands/multi-agent-review.md" \
    "$DEST/commands/multi-agent-review.md"

  # Clean up old command name (renamed from /review to /multi-agent-review)
  if [[ -f "$DEST/commands/review.md" ]]; then
    rm "$DEST/commands/review.md"
    echo "  CLEAN  Removed old $DEST/commands/review.md (renamed to multi-agent-review.md)"
  fi

  echo ""
  echo "Done. Open Claude Code in any repo and run:"
  echo ""
  echo "  /multi-agent-review src/your/target/path"
  echo ""
  echo "The review ledger will be created per-repo at .claude/review-ledger.md"
  echo "on first run. Commit it to preserve state across sessions."
  echo ""
  echo "The review process only runs when you explicitly type /multi-agent-review."
  echo "It will never auto-invoke during normal Claude Code usage."
  echo ""

  exit 0
fi

# ------------------------------------------------------------------
# Per-repo install: <target>/.claude/
# ------------------------------------------------------------------
if [[ ! -d "$TARGET" ]]; then
  echo "Error: $TARGET is not a directory."
  exit 1
fi

TARGET="$(cd "$TARGET" && pwd)"

if [[ ! -d "$TARGET/.git" ]]; then
  echo "Warning: $TARGET does not appear to be a git repo (no .git directory)."
  read -p "Continue anyway? [y/N] " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
  fi
fi

echo ""
echo "Installing four-engineer review kit (per-repo)"
echo "Target: $TARGET"
echo "================================================="
echo ""

echo "Skill:"
copy_file \
  "$SCRIPT_DIR/.claude/skills/four-engineer-review/SKILL.md" \
  "$TARGET/.claude/skills/four-engineer-review/SKILL.md"

echo ""
echo "Command:"
copy_file \
  "$SCRIPT_DIR/.claude/commands/multi-agent-review.md" \
  "$TARGET/.claude/commands/multi-agent-review.md"

# Clean up old command name (renamed from /review to /multi-agent-review)
if [[ -f "$TARGET/.claude/commands/review.md" ]]; then
  rm "$TARGET/.claude/commands/review.md"
  echo "  CLEAN  Removed old $TARGET/.claude/commands/review.md (renamed to multi-agent-review.md)"
fi

echo ""
echo "Ledger:"
if [[ -f "$TARGET/.claude/review-ledger.md" ]]; then
  echo "  SKIP  $TARGET/.claude/review-ledger.md (active ledger, never overwritten)"
else
  echo "  INFO  Ledger will be created automatically on first /multi-agent-review run"
fi

echo ""
echo "Done. Open Claude Code in $TARGET and run:"
echo ""
echo "  /multi-agent-review src/your/target/path"
echo ""
echo "The review process only runs when you explicitly type /multi-agent-review."
echo "It will never auto-invoke during normal Claude Code usage."
echo ""
