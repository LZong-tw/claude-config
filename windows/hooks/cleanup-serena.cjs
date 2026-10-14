#!/usr/bin/env node
'use strict';

const { execFileSync, spawnSync } = require('child_process');

const CPU_SAMPLE_MS = Number(process.env.SERENA_CLEANUP_CPU_SAMPLE_MS || 1200);
const IDLE_GRACE_HOURS = Number(process.env.SERENA_CLEANUP_IDLE_GRACE_HOURS || 0.25);
const ORPHAN_WEBVIEW_GRACE_HOURS = Number(process.env.SERENA_CLEANUP_ORPHAN_WEBVIEW_GRACE_HOURS || 0.25);
const HIGH_PRIVATE_MB = Number(process.env.SERENA_CLEANUP_HIGH_PRIVATE_MB || 768);
const LOW_WORKING_SET_MB = Number(process.env.SERENA_CLEANUP_LOW_WORKING_SET_MB || 128);
const LOW_WORKING_SET_RATIO = Number(process.env.SERENA_CLEANUP_LOW_WORKING_SET_RATIO || 0.12);
const IDLE_CPU_SECONDS = Number(process.env.SERENA_CLEANUP_IDLE_CPU_SECONDS || 0.2);
const KILL_SCORE = Number(process.env.SERENA_CLEANUP_KILL_SCORE || 70);
const DRY_RUN = process.argv.includes('--dry-run');
const SERENA_WRAPPER_NAMES = new Set(['serena', 'uvx', 'uv', 'python', 'python3']);
const ACTIVE_PARENT_NAMES = new Set(['claude', 'codex', 'windowsterminal', 'pwsh', 'powershell', 'node']);

function drainStdin() {
  if (process.stdin.isTTY) return;
  process.stdin.resume();
  process.stdin.on('data', () => {});
}

function runQuiet(command, args, options = {}) {
  return spawnSync(command, args, {
    encoding: 'utf8',
    windowsHide: true,
    timeout: options.timeout || 15000,
    maxBuffer: options.maxBuffer || 20 * 1024 * 1024,
  });
}

function getWindowsProcessRows() {
  const script = String.raw`
$ErrorActionPreference = 'SilentlyContinue'
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class ProcInfo {
  [StructLayout(LayoutKind.Sequential)]
  public struct PROCESS_BASIC_INFORMATION {
    public IntPtr Reserved1;
    public IntPtr PebBaseAddress;
    public IntPtr Reserved2_0;
    public IntPtr Reserved2_1;
    public IntPtr UniqueProcessId;
    public IntPtr InheritedFromUniqueProcessId;
  }

  [DllImport("ntdll.dll")]
  public static extern int NtQueryInformationProcess(
    IntPtr processHandle,
    int processInformationClass,
    ref PROCESS_BASIC_INFORMATION processInformation,
    int processInformationLength,
    ref int returnLength
  );

  public static int GetParentPid(System.Diagnostics.Process process) {
    try {
      PROCESS_BASIC_INFORMATION pbi = new PROCESS_BASIC_INFORMATION();
      int returnLength = 0;
      int status = NtQueryInformationProcess(
        process.Handle,
        0,
        ref pbi,
        Marshal.SizeOf(typeof(PROCESS_BASIC_INFORMATION)),
        ref returnLength
      );
      if (status != 0) return 0;
      return pbi.InheritedFromUniqueProcessId.ToInt32();
    } catch {
      return 0;
    }
  }
}
"@

Get-Process | ForEach-Object {
  $p = $_
  [PSCustomObject]@{
    id = $p.Id
    parentId = [ProcInfo]::GetParentPid($p)
    name = $p.ProcessName
    path = $p.Path
    startTime = if ($p.StartTime) { $p.StartTime.ToUniversalTime().ToString("o") } else { $null }
    cpuSeconds = $p.CPU
    handleCount = $p.HandleCount
    threadCount = if ($p.Threads) { $p.Threads.Count } else { 0 }
    privateBytes = $p.PrivateMemorySize64
    workingSet = $p.WorkingSet64
  }
} | ConvertTo-Json -Depth 3 -Compress
`;

  const encoded = Buffer.from(script, 'utf16le').toString('base64');
  const result = runQuiet('powershell.exe', ['-NoProfile', '-EncodedCommand', encoded], {
    timeout: 25000,
  });
  if (result.status !== 0 || !result.stdout.trim()) {
    throw new Error((result.stderr || result.stdout || 'failed to list processes').trim());
  }

  const parsed = JSON.parse(result.stdout);
  return Array.isArray(parsed) ? parsed : [parsed];
}

