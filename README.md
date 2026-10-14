# claude-config

My Claude Code setup on Windows: a few hooks, skills, and a read-only health report.
Published the same way as my other dotfile repos, but generated: nothing here is copied
by hand from `~/.claude`, and the live `settings.json` is never published.

## What is here

| Path | What |
|---|---|
| `shared/skills/` | `merge-pr`, `converge-pr`, `handoff`, `diagnose-readonly`, `survey` |
| `windows/hooks/` | `session-healthcheck` (warns at startup if bash, rtk or the proxy is down), `codex-concurrency-gate`, `bash-ps-syntax-guard`, `cleanup-serena`, with tests |
| `windows/scripts/daily-watchdog.ps1` | Collects process, memory and worktree facts itself, then asks `claude -p` (no tools) to summarize. Reports only, never kills anything |
| `windows/examples/` | Sanitized `settings.example.json` and `CLAUDE.example.md` |
| `wsl/hooks/bash_guard.py` | PreToolUse guard: blocks broad `pkill -f` / `killall` and unreplaced `<PLACEHOLDER>` text in commands, ignoring heredoc bodies |
| `wsl/skills/parallel-fix` | Several independent fixes in parallel, one worktree and subagent each |
| `wsl/examples/` | Sanitized `settings.example.json` (the WSL `CLAUDE.md` is not published) |

Not here on purpose: statusline scripts live in
[claude-statusline-config](https://github.com/LZong-tw/claude-statusline-config), pxpipe scheduled tasks in
[my-posh-settings](https://github.com/LZong-tw/my-posh-settings).

## Install

```powershell
.\install.ps1                 # copies hooks, scripts, skills; skips files that already exist
.\install.ps1 -MergeSettings  # also adds missing env keys, permission rules and hook commands (backs up first)
```

On WSL/Linux: `./install.sh` and `./install.sh --merge-settings` do the same for `wsl/` (set `CLAUDE_DIR` to target another directory).

`{{HOME}}` in the examples is filled with your home directory at install time. The merge is additive:
it never removes or edits anything already in your `settings.json`, and it does not touch `model`, `language`, or `effortLevel`.

## How publishing works

`tools/export.ps1` builds the public tree from an allowlist of files, rebuilds `settings.example.json`
from an allowlist of keys, replaces the home path with `{{HOME}}`, then scans the exact output for user paths,
emails, keys, private IPs and a local denylist (`tools/denylist.local.txt`, gitignored). Any hit aborts the export
and leaves the repo untouched. Run `tools/export.tests.ps1` to check the scanner still blocks what it should.

```powershell
tools\export.ps1                                  # windows
tools\export.ps1 -Flavor wsl -Source \\wsl.localhost\<distro>\home\<user>\.claude -HomePath /home/<user>
```
