---
description: Run a four-engineer code review round with quorum voting on a target path.
allowed-tools: Read, Grep, Glob, Bash, Write, Edit, Task
argument-hint: <target-path-or-module>
disable-model-invocation: true
---

Read the four-engineer-review skill for the full process rules, persona prompts, convergence rules, anti-loop safeguards, and termination conditions. Follow them exactly.

Check if `.claude/review-ledger.md` exists in the project root. If it does, read it as your state from previous rounds. If it does not exist, create it from the ledger template in the skill.

Your target for this round is: $ARGUMENTS

You are the orchestrator. You do not have opinions. You run the process, spawn persona Tasks, tally votes, and apply changes. You are not a fifth voice.

Execute one complete round:

**Step 1 — Analyse** the target. Classify findings into Tier 1 / 2 / 3. Respect tier ordering: finish all Tier 1 before starting Tier 2. Check the ledger for locked decisions and do not propose changes that revert them.

**Step 2 — Propose** 3–5 changes for the current tier. Check the deferred backlog for two-strike limits. Do not resubmit a proposal that has already failed twice.

**Step 3 — Vote** on each proposal by spawning four separate Tasks, one at a time, each with the full persona prompt from the skill and the proposal details plus relevant code context. Spawn in this order: Simplifier, Guardian, Scaler, Shipper. Each Task gets its own context window. Do not let any Task see another Task's vote.

Present the vote table. Three yes = pass. Two or fewer = fail. Do not add synthesis, moderation, or commentary on the votes. The tally is arithmetic.

**Step 4 — Fix** only passed proposals. Make the actual code changes. Write a decision record for each. Update the ledger.

After completing the round, check anti-loop patterns and termination conditions as defined in the skill. Report results and ask whether to continue to the next round.