function getPosixProcessRows() {
  const result = runQuiet('ps', ['-eo', 'pid=,ppid=,comm=,etimes='], {
    timeout: 10000,
  });
  if (result.status !== 0) throw new Error((result.stderr || 'ps failed').trim());

  const now = Date.now();
  return result.stdout
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean)
    .map((line) => {
      const match = line.match(/^(\d+)\s+(\d+)\s+(\S+)\s+(\d+)$/);
      if (!match) return null;
      return {
        id: Number(match[1]),
        parentId: Number(match[2]),
        name: match[3],
        path: '',
        startTime: new Date(now - Number(match[4]) * 1000).toISOString(),
        cpuSeconds: null,
        handleCount: 0,
        threadCount: 0,
        privateBytes: 0,
        workingSet: 0,
      };
    })
    .filter(Boolean);
}

function processName(row) {
  return String(row.name || '').toLowerCase().replace(/\.exe$/, '');
}

function isSerenaProcess(row) {
  const name = processName(row);
  const path = String(row.path || '').toLowerCase();
  return name === 'serena' || path.endsWith('\\serena.exe') || path.endsWith('/serena');
}

function isSerenaWrapper(row) {
  return SERENA_WRAPPER_NAMES.has(processName(row));
}

function isPythonWebView(row) {
  return processName(row) === 'msedgewebview2';
}

function hoursSince(row, now) {
  if (!row.startTime) return 0;
  const started = Date.parse(row.startTime);
  if (!Number.isFinite(started)) return 0;
  return Math.max(0, (now - started) / 36e5);
}

function buildIndex(rows) {
  const byId = new Map();
  const childrenByParent = new Map();

  for (const raw of rows) {
    const row = {
      ...raw,
      id: Number(raw.id),
      parentId: Number(raw.parentId || 0),
      cpuSeconds: raw.cpuSeconds === null || raw.cpuSeconds === undefined ? null : Number(raw.cpuSeconds),
      cpuDeltaSeconds:
        raw.cpuDeltaSeconds === null || raw.cpuDeltaSeconds === undefined ? null : Number(raw.cpuDeltaSeconds),
      handleCount: Number(raw.handleCount || 0),
      threadCount: Number(raw.threadCount || 0),
      privateBytes: Number(raw.privateBytes || 0),
      workingSet: Number(raw.workingSet || 0),
    };
    if (!Number.isFinite(row.id)) continue;
    byId.set(row.id, row);
  }

  for (const row of byId.values()) {
    if (!childrenByParent.has(row.parentId)) childrenByParent.set(row.parentId, []);
    childrenByParent.get(row.parentId).push(row.id);
  }

  return { byId, childrenByParent };
}

function ancestorSet(byId, pid) {
  const seen = new Set();
  let current = byId.get(pid);
  while (current && !seen.has(current.id)) {
    seen.add(current.id);
    current = byId.get(current.parentId);
  }
  return seen;
}

function descendantSet(childrenByParent, pid) {
  const seen = new Set();
  const stack = [pid];
  while (stack.length) {
    const next = stack.pop();
    if (seen.has(next)) continue;
    seen.add(next);
    for (const child of childrenByParent.get(next) || []) stack.push(child);
  }
  return seen;
}

function hasDescendant(childrenByParent, byId, pid, predicate) {
  for (const descendantPid of descendantSet(childrenByParent, pid)) {
    if (descendantPid === pid) continue;
    const descendant = byId.get(descendantPid);
    if (descendant && predicate(descendant)) return true;
  }
  return false;
}

function rootForSerena(byId, row) {
  let root = row;
  let parent = byId.get(row.parentId);
  const seen = new Set([row.id]);
  while (parent && !seen.has(parent.id) && isSerenaWrapper(parent)) {
    root = parent;
    seen.add(parent.id);
    parent = byId.get(parent.parentId);
  }
  return root;
}

function rootForSerenaLikeTree(byId, row) {
  let root = row;
  let parent = byId.get(row.parentId);
  const seen = new Set([row.id]);
  while (parent && !seen.has(parent.id) && (isSerenaWrapper(parent) || processName(parent) === 'conhost')) {
    root = parent;
    seen.add(parent.id);
    parent = byId.get(parent.parentId);
  }
  return root;
}

