# Claude Code Skills

A collection of skills and tools for [Claude Code](https://claude.com/claude-code). Each skill is a self-contained slash command that you install once and use in any repo.

## Available Skills

| Skill | Description |
|-------|-------------|
| [multi-agent-review](skills/multi-agent-review/README.md) | Four-persona code review with quorum voting and automatic convergence |

## Install

### All skills, user-wide (recommended)

```bash
git clone https://github.com/rajesh-rm/claude-multi-agent-review.git
cd claude-multi-agent-review
chmod +x install.sh
./install.sh --user
```

This copies all skill commands to `~/.claude/commands/`, making them available in every repo.

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
2. Add `skills/<skill-name>/<skill-name>.md` — the command file with frontmatter (`description`, `allowed-tools`, `disable-model-invocation: true`)
3. Add `skills/<skill-name>/README.md` — usage docs
4. Update the skills table in this README
5. Commit. The install script auto-discovers new skills — no script changes needed.

## Repo Structure

```
├── skills/                         # distributable skills (NOT auto-loaded by Claude Code)
│   └── multi-agent-review/
│       ├── multi-agent-review.md   # /multi-agent-review command
│       └── README.md
├── install.sh                      # unified installer
├── .claude/                        # dev-only settings
│   └── settings.local.json
├── .gitignore
├── LICENSE
└── README.md                       # this file
```

Skills live under `skills/`, not `.claude/`, so they are never loaded into the dev session when working on this repo.
