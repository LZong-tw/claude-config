# Global instructions (example)

One file for both Windows and WSL/Linux hosts. Keep the sections you use, delete the rest.

## Execution discipline
- Large multi-file refactors: break into phases and verify each. Once a plan is approved, run its phases through without asking between them. Stop only for merges into a gated branch, irreversible or destructive actions, a break you caused, or an ambiguity the plan does not answer.
- "Make a plan" or "think about this first" means output only the plan, no code until told to go.
- One-word approvals ("yes", "do it", "push", "go") mean execute immediately; do not repeat the plan.
- Do exactly what was asked. No redesigns, restructuring or adjacent refactors unless requested. If an action of yours broke something live, stop and report before any further repair.
- For tasks touching more than 5 independent files, use parallel subagents. After 10+ messages, re-read a file before editing it, since compaction may have dropped its contents.

## Reporting and conclusions
- Label metric columns exactly as named in the source. Never rename or infer columns; if unclear, read the query or command that produced them.
- State root causes as `Hypothesis:` until verified with direct evidence (a log line, file content, command output), then `Verified:`. Anything unchecked is `UNVERIFIED`, with what would confirm it. Cite the command behind each claim.
- Never claim a fix works without a reproduction that fails on the old code and passes on the new. Every fix gets a regression test in the same commit.
- Never report a commit SHA, tag or merge state from memory. Confirm with `git rev-parse` or `git log` and paste the output.
- When debugging, list the top hypotheses with one confirming check each, run the cheapest discriminating check first, and mark each CONFIRMED / RULED OUT / INCONCLUSIVE.
- Before deleting or cleaning up a script or config, grep the whole system for other consumers and surface what you find.

## Shell conventions
- Match syntax to the tool: no PowerShell syntax in a POSIX shell or the reverse. On the first shell error, diagnose the quoting or dialect mismatch instead of retrying the same command shape.
- Preserve each file's existing line endings (CRLF stays CRLF).
- Windows host: Node needs Windows-style paths; inside the Bash tool, prefer literal absolute paths over `$VAR` expansion in double-quoted wrappers.
- Linux/WSL: never use broad `pkill -f` or `killall`. Find PIDs with `pgrep -af <pattern>`, exclude your own shell (`$$`, `$PPID`), then `kill <PID>`.
- Before running a command, check for unreplaced placeholders (`<...>`, TODO, XXX) and unescaped backticks or `$` inside double quotes. Prefer single quotes or heredocs.
- Check `<cli> <cmd> --help` before using flags you have not confirmed.
- After a correction from the user, record the right invocation or rule here so it persists.

## Git and deploy workflow
- Before any deploy, merge or release: `git fetch --all && git status`, confirm the branch is synced with its remote, and operate only on that up-to-date tree.
- Never poll CI unless asked. If told "merge now" or "low-risk", merge and report.
- After a merge, delete merged branches and stale worktrees and remove scratch files. Windows often file-locks removed worktree directories; report any that will not delete instead of retrying.
- Before committing, ask how to split changes. Default: logically separate commits in one MR/PR.
- Gate or verdict files are branch-specific; check for stale ones from other branches before re-running a gate.
- Second-opinion review goes through your review CLI of choice, run from the repo directory.

## Handoffs
When asked to wind down or hand off, deliver exactly two things: the updated handoff doc committed to the repo, and one fenced copy-paste takeover prompt for the next session. Do not poll CI.

## Server-side tools
`advisor` is server-side and does not appear in ToolSearch. If an `advisor_tool` attachment says `available:true` or the user set `/advisor`, call `advisor()` directly before saying it is missing.
