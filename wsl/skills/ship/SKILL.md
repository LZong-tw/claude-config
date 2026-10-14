---
name: ship
description: Fix-to-production pipeline - preflight, regression test, commits, glab MR, CI, merge, staging, prod, cleanup. Use when the user asks to ship/deploy a fix end-to-end.
---
# /ship

Run steps in order. Report evidence (command + output line) at each gate. Mark anything unchecked UNVERIFIED.
Hosts to verify are listed in `SHIP_HOSTS` (space separated) if set; otherwise ask the user.

1. **Preflight**: `bash ~/.claude/skills/ship/preflight.sh` from repo root. Fix any FAIL before continuing.
2. **Regression test first**: write a test that fails on current code; show the failure.
3. **Fix** until it passes. Run the test suite **per test path separately**; report the pass count per path.
4. **Commit split**: ask the user how to split (default: logical commits, one MR). Do not push before agreement.
5. **MR**: `glab mr create --fill --yes --target-branch <target> --remove-source-branch`
6. **CI**: `glab ci status --live` (or poll with ScheduleWakeup ~270s). On failure: `glab ci trace <job>`, fix, retry up to 3 times, then stop and report.
7. **Merge**: only after user approval. `glab mr merge --yes` (auto-merge defaults true: merges when the pipeline passes).
8. **Staging**: deploy, smoke check, verify the deployed commit SHA on **each** host. Report evidence; ask approval for prod.
9. **Prod**: deploy, verify the SHA on **every** host in `SHIP_HOSTS`, check error rates.
10. **Cleanup**: leftover MRs on GitLab (`glab mr list`) and PRs on a GitHub mirror remote if there is one (`gh pr list` / `gh pr close`). Remove the worktree.
11. Any CLI mistake hit: append the correct invocation to ~/.claude/CLAUDE.md "Shell / Bash conventions".
