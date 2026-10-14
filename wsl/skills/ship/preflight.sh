#!/usr/bin/env bash
# Preflight before fix/deploy work. Exit non-zero on any hard failure.
# Optional vault check: set PREFLIGHT_VAULT_FILE and PREFLIGHT_VAULT_PASS (ansible-vault file and its password file),
# either in the environment or in ~/.config/ship/preflight.env.
[ -f ~/.config/ship/preflight.env ] && . ~/.config/ship/preflight.env
fail=0
echo "== disk"; df -h / | tail -1
avail=$(df --output=avail -k / | tail -1); [ "$avail" -lt 3000000 ] && { echo "FAIL: <3G free on /"; fail=1; }
echo "== vendor"; if [ -L vendor ]; then echo "FAIL: vendor is symlink -> $(readlink vendor); run composer install"; fail=1; elif [ -d vendor ]; then echo "ok: real dir"; else echo "warn: no vendor/"; fi
echo "== glab"; glab --version | head -1; glab auth status 2>&1 | grep -Ei "logged in|error" | head -2
echo "== gh"; gh auth status 2>&1 | grep -Ei "logged in|error" | head -2
vault=${PREFLIGHT_VAULT_FILE:-}
pass=${PREFLIGHT_VAULT_PASS:-}
if [ -n "$vault" ] && [ -f "$pass" ]; then echo "== ansible-vault"
  AV=$(command -v ansible-vault || echo ~/.local/bin/ansible-vault)
  keys=$("$AV" view --vault-password-file "$pass" "$vault" </dev/null 2>/dev/null | grep -cE '^[a-z_]+:')
  if [ "${keys:-0}" -gt 0 ]; then echo "ok: $(basename "$vault") decrypts ($keys keys)"; else echo "FAIL: cannot decrypt $(basename "$vault")"; fail=1; fi
fi
echo "== git"; git status -sb 2>/dev/null | head -3
exit $fail
