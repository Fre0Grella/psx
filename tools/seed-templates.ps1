<#
  Regenerates the starter templates in templates/.

  Written through the model rather than by hand so the JSON can never drift from
  a shape the loader accepts. Run after changing the schema:

    pwsh -File tools\seed-templates.ps1
#>

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. "$root\src\Model.ps1"
. "$root\src\Store.ps1"

# Write into the repo's templates/ folder, not the user's ~/.psx.
function Save { param($L)
  $p = Join-Path $root "templates\$($L.name).json"
  $L | ConvertTo-Json -Depth 30 | Set-Content $p -Encoding utf8
  Write-Host "  $p"
}

# --- dev -------------------------------------------------------------------
$dev = New-PsxLayout 'dev' 'Claude Code left, git and dev server right'
$right = Split-PsxPane $dev $dev.root.id 'h' 45
$rightBottom = Split-PsxPane $dev $right 'v' 50
Set-PsxPaneApp $dev $dev.root.children[0].id 'claude' 'claude' $true 'Claude Code' | Out-Null
Set-PsxPaneApp $dev $right 'git' 'git status' $false 'git' | Out-Null
Set-PsxPaneApp $dev $rightBottom 'npm' 'npm run dev' $false 'dev server' | Out-Null
$dev.focus = $dev.root.children[0].id
Save $dev

# --- simple ----------------------------------------------------------------
# Two starters only, on purpose: one worked example and one blank canvas. More
# would be guessing at workflows, and every one of them is a file the user has
# to delete before `psx ls` reads as theirs.
$s = New-PsxLayout 'simple' 'two shells side by side'
$null = Split-PsxPane $s $s.root.id 'h' 50
Save $s
