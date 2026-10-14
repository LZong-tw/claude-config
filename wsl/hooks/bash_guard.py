#!/usr/bin/env python3
"""PreToolUse guard for Bash: block broad kills and unreplaced placeholders.

Heredoc bodies are ignored (file content, not commands). Kill commands only
match in command position (line start or after ; & | ( $( ).
"""
import json, re, sys

try:
    cmd = json.load(sys.stdin).get("tool_input", {}).get("command", "")
except Exception:
    sys.exit(0)


def strip_heredocs(s: str) -> str:
    out, lines, i = [], s.split("\n"), 0
    while i < len(lines):
        line = lines[i]
        out.append(line)
        m = re.search(r"<<-?\s*['\"]?(\w+)['\"]?", line)
        if m:
            tag = m.group(1)
            i += 1
            while i < len(lines) and lines[i].strip() != tag:
                i += 1
        i += 1
    return "\n".join(out)


code = strip_heredocs(cmd)
CMDPOS = r"(?:^|[;&|(\n]|\$\()\s*(?:sudo\s+)?"
checks = [
    (CMDPOS + r"(?:pkill\s+(?:-\S+\s+)*-f\b|killall\b)",
     "broad pkill -f/killall: use pgrep -af then kill PID"),
    (r"<(?:YOUR|REPLACE|PLACEHOLDER|TODO)[A-Z_]*>|\bYOUR_[A-Z_]+\b|\bREPLACE_ME\b",
     "unreplaced placeholder"),
]
for pat, msg in checks:
    if re.search(pat, code, re.M):
        print(f"Blocked by bash_guard: {msg}", file=sys.stderr)
        sys.exit(2)
sys.exit(0)
