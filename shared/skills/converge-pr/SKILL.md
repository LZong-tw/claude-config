---
name: converge-pr
description: Drive one PR to merge in-session — review via pi-px, TDD fixes, gate, merge. Args: PR number.
---
Loop until mergeable or blocked:
1. Sync: `git fetch --all`, check out the PR branch, confirm `git rev-parse @ @{u}` match.
2. Review: from the repo dir, `pwsh -NoLogo -Command 'pi-px --model openai-codex/gpt-6-luna:high -p "Review gh pr diff $ARGUMENTS for correctness bugs; findings only."'`
3. For each real finding: write a failing test first, fix, confirm it passes. Commit test+fix together.
4. Run the repo's reasoning-gate / test suite locally once.
5. Stop and ask the user if: a gate exception is needed, a finding is ambiguous, or 3 rounds pass
   without convergence.
6. When clean, invoke the merge-pr skill.
