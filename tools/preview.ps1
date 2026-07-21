<#
  Prints a template exactly as the editor draws it, without the editor.
  Useful for eyeballing a layout, and for checking rendering changes in a
  terminal that cannot run the interactive loop.

    pwsh -File tools\preview.ps1 dev
#>
param([string]$Name = 'dev', [int]$Width = 66, [int]$Height = 16)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. "$root\src\Model.ps1"
. "$root\src\Render.ps1"
. "$root\src\Store.ps1"

$t = Import-PsxTemplate $Name
if (-not $t) { Write-Host "no template '$Name'"; exit 1 }

$r = Format-PsxLayout $t $Width $Height
Write-Host ''
Write-Host "  psx  -  $($t.name)" -ForegroundColor Cyan
Write-Host "  $($t.desc)" -ForegroundColor DarkGray
Write-Host ''
foreach ($line in $r.Lines) { Write-Host "  $line" -ForegroundColor DarkGray }
Write-Host ''
foreach ($rect in @($r.Rects)) {
  $n = $rect.node
  $what = if ($n.command) { "$($n.command)  [$(if ($n.run) { 'runs' } else { 'typed' })]" } else { 'plain shell' }
  $f = if ($t.focus -eq $n.id) { ' <- focused' } else { '' }
  Write-Host ("  {0,-3} {1,-14} {2}{3}" -f $n.id, $n.label, $what, $f) -ForegroundColor Gray
}
Write-Host ''
