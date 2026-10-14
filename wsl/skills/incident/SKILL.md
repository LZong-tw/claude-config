---
name: incident
description: Structured production incident investigation with ranked hypotheses and optional parallel subagents. Use for prod bugs, unexplained behavior, outages.
---
# /incident <symptom>

1. Preflight: `df -h /`; confirm the credentials and access you will rely on actually work before using them. If the project keeps secrets in an encrypted vault, check it decrypts (`ansible-vault view --vault-password-file "$PREFLIGHT_VAULT_PASS" "$PREFLIGHT_VAULT_FILE"`, see `ship/preflight.sh` for the same check) and that database access works.
2. List 4-5 distinct hypotheses. Cover: recent deploys (`git log`, deployed SHA), external dependencies failing (third-party APIs, payment gateways, CDN or tunnel provider), CI/test side effects hitting real services, hardcoded config / feature flags, data or dedup issues. For each: one command or log check that confirms or rules it out.
3. Show the list to the user before digging (they may veto).
4. If hypotheses are independent and more than 2, spawn one subagent per hypothesis (read-only unless told otherwise). Each returns: verdict CONFIRMED / REFUTED / INCONCLUSIVE, exact commands run, raw evidence (log lines, SHAs, timestamps). No verdict from inference alone.
5. Synthesize a ranked report. Every claim tagged VERIFIED (with evidence) or UNVERIFIED. Never state dates, deploy status or fix status unchecked.
6. Propose the fix as logical commits in one MR/PR; wait for approval; then hand off to `/ship`.
