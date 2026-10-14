// PreToolUse (Bash|PowerShell): refuse a `codex exec` when two are already running
// machine-wide.
//
// The `codex` wrapper in ~/.local/bin (codex-gate.mjs) already queues anything past
// the limit. This hook is the part the model cannot route around: it sees the command
// text before it runs and tells the session to wait, instead of letting it stack
// queued dispatches it thinks are running.
//
// Busy count = max(slot ports held by the wrapper, codex.exe processes running
// `exec`). The process count catches dispatches that bypassed the wrapper, and a
// child that outlived a killed wrapper. If a count cannot be taken it is left out
// rather than treated as zero; if neither can be taken the command is allowed with
// a warning -- a resource limiter that wedges every session on a WMI hiccup is worse
// than the occasional third dispatch.

import net from 'node:net';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

const LIMIT = 2;
const BASE_PORT = 47311;
// Only codex in COMMAND POSITION counts: line start, after ; & | ( or $( -- plus a
// backtick in Bash, where it is command substitution (in PowerShell it is an escape).
// Matching the words anywhere blocked prose: a memory file that merely described this
// gate was refused while the gate was full. Anything this misses still hits the
// wrapper's queue, so a narrow pattern costs little.
const PATHISH = String.raw`(?:["']?[\w.:~@+/\\-]*[\\/])?`;
const LEAD = String.raw`(?:(?:env\s+)?(?:\w+=\S*\s+)*)(?:nohup\s+|exec\s+|&\s*|time\s+)?`;
const TAIL = String.raw`[^|;&\n]*?\bexec(?![\w-])`;
function codexExecPattern(tool) {
  const boundary = tool === 'Bash' ? String.raw`(?:^|[;&|(\x60\n]|\$\()` : String.raw`(?:^|[;&|(\n]|\$\()`;
  const direct = `${LEAD}${PATHISH}codex(?:\\.cmd|\\.ps1|\\.exe)?["']?\\s${TAIL}`;
  const viaNode = `${LEAD}${PATHISH}node(?:\\.exe)?["']?\\s+${PATHISH}codex\\.js["']?\\s${TAIL}`;
  return new RegExp(`${boundary}\\s*(?:${direct}|${viaNode})`, 'im');
}

let raw = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (c) => (raw += c));
process.stdin.on('end', async () => {
  let command = '';
  let tool = '';
  try {
    const input = JSON.parse(raw || '{}');
    command = input?.tool_input?.command ?? '';
    tool = input?.tool_name ?? '';
  } catch {
    process.exit(0);
  }
  if (typeof command !== 'string' || !codexExecPattern(tool).test(command)) process.exit(0);

  const [slots, procs] = await Promise.all([busySlots(), execProcesses()]);
  const known = [slots, procs].filter((n) => n !== null);
  if (known.length === 0) {
    console.error('[codex-gate hook] could not count running codex exec; allowing');
    process.exit(0);
  }
  const busy = Math.max(...known);
  if (busy < LIMIT) process.exit(0);

  console.error(
    `Blocked: ${busy} codex exec already running on this machine (limit ${LIMIT}; ` +
      `slot ports ${slots ?? 'unreadable'}, codex.exe exec processes ${procs ?? 'unreadable'}). ` +
      'Wait for one of them to finish, then retry this exact command. Do not work around ' +
      'this by changing how codex is invoked -- the limit exists because concurrent ' +
      'dispatches exhausted memory on this 32 GB machine (workstation-forensics ' +
      'docs/slow-moment-log.md, 2026-10-05).'
  );
  process.exit(2);
});

function probe(port) {
  return new Promise((resolve) => {
    const sock = net.connect({ host: '127.0.0.1', port });
    const done = (v) => {
      sock.destroy();
      resolve(v);
    };
    sock.setTimeout(500, () => done(false));
    sock.once('connect', () => done(true));
    sock.once('error', () => done(false));
  });
}

async function busySlots() {
  try {
    const held = await Promise.all(Array.from({ length: LIMIT }, (_, i) => probe(BASE_PORT + i)));
    return held.filter(Boolean).length;
  } catch {
    return null;
  }
}

// Must stay asynchronous: a synchronous spawn blocks the event loop for the ~0.8 s
// PowerShell takes, the 500 ms probe timeouts fire before the connect events are
// processed, and every held slot reads as free. The first draft did exactly that and
// still passed every idle test.
async function execProcesses() {
  try {
    const { stdout } = await promisify(execFile)(
      'powershell.exe',
      [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        '$ErrorActionPreference="Stop"; @(Get-CimInstance Win32_Process -Filter "Name=\'codex.exe\'" | Where-Object { $_.CommandLine -match " exec " }).Count',
      ],
      { encoding: 'utf8', timeout: 8000, windowsHide: true }
    );
    const out = stdout.trim();
    return /^\d+$/.test(out) ? Number(out) : null;
  } catch {
    return null;
  }
}
