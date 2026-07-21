<#
.SYNOPSIS
  psx - named psmux layouts, with a visual editor.

.DESCRIPTION
  Draw a workspace once, open it with one word. Templates are JSON in
  ~/.psx/templates and are never touched by updates to this repo.

.EXAMPLE
  psx new              draw a new template
  psx dev              build it here and attach
  psx ls               templates and running sessions
  psx edit dev         change it
  psx delete dev       remove it
  psx kill dev         kill that session
  psx -h               full usage
#>
[CmdletBinding()]
param(
  [Parameter(Position = 0)][string]$Template,
  [Parameter(Position = 1)][string]$Action,

  [Alias('p', 'dir')][string]$Path = (Get-Location).Path,
  [Alias('n', 's')]  [string]$Name,

  # Short flags are explicit aliases, not prefixes. '-l' would otherwise be
  # ambiguous with -Template's old name and PowerShell would refuse to bind it;
  # an exact alias match always beats prefix matching.
  [Alias('k', 'x')]  [switch]$Kill,
  [Alias('l')]       [switch]$List,
  [Alias('d')]       [switch]$NoAttach,
  [Alias('h')]       [switch]$Help
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent

. "$root\src\Model.ps1"
. "$root\src\Render.ps1"
. "$root\src\Catalog.ps1"
. "$root\src\Store.ps1"
. "$root\src\Builder.ps1"
. "$root\src\Editor.ps1"
. "$root\src\Cli.ps1"

Initialize-PsxTemplates (Join-Path $root 'templates')

# --------------------------------------------------------------------------
# Resolve the verb first, whichever position it turned up in.
# --------------------------------------------------------------------------
$verb = $null
$target = $null

if ($Template -and $script:PsxVerbs.ContainsKey($Template.ToLower())) {
  # psx ls   /   psx kill dev   /   psx edit dev
  $verb = $script:PsxVerbs[$Template.ToLower()]
  $target = $Action
}
elseif ($Action -and $script:PsxVerbs.ContainsKey($Action.ToLower())) {
  # psx dev kill
  $verb = $script:PsxVerbs[$Action.ToLower()]
  $target = $Template
}

# Flags say the same thing as the verbs; either spelling is fine.
if ($Kill) { $verb = 'kill'; if (-not $target) { $target = $Template } }
if ($List) { $verb = 'list' }
if ($Help) { $verb = 'help' }
if (-not $verb -and -not $Template) { $verb = 'list' }

switch ($verb) {
  'help'   { Show-PsxUsage; return }
  'list'   { Show-PsxList; return }
  'new'    { Invoke-PsxNew $target; return }
  'edit'   { Invoke-PsxEdit $target; return }
  'delete' { Invoke-PsxDelete $target; return }
  'kill'   { Invoke-PsxKill $(if ($Name) { $Name } else { $target }); return }
}

Invoke-PsxBuild -Template $Template -Dir $Path -SessionName $Name -NoAttach:$NoAttach
