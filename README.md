# Multi-Agent Code Review for Claude Code

A structured code review system that uses four opinionated AI personas as a voting quorum. Every proposed change must pass a 3-of-4 vote. The process converges automatically and never runs unless you explicitly ask for it.

## What It Does

You type `/multi-agent-review src/some/path` in Claude Code. The orchestrator:

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

No. The command has `disable-model-invocation: true` in its frontmatter, which prevents Claude from loading or using it unless you explicitly type `/multi-agent-review`.

During normal Claude Code usage — coding, debugging, chatting — this system is completely inert.

## Install

### User-wide (recommended — one-time, works in every repo)

```bash
git clone https://github.com/rajesh-rm/claude-multi-agent-review.git
cd claude-multi-agent-review
chmod +x install.sh
./install.sh --user
```

This copies the command to `~/.claude/commands/`, which Claude Code loads in every repo you open. Each teammate runs this once and they're set.

The review ledger is still created per-repo (at `.claude/review-ledger.md` in whatever repo you run `/multi-agent-review` in), since each codebase has its own review state.

### Per-repo (alternative — if you only want it in specific repos)

```bash
./install.sh /path/to/your/target/repo
```

This copies the command into that repo's `.claude/commands/` directory only.

### What gets copied

```
~/.claude/                         # with --user
  └── commands/
      └── multi-agent-review.md    # /multi-agent-review — complete process + personas
```

One file. No agents, no hooks, no MCP servers, no background processes.

The install script will not overwrite existing files unless you pass `--force`. It will never overwrite an active review ledger.

## Use

Open Claude Code in the target repo and type:

```
/multi-agent-review src/etl
```

Replace `src/etl` with whatever path or module you want reviewed. The orchestrator handles everything from there.

After a round completes, you are asked whether to continue. State is tracked in `.claude/review-ledger.md` in the target repo. Commit this file so the process can resume across sessions.

## Update

When you push changes to this repo (improved persona prompts, updated convergence rules, new anti-loop patterns), teammates pick up updates by pulling and re-running install:

```bash
cd claude-multi-agent-review
git pull
./install.sh --user --force
```

This overwrites the command in `~/.claude/` but never touches any active ledger in any repo. All review state is preserved.

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

## What Is in the Command File

**`.claude/commands/multi-agent-review.md`** — The complete `/multi-agent-review` slash command. Contains:
- All four persona definitions with their full prompts (Simplifier, Guardian, Scaler, Shipper)
- Round structure (Analyse → Propose → Vote → Fix)
- Tier classification rules (Tier 1 before Tier 2 before Tier 3)
- Convergence rules (decision locking, two-strike parking, scope narrowing)
- Anti-loop safeguards (oscillation detection, test spiral, scope creep, refactor treadmill)
- Termination conditions (zero-pass, diminishing returns, 7-round cap)
- Ledger template (created automatically on first run)
- Identity drift prevention rules

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

Edit the command file in this repo, then re-install with `--force`.

- **Change persona behaviour** — edit the prompt text inside the relevant persona section
- **Add a fifth persona** — add a new persona section, update the orchestrator to spawn five Tasks, and change the quorum to 4-of-5
- **Adjust convergence** — change the round cap, strike limit, or tier definitions

## Repo Structure

```
claude-multi-agent-review/
├── .claude/
│   └── commands/
│       └── multi-agent-review.md  # /multi-agent-review — complete process + personas
├── install.sh                     # Copies command into target locations
└── README.md                      # This file
```
