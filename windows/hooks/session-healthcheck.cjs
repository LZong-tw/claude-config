// SessionStart health check: warn early when bash, rtk or the pxpipe proxy is broken,
// instead of finding out mid-task. Silent when everything is fine; never blocks startup.
const { spawnSync } = require("child_process");
const net = require("net");

const PXPIPE_PORT = Number(process.env.HEALTHCHECK_PXPIPE_PORT || 47821);
const BASH = process.env.HEALTHCHECK_BASH || "bash";
const RTK = process.env.HEALTHCHECK_RTK || "rtk";

function runs(cmd, args, expect) {
  const r = spawnSync(cmd, args, { encoding: "utf8", timeout: 1500, windowsHide: true });
  if (r.error) return r.error.code || r.error.message;
  if (r.status !== 0) return `exit ${r.status}`;
  if (expect && !expect.test(r.stdout)) return `unexpected output: ${r.stdout.trim().slice(0, 80)}`;
  return null;
}

function portOpen(port) {
  return new Promise((resolve) => {
    const s = net.connect({ host: "127.0.0.1", port });
    const done = (ok) => { s.destroy(); resolve(ok); };
    s.setTimeout(800, () => done(false));
    s.once("connect", () => done(true));
    s.once("error", () => done(false));
  });
}

async function main() {
  const problems = [];
  const bash = runs(BASH, ["-c", "echo ok"], /^ok/);
  if (bash) problems.push(`bash broken (${bash}) — Bash tool calls will fail; use PowerShell`);
  const rtk = runs(RTK, ["--version"], /rtk/i);
  if (rtk) problems.push(`rtk unavailable (${rtk}) — command rewrite hook will misbehave`);
  if (!(await portOpen(PXPIPE_PORT))) problems.push(`pxpipe proxy not listening on 127.0.0.1:${PXPIPE_PORT} — pi-px reviews will fail`);
  if (problems.length) process.stdout.write("SESSION HEALTHCHECK WARNINGS:\n- " + problems.join("\n- ") + "\n");
}

const guard = setTimeout(() => process.exit(0), 3000);
main().catch(() => {}).finally(() => { clearTimeout(guard); process.exit(0); });
