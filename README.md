# Claude Code Skills

A collection of skills and tools for [Claude Code](https://claude.com/claude-code). Each skill is a self-contained slash command that you install once and use in any repo.

## Available Skills

| Skill | Description |
|-------|-------------|
| [multi-agent-review](skills/multi-agent-review/README.md) | Four-persona code review with quorum voting and automatic convergence |
| [sast-scan](skills/sast-scan/README.md) | SAST analysis with local SonarQube — setup, scan, fix, and converge to coverage target |

## Install

### All skills, user-wide (recommended)

```bash
git clone https://github.com/rajesh-rm/claude-multi-agent-review.git
cd claude-multi-agent-review
chmod +x install.sh
./install.sh --user
```

This installs all skills to `~/.claude/skills/`, making them available in every repo.

### A specific skill

```bash
./install.sh --user multi-agent-review
```

### Into a specific repo

```bash
./install.sh /path/to/your/repo
./install.sh /path/to/your/repo multi-agent-review   # just one skill
```

### List available skills

```bash
./install.sh --list
```

## Update

```bash
git pull
./install.sh --user --force
```

### Version with Git tags

```bash
git tag -a v2.0.0 -m "Restructured as multi-skill collection"
git push origin v2.0.0
```

## Adding a New Skill

1. Create `skills/<skill-name>/`
2. Add `skills/<skill-name>/<skill-name>.md` — the skill file with frontmatter (`name`, `description`, `allowed-tools` (space-separated), `disable-model-invocation: true`). Installed as `SKILL.md`.
3. Add `skills/<skill-name>/README.md` — usage docs
4. Supporting files (helper scripts, etc.) go in `skills/<skill-name>/lib/` — reference them via `${CLAUDE_SKILL_DIR}/lib/` in the skill file
5. Update the skills table in this README
6. Commit. The install script auto-discovers new skills — no script changes needed.

## Repo Structure

```
├── skills/                         # source skills (NOT auto-loaded during development)
│   ├── multi-agent-review/
│   │   ├── multi-agent-review.md   # → ~/.claude/skills/multi-agent-review/SKILL.md
│   │   └── README.md
│   └── sast-scan/
│       ├── sast-scan.md            # → ~/.claude/skills/sast-scan/SKILL.md
│       ├── lib/
│       │   └── sast-helpers.sh     # → ~/.claude/skills/sast-scan/lib/sast-helpers.sh
│       └── README.md
├── install.sh                      # unified installer
├── .claude/                        # dev-only settings
│   └── settings.local.json
├── .gitignore
├── LICENSE
└── README.md                       # this file
```

After `./install.sh --user`, the installed layout is:

```
~/.claude/skills/
├── multi-agent-review/
│   ├── SKILL.md
│   └── README.md
└── sast-scan/
    ├── SKILL.md
    ├── lib/
    │   └── sast-helpers.sh
    └── README.md
```

Skills live under `skills/` in the repo (not `.claude/`), so they are never loaded during development.
