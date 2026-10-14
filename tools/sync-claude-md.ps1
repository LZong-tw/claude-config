[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Target,
  [string]$Template = (Join-Path $PSScriptRoot 'templates\CLAUDE.example.md')
)
$ErrorActionPreference = 'Stop'
$begin = '<!-- claude-config:shared:begin (edit tools/templates/CLAUDE.example.md in the claude-config repo, then rerun tools/sync-claude-md.ps1) -->'
$end = '<!-- claude-config:shared:end -->'

# Everything above the first "## " heading is the example's own title and intro, not shared rules.
$tpl = [IO.File]::ReadAllText($Template)
$body = $tpl.Substring($tpl.IndexOf("`n## ") + 1).TrimEnd()

$raw = [IO.File]::ReadAllText($Target)
$eol = if ($raw.Contains("`r`n")) { "`r`n" } else { "`n" }
$block = ($begin + "`n" + $body + "`n" + $end) -replace "`r?`n", $eol

$pattern = '(?s)<!-- claude-config:shared:begin.*?<!-- claude-config:shared:end -->'
if ($raw -notmatch $pattern) { throw "no shared block markers in $Target; add the begin/end comment pair where the block belongs" }
$new = [regex]::Replace($raw, $pattern, { param($m) $block })
if ($new -eq $raw) { Write-Output "unchanged: $Target"; return }
[IO.File]::WriteAllText($Target, $new, [Text.UTF8Encoding]::new($false))
Write-Output "synced: $Target"
