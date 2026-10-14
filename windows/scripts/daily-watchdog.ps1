# Daily read-only health report. The script gathers facts itself; claude only summarizes
# (no tools granted), so nothing can be killed, deleted or restarted.
param(
  [string]$ReposRoot = $(if ($env:WATCHDOG_REPOS_ROOT) { $env:WATCHDOG_REPOS_ROOT } else { 'C:\dev' }),
  [int[]]$Ports = $(if ($env:WATCHDOG_PORTS) { $env:WATCHDOG_PORTS -split ',' | ForEach-Object { [int]$_ } } else { @(47821, 9127) }),
  [string[]]$TaskNames = $(if ($env:WATCHDOG_TASKS) { $env:WATCHDOG_TASKS -split ',' } else { @('PxpipeWatchdog', 'WinPxpipeProxy', 'ClaudeIdleBurnSample') })
)
$claude = (Get-Command claude -ErrorAction Stop).Source
$dir = Join-Path $env:USERPROFILE ".claude\watchdog-reports"
New-Item -ItemType Directory -Force $dir | Out-Null
$out = Join-Path $dir ("{0:yyyy-MM-dd}.md" -f (Get-Date))

$procs = Get-CimInstance Win32_Process -Filter "Name='claude.exe' OR Name='node.exe' OR Name='python.exe' OR Name='pi.exe'" |
  ForEach-Object {
    $p = Get-Process -Id $_.ProcessId -EA 0
    [pscustomobject]@{
      Pid = $_.ProcessId; Name = $_.Name; ParentPid = $_.ParentProcessId
      ParentAlive = [bool](Get-Process -Id $_.ParentProcessId -EA 0)
      PrivateMB = [int]($p.PrivateMemorySize64 / 1MB); WorkingSetMB = [int]($p.WorkingSet64 / 1MB)
      Started = $_.CreationDate; Cmd = "$($_.CommandLine)".Substring(0, [Math]::Min(160, "$($_.CommandLine)".Length))
    }
  }
$ports = Get-NetTCPConnection -State Listen -EA 0 | Where-Object LocalPort -in $Ports |
  Select-Object LocalPort, OwningProcess -Unique
$os = Get-CimInstance Win32_OperatingSystem
$mem = [pscustomobject]@{
  FreeRamMB = [int]($os.FreePhysicalMemory / 1KB); TotalRamMB = [int]($os.TotalVisibleMemorySize / 1KB)
  CommitUsedMB = [int](($os.TotalVirtualMemorySize - $os.FreeVirtualMemory) / 1KB); CommitLimitMB = [int]($os.TotalVirtualMemorySize / 1KB)
}
$worktrees = Get-ChildItem $ReposRoot -Directory -EA 0 | Where-Object { Test-Path (Join-Path $_.FullName .git) } | ForEach-Object {
  [pscustomobject]@{
    Repo = $_.Name
    Worktrees = (git -C $_.FullName worktree list --porcelain 2>$null) -join "`n"
    Merged = (git -C $_.FullName branch --merged 2>$null) -join ","
  }
}
$tasks = $TaskNames | ForEach-Object {
  $i = Get-ScheduledTaskInfo $_ -EA 0; [pscustomobject]@{ Task = $_; LastRun = $i.LastRunTime; LastResult = $i.LastTaskResult }
}

$facts = [pscustomobject]@{ Processes = $procs; Ports = $ports; Memory = $mem; Worktrees = $worktrees; Tasks = $tasks } |
  ConvertTo-Json -Depth 5

$prompt = @"
Below is JSON collected just now from this Windows machine. Write a short read-only health report in Traditional Chinese (zh-TW), markdown.
Flag: orphaned processes (ParentAlive=false), large private/working-set processes, who owns the listening ports in Ports,
commit pressure (used/limit), prunable or merged worktrees, scheduled tasks with nonzero LastResult.
Label each finding Verified (directly in the data) or Hypothesis (inferred). Remember private bytes are not RAM.
End with a numbered list of suggested cleanup actions for the user to approve. Do not claim anything was executed.

$facts
"@

[Console]::OutputEncoding = [Text.Encoding]::UTF8
$OutputEncoding = [Text.Encoding]::UTF8
$report = $prompt | & $claude -p --model claude-sonnet-5-5 --tools "" 2>> (Join-Path $dir "stderr.log")
Set-Content -Path $out -Value $report -Encoding utf8