function rootForWebViewTree(byId, row) {
  let root = row;
  let parent = byId.get(row.parentId);
  const seen = new Set([row.id]);
  while (parent && !seen.has(parent.id) && isPythonWebView(parent)) {
    root = parent;
    seen.add(parent.id);
    parent = byId.get(parent.parentId);
  }
  return root;
}

function getProcessRows() {
  return process.platform === 'win32' ? getWindowsProcessRows() : getPosixProcessRows();
}

function sleepSync(ms) {
  if (ms <= 0) return;
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
}

function withCpuDeltas(firstRows, secondRows) {
  const firstById = new Map(firstRows.map((row) => [Number(row.id), row]));
  return secondRows.map((row) => {
    const previous = firstById.get(Number(row.id));
    const before = previous?.cpuSeconds === null || previous?.cpuSeconds === undefined ? null : Number(previous.cpuSeconds);
    const after = row.cpuSeconds === null || row.cpuSeconds === undefined ? null : Number(row.cpuSeconds);
    const cpuDeltaSeconds =
      Number.isFinite(before) && Number.isFinite(after) ? Math.max(0, after - before) : null;
    return { ...row, cpuDeltaSeconds };
  });
}

function getSampledProcessRows() {
  const firstRows = getProcessRows();
  if (CPU_SAMPLE_MS <= 0) return firstRows;
  sleepSync(CPU_SAMPLE_MS);
  return withCpuDeltas(firstRows, getProcessRows());
}

function treeMetrics(root, byId, childrenByParent, protectedPids, now) {
  const tree = [...descendantSet(childrenByParent, root.id)].filter((pid) => !protectedPids.has(pid));
  const rows = tree.map((pid) => byId.get(pid)).filter(Boolean);
  const privateBytes = rows.reduce((sum, row) => sum + (row.privateBytes || 0), 0);
  const workingSet = rows.reduce((sum, row) => sum + (row.workingSet || 0), 0);
  const cpuDeltas = rows
    .map((row) => row.cpuDeltaSeconds)
    .filter((value) => Number.isFinite(value));
  const cpuDeltaSeconds = cpuDeltas.length ? cpuDeltas.reduce((sum, value) => sum + value, 0) : null;
  const parent = byId.get(root.parentId);
  const privateMB = privateBytes / 1024 / 1024;
  const workingSetMB = workingSet / 1024 / 1024;

  return {
    ageHours: hoursSince(root, now),
    cpuDeltaSeconds,
    handleCount: rows.reduce((sum, row) => sum + (row.handleCount || 0), 0),
    parentMissing: root.parentId > 4 && !parent,
    parentName: parent ? processName(parent) : '',
    privateMB,
    threadCount: rows.reduce((sum, row) => sum + (row.threadCount || 0), 0),
    tree,
    webViewCount: rows.filter(isPythonWebView).length,
    workingSetMB,
    workingSetRatio: privateMB > 0 ? workingSetMB / privateMB : 1,
  };
}

function idleLeakScore(kind, metrics) {
  const signals = [];
  let score = 0;

  if (metrics.privateMB >= HIGH_PRIVATE_MB) {
    score += 25;
    signals.push(`private>=${HIGH_PRIVATE_MB}MB`);
  }
  if (metrics.workingSetMB <= LOW_WORKING_SET_MB || metrics.workingSetRatio <= LOW_WORKING_SET_RATIO) {
    score += 30;
    signals.push('low-working-set');
  }
  if (metrics.cpuDeltaSeconds !== null && metrics.cpuDeltaSeconds <= IDLE_CPU_SECONDS) {
    score += 20;
    signals.push('cpu-idle');
  } else if (metrics.cpuDeltaSeconds !== null && metrics.cpuDeltaSeconds > IDLE_CPU_SECONDS * 4) {
    score -= 40;
    signals.push('cpu-active');
  }
  if (metrics.webViewCount > 0) {
    score += 10;
    signals.push(`webview=${metrics.webViewCount}`);
  }
  if (metrics.ageHours >= 1) {
    score += 10;
    signals.push('age>=1h');
  }
  if (metrics.ageHours >= 4) {
    score += 10;
    signals.push('age>=4h');
  }
  if (ACTIVE_PARENT_NAMES.has(metrics.parentName)) {
    score -= 20;
    signals.push(`active-parent=${metrics.parentName}`);
  }
  if (metrics.privateMB < 256) {
    score -= 30;
    signals.push('small-tree');
  }

  return {
    kill: metrics.ageHours >= IDLE_GRACE_HOURS && score >= KILL_SCORE,
    reason: `idle-leak-${kind}:score=${score}:${signals.join(',') || 'no-signals'}`,
    score,
  };
}

