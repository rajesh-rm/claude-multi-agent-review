#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------------------------
# install.sh — Install Claude Code skills
#
# Modes:
#   ./install.sh --user [--force] [SKILL...]        User-wide (~/.claude/)
#   ./install.sh [--force] <target-repo> [SKILL...]  Per-repo
#   ./install.sh --list                              List available skills
#
# If no SKILL names are given, all skills are installed.
# -------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="$SCRIPT_DIR/skills"
FORCE=false
USER_WIDE=false
LIST=false
TARGET=""
SKILLS=()

usage() {
  echo "Usage:"
  echo "  $0 --user [--force] [SKILL...]        Install user-wide (~/.claude/)"
  echo "  $0 [--force] <target-repo> [SKILL...]  Install into a specific repo"
  echo "  $0 --list                              List available skills"
  echo ""
  echo "If no SKILL names are given, all skills are installed."
  echo ""
  echo "Options:"
  echo "  --user     Install to ~/.claude/ so it works in every repo (recommended)"
  echo "  --force    Overwrite existing files"
  echo "  --list     List available skills and exit"
  echo ""
  echo "Examples:"
  echo "  $0 --user                              # Install all skills, user-wide"
  echo "  $0 --user multi-agent-review           # Install one skill, user-wide"
  echo "  $0 --user --force                      # Update all after git pull"
  echo "  $0 ~/repos/my-api                      # All skills into one repo"
  echo "  $0 ~/repos/my-api multi-agent-review   # One skill into one repo"
  exit 1
}

# Discover all available skills (directories under skills/)
discover_skills() {
  local found=()
  for dir in "$SKILLS_DIR"/*/; do
    [[ -d "$dir" ]] || continue
    local name
    name="$(basename "$dir")"
    if [[ -f "$dir/$name.md" ]]; then
      found+=("$name")
    fi
  done
  echo "${found[@]}"
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --user) USER_WIDE=true; shift ;;
    --force) FORCE=true; shift ;;
    --list) LIST=true; shift ;;
    -h|--help) usage ;;
    -*) echo "Error: Unknown option: $1"; usage ;;
    *)
      if [[ "$USER_WIDE" == false && -z "$TARGET" && -d "$1" ]]; then
        TARGET="$1"
      else
        SKILLS+=("$1")
      fi
      shift
      ;;
  esac
done

# --list: show available skills and exit
if [[ "$LIST" == true ]]; then
  echo "Available skills:"
  echo ""
  for dir in "$SKILLS_DIR"/*/; do
    [[ -d "$dir" ]] || continue
    local_name="$(basename "$dir")"
    if [[ -f "$dir/$local_name.md" ]]; then
      # Extract description from frontmatter
      desc=$(sed -n 's/^description: *//p' "$dir/$local_name.md" | head -1)
      printf "  %-30s %s\n" "$local_name" "$desc"
    fi
  done
  echo ""
  exit 0
fi

if [[ "$USER_WIDE" == false && -z "$TARGET" ]]; then
  echo "Error: Provide --user for user-wide install, or a target repo path."
  echo ""
  usage
fi

if [[ "$USER_WIDE" == true && -n "$TARGET" ]]; then
  echo "Error: Cannot use --user and a target path together. Pick one."
  exit 1
fi

# If no specific skills requested, install all
if [[ ${#SKILLS[@]} -eq 0 ]]; then
  IFS=' ' read -ra SKILLS <<< "$(discover_skills)"
fi

# Validate requested skills exist
for skill in "${SKILLS[@]}"; do
  if [[ ! -f "$SKILLS_DIR/$skill/$skill.md" ]]; then
    echo "Error: Skill '$skill' not found. Run '$0 --list' to see available skills."
    exit 1
  fi
done

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

cleanup_old_artifacts() {
  local dest="$1"

  # Remove artifacts from previous versions (can be removed in a future release)
  if [[ -f "$dest/commands/review.md" ]]; then
    rm "$dest/commands/review.md"
    echo "  CLEAN  Removed old $dest/commands/review.md"
  fi
  if [[ -d "$dest/skills/four-engineer-review" ]]; then
    rm -rf "$dest/skills/four-engineer-review"
    echo "  CLEAN  Removed old $dest/skills/four-engineer-review/"
  fi
}

# ------------------------------------------------------------------
# User-wide install: ~/.claude/
# ------------------------------------------------------------------
if [[ "$USER_WIDE" == true ]]; then
  DEST="$HOME/.claude"

  echo ""
  echo "Installing skills (user-wide)"
  echo "Target: $DEST"
  echo "================================================="
  echo ""

  for skill in "${SKILLS[@]}"; do
    echo "[$skill]"
    copy_file \
      "$SKILLS_DIR/$skill/$skill.md" \
      "$DEST/commands/$skill.md"
    echo ""
  done

  cleanup_old_artifacts "$DEST"

  echo "Done. Installed ${#SKILLS[@]} skill(s). Run /skills in Claude Code to verify."
  echo ""
  echo "The review process only runs when you explicitly type the command."
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
echo "Installing skills (per-repo)"
echo "Target: $TARGET"
echo "================================================="
echo ""

for skill in "${SKILLS[@]}"; do
  echo "[$skill]"
  copy_file \
    "$SKILLS_DIR/$skill/$skill.md" \
    "$TARGET/.claude/commands/$skill.md"
  echo ""
done

cleanup_old_artifacts "$TARGET/.claude"

echo "Done. Installed ${#SKILLS[@]} skill(s). Run /skills in Claude Code to verify."
echo ""
