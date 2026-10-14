$dir = Split-Path $MyInvocation.MyCommand.Path
$hook = "$env:USERPROFILE\.claude\hooks\codex-concurrency-gate.mjs"
$gate = "$env:USERPROFILE\.local\bin\codex-gate.mjs"
'setTimeout(() => process.exit(0), 90000);' | Set-Content "$dir\fake90.mjs" -Encoding ASCII
$env:CODEX_GATE_REAL = "$dir\fake90.mjs"
$holders = 1..2 | ForEach-Object { Start-Process node -ArgumentList $gate, 'exec', "case$_" -WindowStyle Hidden -PassThru }
$env:CODEX_GATE_REAL = $null
Start-Sleep 1
$cases = Get-Content "$dir\cases.json" -Raw | ConvertFrom-Json
$fail = 0
foreach ($c in $cases) {
    $json = @{ tool_name = $c.tool; tool_input = @{ command = $c.cmd } } | ConvertTo-Json -Compress
    $null = $json | & node $hook 2>&1
    $blocked = $LASTEXITCODE -eq 2
    $ok = $blocked -eq [bool]$c.block
    if (-not $ok) { $fail++ }
    '{0} {1,-10} want {2,-5} got {3,-5} {4}' -f $(if ($ok) { 'PASS' } else { 'FAIL' }), $c.tool, $c.block, $blocked, ($c.cmd -replace '\n', '\n')
}
$holders | Stop-Process -Force
"failures: $fail of $($cases.Count)"
