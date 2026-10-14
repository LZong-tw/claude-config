<!-- clawback:v1:begin -->
# Clawback — Behavioral Guidance

This section is managed by Clawback. Mechanical enforcement (typecheck, lint, format,
file protection, context re-injection) is handled by hooks in ~/.claude/hooks/.

## What the Hooks Do (Don't Duplicate This Work)

- **After every edit:** Your code is auto-formatted and linted. Do NOT manually run
  prettier, eslint, gofmt, cargo fmt, ruff format, or pint. The hooks handle it.
- **Before completion:** Full typecheck + lint runs automatically. If it fails, you
  will be asked to fix errors before completing. Do NOT manually run tsc, go build,
  cargo check, mypy, or phpstan for verification — the hooks do this.
- **Protected files:** .env*, lockfiles, and .git/ are blocked from editing.
  Do NOT attempt to write to these files.

## Execution Discipline

### Phased Execution
For large multi-file refactors, break work into phases and verify each one. Once the
user has approved a plan, run its phases through to the end without asking between them.
Stop to ask only for: gate-file merges, irreversible/destructive actions, a break you
caused, or a genuine ambiguity the plan does not answer. Mechanical or Tier C work
(prompts, docs, tests) needs no phase gate.

### Plan != Build
When asked to "make a plan" or "think about this first," output only the plan.
No code until the user says go.

### One-Word Mode
When the user says "yes," "do it," or "push" — execute immediately.
Don't repeat the plan.

## Context Awareness

### Context Decay
After 10+ messages, re-read any file before editing it. Do not trust your memory.
Auto-compaction may have silently destroyed that context.

### Sub-Agent Swarming
For tasks touching >5 independent files, launch parallel sub-agents. One agent
processing 20 files sequentially guarantees context decay.

## Code Quality

### Senior Dev Override
If architecture is flawed, state is duplicated, or patterns are inconsistent —
propose structural fixes. Don't just do the minimum.

### Write Human Code
No robotic comment blocks, no excessive section headers. If three experienced devs
would all write it the same way, that's the way.

## Self-Improvement

### Mistake Logging
After ANY correction from the user, log the pattern to gotchas.md. The PostCompact
hook re-injects gotchas.md after context compaction, so lessons persist.

### Edit Safety
When renaming anything, search separately for: direct calls, type-level references,
string literals, dynamic imports, re-exports, barrel files, test files and mocks.
You have grep, not an AST.
<!-- clawback:v1:end -->

<!-- user-additions: NOT managed by Clawback; safe to edit -->

## Scope Control
- Do exactly what was asked. Do not redesign layouts, restructure files, or refactor adjacent code unless explicitly requested.
- If you touched something that broke a live service (proxy, auth, session), STOP and report — do not attempt further repairs without confirmation.

## Verification Discipline

Never report a commit SHA, hash, tag, or merge state from memory. Confirm it first
with `git rev-parse` / `git log` and paste the actual output. When tool output may be
corrupted (e.g. RTK proxy mangling stdout), cross-check the same fact through a second
independent channel before claiming success — output corruption has previously induced
fabricated SHAs.

## Diagnosis Discipline
- State root-cause claims as HYPOTHESES until verified with direct evidence (log line, file content, command output). Label them 'Hypothesis:' vs 'Verified:'.
- Never claim a fix works without a reproduction that fails on the old code and passes on the new.
- Before proposing to delete a script/config, grep the whole system for other consumers first.

## Before Removing Code

Before deleting or "cleaning up" any file or script deemed redundant, grep the repo for
dependents (and check whether other apps/shortcuts shell out to it) and confirm nothing
relies on it. Surface what you find instead of assuming it's dead.

## Shell & Environment Conventions

This is a Windows host (Git Bash / PowerShell / WSL side-by-side). Match syntax to the tool:
never PowerShell syntax (`$null`, cmdlets) inside the Bash tool or vice versa. In the Bash
tool, do not rely on `$VAR`/`$1` expansion inside double-quoted wrappers — the harness's outer
quoting can expand them to empty strings; prefer literal absolute paths. Node.js invocations
need Windows-style paths. On the first shell error, diagnose the dialect/quoting mismatch —
do not retry the same command shape. Preserve each file's existing line endings (CRLF stays CRLF).

## Hypothesis Discipline

On a terse or ambiguous request, restate the goal in one line and confirm the referent before
investigating. When debugging, name the top candidate root causes, verify the cheapest
discriminating evidence first, and label unverified intermediate conclusions as hypotheses —
never state them as facts. Do not expand scope beyond the ask (no unrequested redesigns), and
after an action of yours breaks something, stop and confirm with the user before touching
anything else.

## Git & Deploy Workflow

Before any deploy, merge, vendor, or release operation, sync first: `git fetch` and confirm
the local ref is current with the remote (`git status` / `git rev-parse @ @{u}`), then operate
on the up-to-date tree. Never deploy or merge from a checkout you haven't just confirmed is
current — stale local refs have caused deploys of outdated code and false risk-scanner floods.

## Before Deploying or Merging
- ALWAYS `git fetch --all && git status` and confirm the working branch is synced BEFORE any deploy, publish, or merge action.
- Never poll CI unless explicitly asked; if the user says 'merge now / low-risk', merge and report, don't wait on checks.
- After a merge, clean up: delete merged branches and stale worktrees, and remove scratch files.
  Windows often file-locks removed worktree dirs; report any that won't delete instead of retrying.
- Reasoning-gate verdict/allowlist files are branch-specific; check for stale ones from other branches before re-running a gate.
- Second-opinion code review goes through pi-px (PowerShell profile function; tool shells skip the profile, so wrap in pwsh), not hcx or raw codex:
  `pwsh -NoLogo -Command 'pi-px --model openai-codex/gpt-6-luna:high -p "<review prompt>"'` (run from the repo dir)
  WSL fallback: `wsl -e zsh -ic 'pi-px --model openai/gpt-6-luna:high -p "..."'` (provider name differs per side)

## Handoffs
When asked to wind down or hand off, deliver exactly two things: the updated handoff doc
committed to the repo, and one fenced copy-paste takeover prompt for the next session.
Do not poll CI while doing this.

## Server-side Tools (advisor)

`advisor` is a server-side tool: it does not show up in ToolSearch or the deferred tool list.
Not finding it by search does not mean it is unavailable. If a recent `advisor_tool`
attachment says `available:true`, or the user set `/advisor`, call `advisor()` directly once
before saying it is missing. Never tell the user to open a new session over this.


