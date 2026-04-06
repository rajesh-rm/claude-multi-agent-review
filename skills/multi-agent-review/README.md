# multi-agent-review

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

## Usage

Open Claude Code in the target repo and type:

```
/multi-agent-review src/etl
```

Replace `src/etl` with whatever path or module you want reviewed. The orchestrator handles everything from there.

After a round completes, you are asked whether to continue. State is tracked in `.claude/review-ledger.md` in the target repo. Commit this file so the process can resume across sessions.

## Will Claude Use This Automatically?

No. The command has `disable-model-invocation: true` in its frontmatter. It only runs when you explicitly type `/multi-agent-review`. During normal Claude Code usage, it is completely inert.

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

Edit `multi-agent-review.md` in this directory, then re-install with `--force`.

- **Change persona behaviour** — edit the prompt text inside the relevant persona section
- **Add a fifth persona** — add a new persona section, update the orchestrator to spawn five Tasks, change the quorum to 4-of-5
- **Adjust convergence** — change the round cap, strike limit, or tier definitions
