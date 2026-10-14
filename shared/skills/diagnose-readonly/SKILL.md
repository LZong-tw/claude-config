---
name: diagnose-readonly
description: Read-only diagnosis — investigate, then propose numbered actions and wait. Use when the user wants diagnosis before any change.
---
1. Read-only only: no kills, edits, restarts, deletes, or installs.
2. Gather direct evidence (process + port + parent chain, logs, config). Label each conclusion
   `Verified:` (with the evidence) or `Hypothesis:`.
3. Output a numbered list of proposed actions, each with risk and reversibility.
4. Stop. Execute only the numbers the user replies with.
