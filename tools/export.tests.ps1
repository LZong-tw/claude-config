$export = Join-Path $PSScriptRoot 'export.ps1'
$fail = 0

function New-FakeSource([hashtable]$extra = @{}) {
  $src = Join-Path ([IO.Path]::GetTempPath()) ("fake-claude-" + [guid]::NewGuid())
  $home_ = 'C:\Users\Someone'
  $files = @{
    'settings.json' = (@{
      model = 'sonnet'; env = @{ ENABLE_TOOL_SEARCH = 'true' }
      autoMode = @{ environment = @('Trusted repo at C:\Users\Someone') }
      permissions = @{
        allow = @('Bash(git status:*)', 'WebFetch(domain:api.example-private.test)')
        deny = @('Read(.env)'); ask = @(); defaultMode = 'auto'
      }
      hooks = @{ Stop = @(
        @{ hooks = @(@{ type = 'command'; command = 'node "C:/Users/Someone/.claude/hooks/session-healthcheck.cjs"' }) },
        @{ hooks = @(@{ type = 'command'; command = 'C:/Users/Someone/.orca/agent-hooks/claude-hook.cmd' }) }
      ) }
    } | ConvertTo-Json -Depth 10)
    'CLAUDE.md' = "# Rules`n`n@RTK.md`n`n<posthog>`nuse posthog`n</posthog>`n"
    'scripts\daily-watchdog.ps1' = '$dir = Join-Path $env:USERPROFILE ".claude"'
    'hooks\tests\codex-gate\cases.json' = '[]'
    'hooks\tests\session-healthcheck\run.ps1' = 'Write-Output ok'
  }
  foreach ($h in 'codex-concurrency-gate.mjs', 'bash-ps-syntax-guard.cjs', 'cleanup-serena.cjs', 'session-healthcheck.cjs') { $files["hooks\$h"] = '// hook' }
  foreach ($s in 'merge-pr', 'handoff', 'diagnose-readonly', 'survey', 'converge-pr') { $files["skills\$s\SKILL.md"] = "---`nname: $s`n---`nbody" }
  foreach ($k in $extra.Keys) { $files[$k] = $extra[$k] }
  foreach ($k in $files.Keys) {
    $p = Join-Path $src $k
    New-Item -ItemType Directory -Force (Split-Path $p) | Out-Null
    Set-Content -Path $p -Value $files[$k] -Encoding utf8NoBOM
  }
  $src
}

function Invoke-Export($src, $flavor = 'windows', $homePath = 'C:\Users\Someone') {
  $dest = Join-Path ([IO.Path]::GetTempPath()) ("fake-dest-" + [guid]::NewGuid())
  New-Item -ItemType Directory -Force $dest | Out-Null
  $deny = Join-Path $dest 'deny.txt'
  Set-Content $deny 'example-private.test'
  $log = pwsh -NoProfile -File $export -Flavor $flavor -Source $src -Dest $dest -HomePath $homePath -LocalDenylist $deny 2>&1 | Out-String
  [pscustomobject]@{ Code = $LASTEXITCODE; Dest = $dest; Log = $log }
}

function Check($name, [bool]$ok, $detail = '') {
  if (-not $ok) { $script:fail++ }
  Write-Output ("{0} {1} {2}" -f $(if ($ok) { 'PASS' } else { 'FAIL' }), $name, $detail)
}

# Clean tree: exports, and the private bits are gone while the useful bits stay.
$r = Invoke-Export (New-FakeSource)
$settings = Get-Content (Join-Path $r.Dest 'windows\examples\settings.example.json') -Raw -ErrorAction SilentlyContinue
$md = Get-Content (Join-Path $r.Dest 'windows\examples\CLAUDE.example.md') -Raw -ErrorAction SilentlyContinue
Check 'clean tree exports' ($r.Code -eq 0) $r.Log
Check 'autoMode dropped' ($settings -and $settings -notmatch 'autoMode|Trusted repo')
Check 'private allow rule dropped' ($settings -and $settings -notmatch 'example-private')
Check 'generic allow rule kept' ($settings -and $settings -match 'git status')
Check 'third-party hook dropped' ($settings -and $settings -notmatch 'orca')
Check 'home path replaced' ($settings -and $settings -match '\{\{HOME\}\}/\.claude/hooks/session-healthcheck\.cjs' -and $settings -notmatch 'Someone')
Check 'RTK import and posthog dropped' ($md -and $md -notmatch 'RTK|posthog')

