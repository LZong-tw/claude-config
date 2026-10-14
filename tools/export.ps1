[CmdletBinding()]
param(
  [ValidateSet('windows', 'wsl')][string]$Flavor = 'windows',
  [string]$Source,
  [string]$Dest = (Split-Path $PSScriptRoot -Parent),
  [string]$HomePath,
  [string]$LocalDenylist = (Join-Path $PSScriptRoot 'denylist.local.txt')
)
$ErrorActionPreference = 'Stop'
if ($Flavor -eq 'windows') {
  if (-not $Source) { $Source = Join-Path $env:USERPROFILE '.claude' }
  if (-not $HomePath) { $HomePath = $env:USERPROFILE }
} elseif (-not $Source -or -not $HomePath) {
  throw "-Flavor wsl needs -Source (e.g. \\wsl.localhost\<distro>\home\<user>\.claude) and -HomePath (e.g. /home/<user>)"
}

# Everything published is listed here. Anything not listed never leaves the machine.
if ($Flavor -eq 'windows') {
  $hookFiles = 'codex-concurrency-gate.mjs', 'bash-ps-syntax-guard.cjs', 'cleanup-serena.cjs', 'session-healthcheck.cjs'
  $hookTests = 'codex-gate', 'session-healthcheck'
  $skills = 'merge-pr', 'handoff', 'diagnose-readonly', 'survey', 'converge-pr'
  $skillsOut = 'shared\skills'
  $ownedDirs = 'windows', 'shared'
} else {
  $hookFiles = 'bash_guard.py'
  $hookTests = @()
  $skills = 'parallel-fix', 'incident', 'ship'
  $skillsOut = 'wsl\skills'
  $ownedDirs = @('wsl')
}
$safeAllow = 'Bash(git status:*)', 'Bash(git log:*)', 'Bash(git branch:*)', 'Bash(git diff:*)',
  'Bash(gh pr list:*)', 'Bash(gh pr view:*)', 'Bash(gh run list:*)', 'Bash(gh run view:*)',
  'Bash(ls:*)', 'Bash(cat:*)', 'Bash(head:*)', 'Bash(jq:*)', 'Bash(echo:*)', 'WebSearch'

$safeDeny = 'Read(.env)', 'Read(.env.*)', 'Read(**/.env)', 'Read(**/.env.*)', 'Read(**/credentials.*)', 'Read(**/secrets.*)',
  'Read(**/*.key)', 'Read(**/*.pem)', 'Read(**/*.p12)', 'Read(**/*.pfx)'

$stage = Join-Path ([IO.Path]::GetTempPath()) ("claude-config-export-" + [guid]::NewGuid())
New-Item -ItemType Directory -Force $stage | Out-Null

function Copy-Staged([string]$rel, [string]$to, [switch]$Absolute) {
  $target = Join-Path $stage $to
  New-Item -ItemType Directory -Force (Split-Path $target) | Out-Null
  $from = if ($Absolute) { $rel } else { Join-Path $Source $rel }
  Copy-Item $from $target -Recurse -Force
}

