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

# --- build -----------------------------------------------------------------
$b = New-PsxLayout 'build' 'editor left, build and test right'
$bRight = Split-PsxPane $b $b.root.id 'h' 50
$bBottom = Split-PsxPane $b $bRight 'v' 50
Set-PsxPaneApp $b $b.root.children[0].id 'npm' 'npm run dev' $false 'dev server' | Out-Null
Set-PsxPaneApp $b $bRight 'build' 'npm run build' $false 'build' | Out-Null
Set-PsxPaneApp $b $bBottom 'custom' 'npm test -- --watch' $false 'tests' | Out-Null
$b.focus = $b.root.children[0].id
Save $b

# --- quantum ---------------------------------------------------------------
$q = New-PsxLayout 'quantum' 'Jupyter left, pytest and a shell right'
$qRight = Split-PsxPane $q $q.root.id 'h' 45
$qBottom = Split-PsxPane $q $qRight 'v' 50
Set-PsxPaneApp $q $q.root.children[0].id 'jupyter' 'uv run jupyter lab' $false 'Jupyter' | Out-Null
Set-PsxPaneApp $q $qRight 'pytest' 'uv run pytest -q' $false 'pytest' | Out-Null
$q.focus = $qBottom
Save $q

# --- simple ----------------------------------------------------------------
$s = New-PsxLayout 'simple' 'two shells side by side'
$null = Split-PsxPane $s $s.root.id 'h' 50
Save $s
