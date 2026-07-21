<#
  Cli.ps1 - argument handling and the top-level commands.

  Design rule inherited from the shell script this replaces: nothing needs
  Shift. Every command has a bare verb and a short flag, and verb order does not
  matter (`psx kill dev` and `psx dev kill` are the same). Short flags are
  explicit aliases rather than prefixes, because '-l' would otherwise be
  ambiguous between -Layout and -List and PowerShell would refuse to bind it.
#>

$script:PsxVerbs = @{
  'ls' = 'list'; 'l' = 'list'; 'list' = 'list'
  'new' = 'new'; 'n' = 'new'; 'create' = 'new'
  'edit' = 'edit'; 'e' = 'edit'
  'delete' = 'delete'; 'del' = 'delete'; 'rm' = 'delete'
  'kill' = 'kill'; 'k' = 'kill'; 'x' = 'kill'; 'stop' = 'kill'
  'help' = 'help'; 'h' = 'help'
}

function Get-PsxSessions {
  # "name: N windows (created ...) [WxH] (attached)" -> just the names.
  @(psmux list-sessions 2>&1 |
      Where-Object { $_ -match '^([^:]+):' } |
      ForEach-Object { $Matches[1] })
}

function Get-PsxDefaultName {
  param([string]$Dir)
  (Split-Path $Dir -Leaf) -replace '[^\w\-]', '-'
}

function Show-PsxList {
  $here = Get-PsxDefaultName (Get-Location).Path
  $live = Get-PsxSessions
  $names = @(Get-PsxTemplateNames)

  Write-Host ''
  Write-Host '  templates' -ForegroundColor Cyan
  if ($names.Count -eq 0) {
    Write-Host '    (none yet - psx new)' -ForegroundColor DarkGray
  }
  foreach ($n in $names) {
    $t = Import-PsxTemplate $n
    $count = @(Get-PsxPanes $t.root).Count
    Write-Host ('    {0,-12} {1,-2} panes  {2}' -f $n, $count, $t.desc)
  }

  Write-Host ''
  Write-Host '  running' -ForegroundColor Cyan
  if ($live.Count -eq 0) {
    Write-Host '    (no server running)' -ForegroundColor DarkGray
  }
  else {
    foreach ($n in $live) {
      $tag = if ($n -eq $here) { '  <- this folder' } else { '' }
      Write-Host ('    {0}{1}' -f $n, $tag) -ForegroundColor Green
    }
  }

  Write-Host ''
  Write-Host '  psx <template>   open it here      psx -h   full usage' -ForegroundColor DarkGray
  Write-Host ''
}

function Show-PsxUsage {
  Write-Host ''
  Write-Host '  psx - named psmux layouts' -ForegroundColor Cyan
  Write-Host ''
  Write-Host '  COMMANDS' -ForegroundColor Cyan
  Write-Host '    psx <template>      build it in the current folder, then attach'
  Write-Host '                        already running? it just attaches, so re-running is safe'
  Write-Host '    psx ls              templates and running sessions'
  Write-Host '    psx new [name]      draw a new template in the editor'
  Write-Host '    psx edit <name>     change one'
  Write-Host '    psx delete <name>   remove one'
  Write-Host '    psx kill [name]     kill a session; no name kills the one for this folder'
  Write-Host '    psx kill all        kill every session (stops the server)'
  Write-Host '    psx -h              this screen'
  Write-Host ''
  Write-Host '  OPTIONS' -ForegroundColor Cyan
  Write-Host '    -p <dir>            build somewhere other than the current folder'
  Write-Host '    -n <name>           session name (default: the folder name)'
  Write-Host '    -d                  build it but do not attach'
  Write-Host ''
  Write-Host '  SHORTHAND' -ForegroundColor Cyan
  Write-Host '    Nothing needs Shift. Verb order does not matter.'
  Write-Host '      list    psx ls   psx l   psx -l'
  Write-Host '      new     psx new   psx n'
  Write-Host '      edit    psx edit dev   psx e dev   psx dev e'
  Write-Host '      delete  psx delete dev   psx rm dev'
  Write-Host '      kill    psx k dev   psx dev k   psx dev -k'
  Write-Host ''
  Write-Host '  EDITOR KEYS' -ForegroundColor Cyan
  Write-Host '    arrows  move between panes        \  split side by side'
  Write-Host '    enter   choose what runs here     -  split top and bottom'
  Write-Host '    x       delete pane               [ ] resize'
  Write-Host '    f       focus this pane on open   d  description'
  Write-Host '    w       save                      q  quit'
  Write-Host ''
  Write-Host "  Templates live in $(Join-Path $HOME '.psx\templates') as plain JSON." -ForegroundColor DarkGray
  Write-Host ''
}

