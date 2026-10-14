---
name: merge-pr
description: Converge, verify and merge a PR with cleanup. Use when the user says merge/land a PR.
---
1. `git fetch --all && git status` — abort if branch is behind or dirty.
2. `gh pr view $ARGUMENTS --json title,mergeable,statusCheckRollup`
3. Report gate status ONCE. Do NOT poll CI unless the user asks.
4. Check for stale reasoning-gate verdict/allowlist files left by other branches; flag them.
5. Verify the fix: show a test that fails on the base commit and passes on HEAD.
6. Unless the user said "merge now / low-risk", get a second opinion via pi-px:
   from the repo dir, `pwsh -NoLogo -Command 'pi-px --model openai-codex/gpt-6-luna:high -p "Review the diff of PR <N> (gh pr diff <N>) for correctness bugs. List findings only."'`
   Address real findings before merging.
7. `gh pr merge $ARGUMENTS --squash --delete-branch`
8. `git worktree prune`; list leftover branches/scratch files for deletion. Report worktree dirs
   that Windows refuses to delete (file locks) instead of retrying.