# Leaks in files that are copied verbatim must stop the export and leave dest untouched.
$cases = @{
  'foreign user path' = @{ 'hooks\session-healthcheck.cjs' = 'const p = "C:\Users\Bob\notes.txt";' }
  'email address'     = @{ 'scripts\daily-watchdog.ps1' = '# contact bob@corp.example.com' }
  'local denylist term' = @{ 'skills\survey\SKILL.md' = 'check api.example-private.test status' }
  'private key'       = @{ 'hooks\cleanup-serena.cjs' = '-----BEGIN RSA PRIVATE KEY-----' }
}
foreach ($name in $cases.Keys) {
  $r = Invoke-Export (New-FakeSource $cases[$name])
  Check "blocks $name" ($r.Code -ne 0 -and -not (Test-Path (Join-Path $r.Dest 'windows')))
}

# WSL flavor: only the generic hook and skill ship; infra-specific skills, the vendor-injected hooks
# and the work-flavored CLAUDE.md must stay home.
function New-FakeWslSource([hashtable]$extra = @{}) {
  $src = Join-Path ([IO.Path]::GetTempPath()) ("fake-wsl-" + [guid]::NewGuid())
  $injected = 'if [ -z "${HOME-}" ]; then printf x; fi; "/home/someone/.orca/agent-hooks/claude-hook.sh"'
  $files = @{
    'settings.json' = (@{
      model = 'opus'; env = @{ ENABLE_TOOL_SEARCH = 'true' }
      permissions = @{ allow = @('WebSearch', 'mcp__sentry__search_issues', 'Bash(glab mr:*)'); deny = @(); ask = @(); defaultMode = 'auto' }
      hooks = @{
        Stop = @(@{ hooks = @(@{ type = 'command'; command = $injected }) })
        PreToolUse = @(@{ matcher = 'Bash'; hooks = @(@{ type = 'command'; command = 'python3 ~/.claude/hooks/bash_guard.py' }) })
      }
    } | ConvertTo-Json -Depth 10)
    'CLAUDE.md' = 'Rollouts: break down per host web-01 web-02'
    'hooks\bash_guard.py' = '# guard'
    'skills\parallel-fix\SKILL.md' = "---`nname: parallel-fix`n---`nbody"
    'skills\ramp-controller\SKILL.md' = 'targets web-01 192.168.152.244'
    'skills\incident\SKILL.md' = 'vault under ~/.config/private-garden'
    'skills\ship\SKILL.md' = 'ship'
  }
  foreach ($k in $extra.Keys) { $files[$k] = $extra[$k] }
  foreach ($k in $files.Keys) {
    $p = Join-Path $src $k
    New-Item -ItemType Directory -Force (Split-Path $p) | Out-Null
    Set-Content -Path $p -Value $files[$k] -Encoding utf8NoBOM
  }
  $src
}
$r = Invoke-Export (New-FakeWslSource) 'wsl' '/home/someone'
$ws = Get-Content (Join-Path $r.Dest 'wsl\examples\settings.example.json') -Raw -ErrorAction SilentlyContinue
$shipped = if (Test-Path (Join-Path $r.Dest 'wsl')) { (Get-ChildItem (Join-Path $r.Dest 'wsl') -Recurse -File | ForEach-Object { $_.FullName }) -join "`n" } else { '' }
Check 'wsl exports' ($r.Code -eq 0) $r.Log
Check 'wsl keeps generic hook and skill' ($shipped -match 'bash_guard\.py' -and $shipped -match 'parallel-fix')
Check 'wsl drops infra skills and CLAUDE.md' ($shipped -notmatch 'ramp-controller|incident|ship|CLAUDE')
Check 'wsl drops vendor-injected hook' ($ws -and $ws -notmatch 'orca|HOME-')
Check 'wsl keeps bash_guard hook entry' ($ws -and $ws -match 'bash_guard\.py')
Check 'wsl drops work-only allow rules' ($ws -and $ws -notmatch 'sentry|glab')
$r = Invoke-Export (New-FakeWslSource @{ 'hooks\bash_guard.py' = '# talks to 192.168.152.244' }) 'wsl' '/home/someone'
Check 'wsl blocks internal IP' ($r.Code -ne 0 -and -not (Test-Path (Join-Path $r.Dest 'wsl')))
$r = Invoke-Export (New-FakeWslSource @{ 'skills\parallel-fix\SKILL.md' = 'see /home/bob/notes' }) 'wsl' '/home/someone'
Check 'wsl blocks foreign home path' ($r.Code -ne 0 -and -not (Test-Path (Join-Path $r.Dest 'wsl')))

if ($fail) { Write-Output "$fail FAILED"; exit 1 } else { Write-Output 'ALL PASS' }
