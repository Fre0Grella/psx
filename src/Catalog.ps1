<#
  Catalog.ps1 - what you can put in a pane.

  'run' decides whether the command is executed or merely typed:

    run = $true   send-keys "<cmd>" Enter   -> starts immediately
    run = $false  send-keys "<cmd>"         -> sits on the prompt, you press Enter

  Typed-not-run is the safer default for anything that builds, watches, or
  assumes a particular project (npm run dev in a repo with no package.json), and
  the better default for anything long-running you may not want yet.

  'needs' names the executable. The picker greys out entries whose program is
  missing rather than hiding them, so it stays obvious that the option exists.
#>

function Get-PsxCatalog {
  @(
    @{ key = 'claude';  label = 'Claude Code'; command = 'claude';             run = $true;  needs = 'claude'
       hint = 'starts Claude Code in this pane' }

    @{ key = 'shell';   label = 'shell';       command = '';                   run = $false; needs = $null
       hint = 'plain prompt, nothing typed' }

    @{ key = 'htop';    label = 'htop';        command = 'htop';               run = $true;  needs = 'htop'
       hint = 'process monitor' }

    @{ key = 'ssh';     label = 'ssh';         command = 'ssh {0}';            run = $true;  needs = 'ssh'
       prompt = 'host (user@host)'; hint = 'asks for the host' }

    @{ key = 'git';     label = 'git status';  command = 'git status';         run = $false; needs = 'git'
       hint = 'general git / gh pane' }

    @{ key = 'npm';     label = 'npm run dev'; command = 'npm run dev';        run = $false; needs = 'npm'
       hint = 'dev server, typed not run' }

    @{ key = 'build';   label = 'npm run build'; command = 'npm run build';    run = $false; needs = 'npm'
       hint = 'build, typed not run' }

    @{ key = 'pytest';  label = 'pytest';      command = 'uv run pytest -q';   run = $false; needs = 'uv'
       hint = 'typed not run' }

    @{ key = 'jupyter'; label = 'Jupyter Lab'; command = 'uv run jupyter lab'; run = $false; needs = 'uv'
       hint = 'typed not run' }

    @{ key = 'custom';  label = 'custom...';   command = '';                   run = $false; needs = $null
       hint = 'type your own command, then choose run or typed' }
  )
}

function Test-PsxAvailable {
  param($Entry)
  if (-not $Entry.needs) { return $true }
  [bool](Get-Command $Entry.needs -ErrorAction SilentlyContinue)
}

function Get-PsxCatalogEntry {
  param([string]$Key)
  Get-PsxCatalog | Where-Object { $_.key -eq $Key } | Select-Object -First 1
}
