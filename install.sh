#!/usr/bin/env bash
# WSL/Linux installer. Copies hooks and skills; --merge-settings adds missing settings only.
set -euo pipefail

root=$(cd "$(dirname "$0")" && pwd)
target=${CLAUDE_DIR:-$HOME/.claude}
merge=0
force=0
for a in "$@"; do
  case $a in
    --merge-settings) merge=1 ;;
    --force) force=1 ;;
    *) echo "unknown option: $a" >&2; exit 2 ;;
  esac
done

copy_tree() {
  local src=$1 dst=$2
  [ -d "$src" ] || return 0
  (cd "$src" && find . -type f) | while read -r f; do
    if [ -e "$dst/$f" ] && [ "$force" -eq 0 ]; then echo "skip (exists): $dst/$f"; continue; fi
    mkdir -p "$(dirname "$dst/$f")"
    sed "s|{{HOME}}|$HOME|g" "$src/$f" > "$dst/$f"
    echo "wrote: $dst/$f"
  done
}

copy_tree "$root/wsl/hooks" "$target/hooks"
copy_tree "$root/wsl/skills" "$target/skills"
chmod +x "$target"/hooks/*.py 2>/dev/null || true

if [ "$merge" -eq 0 ]; then
  echo "settings.json untouched. Review wsl/examples/settings.example.json, or rerun with --merge-settings."
  exit 0
fi

settings=$target/settings.json
[ -f "$settings" ] && cp "$settings" "$settings.bak-$(date +%Y%m%d%H%M%S)"
python3 - "$root/wsl/examples/settings.example.json" "$settings" <<'PY'
import json, os, sys

example_path, settings_path = sys.argv[1:3]
ex = json.loads(open(example_path).read().replace("{{HOME}}", os.path.expanduser("~")))
cur = json.load(open(settings_path)) if os.path.exists(settings_path) else {}

env = cur.setdefault("env", {})
for k, v in ex.get("env", {}).items():
    env.setdefault(k, v)

perms = cur.setdefault("permissions", {})
for lst in ("allow", "deny"):
    merged = list(perms.get(lst, []))
    merged += [x for x in ex.get("permissions", {}).get(lst, []) if x not in merged]
    perms[lst] = merged

hooks = cur.setdefault("hooks", {})
have = {h["command"] for gs in hooks.values() for g in gs for h in g.get("hooks", [])}
for event, groups in ex.get("hooks", {}).items():
    for g in groups:
        new = [h for h in g["hooks"] if h["command"] not in have]
        if new:
            ng = {"hooks": new}
            if "matcher" in g:
                ng["matcher"] = g["matcher"]
            hooks.setdefault(event, []).append(ng)

json.dump(cur, open(settings_path, "w"), indent=2)
print(f"merged into {settings_path} (backup written alongside)")
PY
