$hook = (Resolve-Path (Join-Path $PSScriptRoot '..\..\session-healthcheck.cjs')).Path
$fail = 0
function Check($name, $envs, [scriptblock]$assert) {
  $saved = @{}
  foreach ($k in $envs.Keys) { $saved[$k] = [Environment]::GetEnvironmentVariable($k); [Environment]::SetEnvironmentVariable($k, $envs[$k]) }
  $sw = [Diagnostics.Stopwatch]::StartNew()
  $out = (node $hook | Out-String)
  $code = $LASTEXITCODE; $ms = $sw.ElapsedMilliseconds
  foreach ($k in $envs.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k]) }
  $ok = ($code -eq 0) -and ($ms -lt 4000) -and (& $assert $out)
  if (-not $ok) { $script:fail++ }
  Write-Output ("{0} {1} ({2} ms, exit {3})`n{4}" -f ($(if ($ok) { 'PASS' } else { 'FAIL' })), $name, $ms, $code, $out)
}

# Healthy machine: silent.
Check "healthy is silent" @{} { param($o) $o.Trim() -eq "" }
# Each broken dependency must be named; the others must not be.
Check "missing bash" @{ HEALTHCHECK_BASH = "no-such-bash-xyz" } { param($o) $o -match "bash broken" -and $o -notmatch "rtk|pxpipe" }
Check "missing rtk" @{ HEALTHCHECK_RTK = "no-such-rtk-xyz" } { param($o) $o -match "rtk unavailable" -and $o -notmatch "bash|pxpipe" }
Check "pxpipe down" @{ HEALTHCHECK_PXPIPE_PORT = "1" } { param($o) $o -match "pxpipe proxy not listening" -and $o -notmatch "bash|rtk" }

if ($fail) { Write-Output "$fail FAILED"; exit 1 } else { Write-Output "ALL PASS" }