function Hide-Home([string]$text) {
  $h = $HomePath.TrimEnd('\', '/')
  $text.Replace(($h -replace '\\', '\\'), '{{HOME}}').Replace($h, '{{HOME}}').Replace(($h -replace '\\', '/'), '{{HOME}}')
}

try {
  foreach ($f in $hookFiles) { Copy-Staged "hooks\$f" "$Flavor\hooks\$f" }
  foreach ($t in $hookTests) { Copy-Staged "hooks\tests\$t" "$Flavor\hooks\tests\$t" }
  if ($Flavor -eq 'windows') { Copy-Staged 'scripts\daily-watchdog.ps1' 'windows\scripts\daily-watchdog.ps1' }
  foreach ($s in $skills) { Copy-Staged "skills\$s" "$skillsOut\$s" }

  # Text files: replace the user's home path with a placeholder the installer fills back in.
  Get-ChildItem $stage -Recurse -File | ForEach-Object {
    $raw = Get-Content $_.FullName -Raw
    $new = Hide-Home $raw
    if ($new -ne $raw) { [IO.File]::WriteAllText($_.FullName, $new, [Text.UTF8Encoding]::new($false)) }
  }

  # settings.json: rebuilt from an allowlist of keys, never filtered from the live file.
  $s = Get-Content (Join-Path $Source 'settings.json') -Raw | ConvertFrom-Json
  $out = [ordered]@{}
  foreach ($k in 'cleanupPeriodDays', 'env', 'model', 'language', 'alwaysThinkingEnabled', 'effortLevel') {
    if ($s.PSObject.Properties[$k]) { $out[$k] = $s.$k }
  }
  $perm = [ordered]@{}
  $perm.allow = @($s.permissions.allow | Where-Object { $_ -in $safeAllow })
  $perm.deny = @($s.permissions.deny | Where-Object { $_ -in $safeDeny })
  $perm.ask = @($s.permissions.ask)
  if ($s.permissions.defaultMode) { $perm.defaultMode = $s.permissions.defaultMode }
  $out.permissions = $perm
  $hooksOut = [ordered]@{}
  foreach ($ev in $s.hooks.PSObject.Properties) {
    $groups = foreach ($g in $ev.Value) {
      $keep = @($g.hooks | Where-Object { $cmd = $_.command; $hookFiles | Where-Object { $cmd -like "*$_*" } })
      if ($keep.Count) {
        $ng = [ordered]@{}
        if ($g.matcher) { $ng.matcher = $g.matcher }
        $ng.hooks = $keep
        $ng
      }
    }
    if ($groups) { $hooksOut[$ev.Name] = @($groups) }
  }
  $out.hooks = $hooksOut
  $settingsText = Hide-Home ($out | ConvertTo-Json -Depth 10)
  New-Item -ItemType Directory -Force (Join-Path $stage "$Flavor\examples") | Out-Null
  [IO.File]::WriteAllText((Join-Path $stage "$Flavor\examples\settings.example.json"), $settingsText, [Text.UTF8Encoding]::new($false))

  # CLAUDE.md: the live files mix in personal tooling and work notes, so neither is published.
  # One merged, generic template (tools/templates) covers both hosts; it still goes through the leak scan.
  if ($Flavor -eq 'windows') {
    Copy-Staged (Join-Path $PSScriptRoot 'templates\CLAUDE.example.md') 'shared\examples\CLAUDE.example.md' -Absolute
  }

  # Leak scan over the exact bytes about to be published.
  $patterns = @(
    '[A-Za-z]:[\\/]+Users[\\/]+(?!Public|Default|\{\{)[^\\/\s"]+',
    '/home/(?!\{\{)[a-z0-9_-]+',
    '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}',
    'op://', 'sk-[A-Za-z0-9]{20,}', 'ghp_[A-Za-z0-9]{20,}', '-----BEGIN [A-Z ]*PRIVATE KEY',
    '\b(?:10\.|192\.168\.|172\.(?:1[6-9]|2\d|3[01])\.)\d{1,3}\.\d{1,3}(?:\.\d{1,3})?\b'
  )
  $terms = @((Split-Path $HomePath -Leaf), $env:USERNAME)
  if (Test-Path $LocalDenylist) { $terms += Get-Content $LocalDenylist | Where-Object { $_ -and $_ -notmatch '^\s*#' } }
  $patterns += $terms | Where-Object { $_ } | ForEach-Object { [regex]::Escape($_) }

  $hits = foreach ($file in Get-ChildItem $stage -Recurse -File) {
    $i = 0
    foreach ($line in Get-Content $file.FullName) {
      $i++
      foreach ($p in $patterns) {
        $m = [regex]::Match($line, $p, 'IgnoreCase')
        if ($m.Success) { "{0}:{1}: {2}" -f $file.FullName.Substring($stage.Length + 1), $i, $m.Value }
      }
    }
  }
  if ($hits) {
    Write-Error ("LEAK SCAN FAILED, nothing published:`n" + (($hits | Select-Object -Unique) -join "`n")) -ErrorAction Continue
    exit 1
  }

  if (Get-Command gitleaks -ErrorAction SilentlyContinue) {
    & gitleaks detect --no-git --source $stage --no-banner --redact | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Error 'gitleaks flagged the export, nothing published' -ErrorAction Continue; exit 1 }
  } else {
    Write-Warning 'gitleaks not installed; only the built-in leak scan ran'
  }

  foreach ($d in $ownedDirs) {
    $dst = Join-Path $Dest $d
    if (Test-Path $dst) { Remove-Item $dst -Recurse -Force }
    Copy-Item (Join-Path $stage $d) $dst -Recurse
  }
  $n = (Get-ChildItem $stage -Recurse -File | Measure-Object).Count
  Write-Output "exported $n files to $Dest (leak scan clean)"
} finally {
  Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
}
