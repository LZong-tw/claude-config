[CmdletBinding()]
param(
  [string]$Target = (Join-Path $env:USERPROFILE '.claude'),
  [switch]$MergeSettings,
  [switch]$Force
)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$homeFwd = ($env:USERPROFILE -replace '\\', '/')

function Copy-Tree([string]$from, [string]$to) {
  Get-ChildItem $from -Recurse -File | ForEach-Object {
    $dst = Join-Path $to $_.FullName.Substring($from.Length + 1)
    if ((Test-Path $dst) -and -not $Force) { Write-Output "skip (exists): $dst"; return }
    New-Item -ItemType Directory -Force (Split-Path $dst) | Out-Null
    $text = (Get-Content $_.FullName -Raw).Replace('{{HOME}}', $homeFwd)
    [IO.File]::WriteAllText($dst, $text, [Text.UTF8Encoding]::new($false))
    Write-Output "wrote: $dst"
  }
}

Copy-Tree (Join-Path $root 'windows\hooks') (Join-Path $Target 'hooks')
Copy-Tree (Join-Path $root 'windows\scripts') (Join-Path $Target 'scripts')
Copy-Tree (Join-Path $root 'shared\skills') (Join-Path $Target 'skills')

if (-not $MergeSettings) {
  Write-Output "settings.json untouched. Review windows\examples\settings.example.json, or rerun with -MergeSettings."
  return
}

# Additive merge: only env keys, permission rules and hook commands that are missing get added.
$settingsPath = Join-Path $Target 'settings.json'
$ex = (Get-Content (Join-Path $root 'windows\examples\settings.example.json') -Raw).Replace('{{HOME}}', $homeFwd) | ConvertFrom-Json -AsHashtable
$cur = if (Test-Path $settingsPath) { Get-Content $settingsPath -Raw | ConvertFrom-Json -AsHashtable } else { @{} }
if (Test-Path $settingsPath) { Copy-Item $settingsPath "$settingsPath.bak-$(Get-Date -Format yyyyMMddHHmmss)" }

if (-not $cur.env) { $cur.env = @{} }
foreach ($k in $ex.env.Keys) { if (-not $cur.env.ContainsKey($k)) { $cur.env[$k] = $ex.env[$k] } }

if (-not $cur.permissions) { $cur.permissions = @{} }
foreach ($list in 'allow', 'deny') {
  $merged = [System.Collections.Generic.List[object]]::new()
  foreach ($x in @($cur.permissions[$list]) + @($ex.permissions[$list])) { if ($x -and $x -notin $merged) { $merged.Add($x) } }
  $cur.permissions[$list] = $merged
}

if (-not $cur.hooks) { $cur.hooks = @{} }
$have = @($cur.hooks.Values | ForEach-Object { $_ } | ForEach-Object { $_.hooks } | ForEach-Object { $_.command })
foreach ($ev in $ex.hooks.Keys) {
  foreach ($g in $ex.hooks[$ev]) {
    $new = @($g.hooks | Where-Object { $_.command -notin $have })
    if (-not $new.Count) { continue }
    $ng = @{ hooks = $new }
    if ($g.matcher) { $ng.matcher = $g.matcher }
    if (-not $cur.hooks[$ev]) { $cur.hooks[$ev] = @() }
    $cur.hooks[$ev] = @($cur.hooks[$ev]) + $ng
  }
}

[IO.File]::WriteAllText($settingsPath, ($cur | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))
Write-Output "merged into $settingsPath (backup written alongside)"