function Invoke-PsxNew {
  param([string]$Name)

  while (-not (Test-PsxName $Name)) {
    Clear-Host
    Write-Host ''
    Write-Host '  new template' -ForegroundColor Cyan
    Write-Host '  letters, digits, - and _ only' -ForegroundColor DarkGray
    $Name = Read-PsxLineInput 'name'
    if (-not $Name) { Write-Host '  cancelled' -ForegroundColor DarkGray; return }
    if (-not (Test-PsxName $Name)) { continue }
    if (Import-PsxTemplate $Name) {
      Write-Host ''
      Write-Host "  '$Name' already exists - use  psx edit $Name" -ForegroundColor Yellow
      Start-Sleep -Milliseconds 1200
      $Name = ''
    }
  }

  $layout = New-PsxLayout $Name
  Clear-Host
  if (Invoke-PsxEditor $layout) {
    Write-Host "template '$Name' saved. open it with:  psx $Name" -ForegroundColor Green
  }
  else {
    Write-Host "'$Name' not saved" -ForegroundColor DarkGray
  }
}

function Invoke-PsxEdit {
  param([string]$Name)
  if (-not $Name) { Write-Host 'which template? try  psx ls' -ForegroundColor Yellow; return }
  $layout = Import-PsxTemplate $Name
  if (-not $layout) {
    Write-Host "no template '$Name'" -ForegroundColor Yellow
    Show-PsxList
    return
  }
  Clear-Host
  if (Invoke-PsxEditor $layout) { Write-Host "template '$Name' saved" -ForegroundColor Green }
  else { Write-Host "'$Name' unchanged" -ForegroundColor DarkGray }
}

function Invoke-PsxDelete {
  param([string]$Name)
  if (-not $Name) { Write-Host 'which template? try  psx ls' -ForegroundColor Yellow; return }
  $layout = Import-PsxTemplate $Name
  if (-not $layout) { Write-Host "no template '$Name'" -ForegroundColor Yellow; return }

  Write-Host ''
  Write-Host "  delete template '$Name'? ($(@(Get-PsxPanes $layout.root).Count) panes - $($layout.desc))" -ForegroundColor Yellow
  Write-Host '  [y] delete    anything else cancels' -ForegroundColor DarkGray
  if ((Read-PsxKey) -ne 'y') { Write-Host '  cancelled' -ForegroundColor DarkGray; return }

  if (Remove-PsxTemplate $Name) { Write-Host "  deleted '$Name'" -ForegroundColor DarkGray }
}

function Invoke-PsxKill {
  param([string]$Target)

  if ($Target -eq 'all') {
    $live = Get-PsxSessions
    if ($live.Count -eq 0) { Write-Host 'nothing running' -ForegroundColor DarkGray; return }
    psmux kill-server 2>&1 | Out-Null
    Write-Host ("killed {0} session(s): {1}" -f $live.Count, ($live -join ', ')) -ForegroundColor DarkGray
    return
  }

  if (-not $Target) { $Target = Get-PsxDefaultName (Get-Location).Path }

  psmux has-session -t $Target 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) {
    Write-Host "no session '$Target'" -ForegroundColor Yellow
    $live = Get-PsxSessions
    if ($live.Count) { Write-Host ('  running: ' + ($live -join ', ')) -ForegroundColor DarkGray }
    return
  }
  psmux kill-session -t $Target 2>&1 | Out-Null
  Write-Host "killed session '$Target'" -ForegroundColor DarkGray
}

function Invoke-PsxBuild {
  param([string]$Template, [string]$Dir, [string]$SessionName, [switch]$NoAttach)

  $layout = Import-PsxTemplate $Template
  if (-not $layout) {
    Write-Host "no template '$Template'" -ForegroundColor Red
    Show-PsxList
    return
  }

  $D = (Resolve-Path $Dir).Path
  $S = if ($SessionName) { $SessionName } else { Get-PsxDefaultName $D }

  # Idempotent: already there? just go.
  psmux has-session -t $S 2>&1 | Out-Null
  if ($LASTEXITCODE -eq 0) {
    Write-Host "session '$S' already exists - attaching" -ForegroundColor DarkGray
    if (-not $NoAttach) { psmux attach -t $S }
    return
  }

  Write-Host "building '$Template' in $D" -ForegroundColor Cyan
  $plan = Get-PsxBuildPlan $layout
  Invoke-PsxBuildPlan $plan $S $D | Out-Null
  Write-Host "session '$S' ready" -ForegroundColor Green
  if (-not $NoAttach) { psmux attach -t $S }
}