function addTarget(targets, root, kind, metrics, reason) {
  if (targets.has(root.id)) return;
  targets.set(root.id, {
    pid: root.id,
    name: root.name,
    reason,
    ageHours: Number(metrics.ageHours.toFixed(2)),
    cpuDeltaSeconds:
      metrics.cpuDeltaSeconds === null ? null : Number(metrics.cpuDeltaSeconds.toFixed(3)),
    privateMB: Number(metrics.privateMB.toFixed(1)),
    workingSetMB: Number(metrics.workingSetMB.toFixed(1)),
    workingSetRatio: Number(metrics.workingSetRatio.toFixed(3)),
    webViewCount: metrics.webViewCount,
    kind,
    path: root.path || '',
  });
}

function collectTargets(rows) {
  const now = Date.now();
  const { byId, childrenByParent } = buildIndex(rows);
  const protectedPids = ancestorSet(byId, process.pid);
  const targets = new Map();

  for (const row of byId.values()) {
    if (!isSerenaProcess(row) || protectedPids.has(row.id)) continue;
    const root = rootForSerena(byId, row);
    if (protectedPids.has(root.id) || targets.has(root.id)) continue;

    const metrics = treeMetrics(root, byId, childrenByParent, protectedPids, now);
    if (metrics.parentMissing) addTarget(targets, root, 'serena-tree', metrics, 'orphan-serena-tree');
    else {
      const decision = idleLeakScore('serena-tree', metrics);
      if (decision.kill) addTarget(targets, root, 'serena-tree', metrics, decision.reason);
    }
  }

  for (const row of byId.values()) {
    const name = processName(row);
    if (!['python', 'python3', 'uv', 'uvx'].includes(name) || protectedPids.has(row.id)) continue;
    if (!hasDescendant(childrenByParent, byId, row.id, isPythonWebView)) continue;

    const root = rootForSerenaLikeTree(byId, row);
    if (protectedPids.has(root.id) || targets.has(root.id)) continue;

    const metrics = treeMetrics(root, byId, childrenByParent, protectedPids, now);
    if (metrics.parentMissing) addTarget(targets, root, 'serena-python-tree', metrics, 'orphan-serena-python-tree');
    else {
      const decision = idleLeakScore('serena-python-tree', metrics);
      if (decision.kill) addTarget(targets, root, 'serena-python-tree', metrics, decision.reason);
    }
  }

  for (const row of byId.values()) {
    if (!isPythonWebView(row) || protectedPids.has(row.id)) continue;
    const root = rootForWebViewTree(byId, row);
    if (protectedPids.has(root.id) || targets.has(root.id)) continue;

    const metrics = treeMetrics(root, byId, childrenByParent, protectedPids, now);
    if (metrics.parentMissing && metrics.ageHours >= ORPHAN_WEBVIEW_GRACE_HOURS) {
      addTarget(targets, root, 'webview-tree', metrics, 'orphan-webview-tree');
    }
  }

  return [...targets.values()].sort((a, b) => b.privateMB - a.privateMB);
}

function killTree(pid) {
  if (DRY_RUN) return;
  if (process.platform === 'win32') {
    execFileSync('taskkill.exe', ['/T', '/F', '/PID', String(pid)], {
      stdio: 'ignore',
      windowsHide: true,
      timeout: 15000,
    });
  } else {
    spawnSync('pkill', ['-TERM', '-P', String(pid)], { stdio: 'ignore', timeout: 5000 });
    spawnSync('kill', ['-TERM', String(pid)], { stdio: 'ignore', timeout: 5000 });
  }
}

function main() {
  drainStdin();
  const rows = getSampledProcessRows();
  const targets = collectTargets(rows);
  if (!targets.length) return;

  console.error(
    `[serena-cleanup] ${DRY_RUN ? 'would stop' : 'stopping'} ${targets.length} stale/orphan process tree(s)`
  );
  for (const target of targets) {
    console.error(
      `[serena-cleanup] ${target.reason}: pid=${target.pid} name=${target.name} age=${target.ageHours}h private=${target.privateMB}MB ws=${target.workingSetMB}MB`
    );
    try {
      killTree(target.pid);
    } catch (error) {
      console.error(`[serena-cleanup] failed pid=${target.pid}: ${error.message}`);
    }
  }
}

try {
  main();
} catch (error) {
  console.error(`[serena-cleanup] ${error.message}`);
}
