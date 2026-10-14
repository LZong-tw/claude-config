---
name: parallel-fix
description: Run several independent fixes in parallel, one worktree + subagent each, with vendor isolation. Use when a session spans multiple unrelated fixes.
---
# /parallel-fix

1. `df -h /`; if under 5G free, clean stale worktrees (`git worktree list`, `git worktree prune`) first. Ask before deleting anything not obviously stale.
2. For each fix: create a worktree, run `composer install` inside so `vendor/` is a real dir (verify `ls -la vendor`).
3. Spawn one subagent per fix (in parallel). Each: regression test first, fix, Pest per test path separately, report per-path pass counts.
4. Collect results; one MR per fix (commit split per user preference). Hand each to `/ship` from step 5.
