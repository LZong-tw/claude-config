---
name: handoff
description: Wind down the session — update and commit the handoff doc, then print one copy-paste takeover prompt. Use when the user says handoff / wrap up / 交接.
---
1. Find the repo's handoff doc (HANDOFF.md, docs/handoff*.md, or ask once if none exists).
2. Update it: current goal, what is done (with verified commit SHAs from `git log -1 --format=%H`),
   what is in flight, open PRs, known blockers, next concrete step.
3. Commit and push the doc only. Do NOT poll CI.
4. Output exactly one fenced block: a self-contained takeover prompt that points at the doc
   path and states the next step. Nothing else after it.
