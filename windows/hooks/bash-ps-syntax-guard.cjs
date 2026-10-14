'use strict';

// Claude's Bash tool only. The settings.json command must not contain `$`:
// Grok treats every `$name` as a required environment variable and skips the
// hook (`$null` in a regex becomes the missing variable `${null}`).

async function readStdin() {
  const chunks = [];
  for await (const chunk of process.stdin) chunks.push(chunk);
  if (chunks.length === 0) return {};
  try {
    return JSON.parse(Buffer.concat(chunks).toString('utf8'));
  } catch {
    return {};
  }
}

function toolName(input) {
  return String(input.tool_name || input.toolName || '');
}

function commandOf(input) {
  const bag = input.tool_input || input.toolInput || {};
  return typeof bag.command === 'string' ? bag.command : '';
}

const POWERSHELL_IN_BASH = /\$null|Get-Process|Get-ChildItem|Write-Host/;

async function main() {
  const input = await readStdin();
  if (toolName(input) !== 'Bash') process.exit(0);
  if (!POWERSHELL_IN_BASH.test(commandOf(input))) process.exit(0);
  process.stderr.write(
    'PowerShell syntax in Bash tool. Use: powershell.exe -NoProfile -Command "..."\n',
  );
  process.exit(2);
}

main().catch(() => process.exit(0));
