---
name: survey
description: Inventory current repo/work state (worktrees, branches, PRs, gate files, running agents) as a table, then stop.
---
Read-only. Collect and present as tables, then stop and wait:
1. `git worktree list` — mark which are clean/dirty/locked.
2. Local branches with upstream state (`git branch -vv`), merged-but-not-deleted ones flagged.
3. Open PRs: `gh pr list --json number,title,headRefName,mergeable,statusCheckRollup` (single call, no polling).
4. Reasoning-gate verdict/allowlist files and which branch they belong to.
5. Running claude / codex / pi processes with PID, parent, start time, working dir.
