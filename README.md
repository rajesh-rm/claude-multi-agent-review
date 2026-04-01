# Four-Engineer Code Review for Claude Code

A structured code review system that uses four opinionated AI personas as a voting quorum. Every proposed change must pass a 3-of-4 vote. The process converges automatically and never runs unless you explicitly ask for it.

## What It Does

You type `/review src/some/path` in Claude Code. The orchestrator:

1. **Analyses** the target and classifies findings by severity (Tier 1: bugs/safety → Tier 2: structure → Tier 3: polish)
2. **Proposes** 3–5 concrete changes for the highest-priority tier
3. **Votes** by spawning four isolated Tasks, each with one competing concern:
   - **Simplifier** — structural, cognitive, and operational complexity reduction
   - **Guardian** — reliability, testability, auditability, compliance
   - **Scaler** — scalability, extensibility, growth readiness
   - **Shipper** — delivery speed, practical user value
4. **Fixes** only what got 3+ yes votes, locks decisions, records dissent as documented trade-offs

Repeat rounds until termination (zero-pass round, diminishing returns, 7-round cap, or you say stop).

## Will Claude Use This Automatically?

No. The system is designed to never auto-invoke:

- The skill has `disable-model-invocation: true` in its frontmatter, which prevents Claude from loading or using it unless you explicitly type the command.
- The command only fires when you type `/review`.
- There are no agent files in `.claude/agents/`. Agent files would auto-delegate based on description matching, so this kit deliberately avoids them. Instead, the four personas are defined as inline prompts inside the skill and spawned as isolated Tasks only when the `/review` command runs.

During normal Claude Code usage — coding, debugging, chatting — this system is completely inert.

## Install

### User-wide (recommended — one-time, works in every repo)

```bash
git clone https://github.com/YOUR_ORG/four-engineer-review.git
cd four-engineer-review
chmod +x install.sh
./install.sh --user
```

This copies the skill and command to `~/.claude/`, which Claude Code loads in every repo you open. Each teammate runs this once and they're set.

The review ledger is still created per-repo (at `.claude/review-ledger.md` in whatever repo you run `/review` in), since each codebase has its own review state.

### Per-repo (alternative — if you only want it in specific repos)

```bash
./install.sh /path/to/your/target/repo
```

This copies the files into that repo's `.claude/` directory only. Useful if you want to check the skill into version control alongside the repo, or if some repos should not have the review system.

### What gets copied

```
~/.claude/                         # with --user
  ├── skills/
  │   └── four-engineer-review/
  │       └── SKILL.md             # Process rules + four persona prompts
  └── commands/
      └── review.md                # /review entry point
```

Two files. No agents, no hooks, no MCP servers, no background processes.

The install script will not overwrite existing files unless you pass `--force`. It will never overwrite an active review ledger.

## Use

Open Claude Code in the target repo and type:

```
/review src/etl
```

Replace `src/etl` with whatever path or module you want reviewed. The orchestrator handles everything from there.

After a round completes, you are asked whether to continue. State is tracked in `.claude/review-ledger.md` in the target repo. Commit this file so the process can resume across sessions.

## Update

When you push changes to this repo (improved persona prompts, updated convergence rules, new anti-loop patterns), teammates pick up updates by pulling and re-running install:

```bash
cd four-engineer-review
git pull
./install.sh --user --force
```

This overwrites the skill and command in `~/.claude/` but never touches any active ledger in any repo. All review state is preserved.

For per-repo installs, same idea:

```bash
./install.sh --force /path/to/target/repo
```

### Version with Git tags

Tag releases so your team knows when an update matters:

```bash
git tag -a v1.1.0 -m "Improved Guardian prompt, added Tier 1 escalation rule"
git push origin v1.1.0
```

## What Is in Each File

**`.claude/skills/four-engineer-review/SKILL.md`** — The complete process document. Contains:
- All four persona definitions with their full prompts (Simplifier, Guardian, Scaler, Shipper)
- Round structure (Analyse → Propose → Vote → Fix)
- Tier classification rules (Tier 1 before Tier 2 before Tier 3)
- Convergence rules (decision locking, two-strike parking, scope narrowing)
- Anti-loop safeguards (oscillation detection, test spiral, scope creep, refactor treadmill)
- Termination conditions (zero-pass, diminishing returns, 7-round cap)
- Ledger template (created automatically on first run)
- Identity drift prevention rules

**`.claude/commands/review.md`** — The `/review` slash command. This is the entry point that reads the skill and executes one round. It spawns each persona as a separate Task with its own context window, tallies votes, applies changes, and updates the ledger.

**`.claude/review-ledger.md`** (created at runtime) — The live state tracker. Records applied changes (locked), deferred backlog, active debt register, round summaries, and anti-loop detections. Commit this to your repo to preserve state across sessions.

## Convergence Guarantees

The process cannot loop or run forever:

- **Tier ordering** — Tier 1 before Tier 2 before Tier 3
- **Decision locking** — applied changes are final (append-only, like ADRs)
- **Two-strike rule** — a failed proposal gets one revision, then it is parked permanently
- **Scope narrowing** — each round's scope is equal to or smaller than the previous round
- **Diminishing returns** — two consecutive low-impact rounds trigger termination
- **Hard cap** — maximum 7 rounds per target
- **Anti-loop detection** — Simplifier-Scaler oscillation, Guardian test spiral, Shipper scope creep, refactor treadmill

## Customisation

Edit the SKILL.md in this repo, then re-install with `--force`.

- **Change persona behaviour** — edit the prompt text inside the relevant persona section
- **Change the voting model** — adjust the "model:" field if using subagent files in the future, or instruct the orchestrator to use a specific model for Tasks
- **Add a fifth persona** — add a new persona section in SKILL.md, update the command to spawn five Tasks, and change the quorum to 4-of-5
- **Adjust convergence** — change the round cap, strike limit, or tier definitions in the skill

## Why Not a Claude Code Plugin?

Claude Code plugins are the standard distribution mechanism, but they currently have a bug where `disable-model-invocation: true` is ignored for plugin-defined skills (see [anthropics/claude-code#22345](https://github.com/anthropics/claude-code/issues/22345)). This means a plugin version of this kit would auto-load into context during every Claude Code session, even when nobody asked for a review.

Additionally, agent files inside plugins auto-delegate based on description matching, with no way to disable this.

The `.claude/` directory approach used here gives you `disable-model-invocation: true` that actually works, no agent auto-delegation, and the same functionality. When Anthropic fixes the plugin bug, this kit can be converted to a plugin with minimal changes.

## Repo Structure

```
four-engineer-review/
├── .claude/
│   ├── skills/
│   │   └── four-engineer-review/
│   │       └── SKILL.md        # Process rules + persona prompts (the brain)
│   └── commands/
│       └── review.md           # /review entry point (the trigger)
├── install.sh                  # Copies .claude/ into target repos
└── README.md                   # This file
```
