<#
  Plain test runner. No Pester: the version bundled with Windows here is 3.4.0,
  whose syntax differs enough from modern Pester that a test file would only run
  on this one machine. A dozen lines of asserts run anywhere.

  Usage:  pwsh -File tests\run.ps1
#>

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. "$root\src\Model.ps1"
. "$root\src\Render.ps1"
. "$root\src\Catalog.ps1"
. "$root\src\Store.ps1"
. "$root\src\Builder.ps1"
. "$root\src\Editor.ps1"

$script:Pass = 0; $script:Fail = 0

function ok {
  param([string]$What, [bool]$Cond, [string]$Detail = '')
  if ($Cond) { $script:Pass++; Write-Host "  ok   $What" -ForegroundColor DarkGreen }
  else { $script:Fail++; Write-Host "  FAIL $What" -ForegroundColor Red; if ($Detail) { Write-Host "       $Detail" -ForegroundColor DarkGray } }
}
function eq {
  param([string]$What, $Actual, $Expected)
  ok $What ($Actual -eq $Expected) "expected [$Expected] got [$Actual]"
}

function section { param([string]$N) Write-Host ''; Write-Host $N -ForegroundColor Cyan }

# ---------------------------------------------------------------- model
section 'model'

$l = New-PsxLayout 'test' 'desc'
eq 'new layout has one pane' @(Get-PsxPanes $l.root).Count 1
eq 'root starts as a pane' $l.root.type 'pane'

$rootId = $l.root.id
$second = Split-PsxPane $l $rootId 'h' 45
eq 'split makes two panes' @(Get-PsxPanes $l.root).Count 2
eq 'root became a split' $l.root.type 'split'
eq 'split direction kept' $l.root.dir 'h'
eq 'percent kept' $l.root.percent 45
eq 'original pane is child 0' $l.root.children[0].id $rootId
eq 'new pane is child 1' $l.root.children[1].id $second

$third = Split-PsxPane $l $second 'v' 50
eq 'three panes' @(Get-PsxPanes $l.root).Count 3
eq 'depth-first order: original first' @(Get-PsxPanes $l.root)[0].id $rootId

ok 'Find-PsxNode finds a pane' ((Find-PsxNode $l.root $third).id -eq $third)
ok 'Find-PsxNode misses cleanly' ($null -eq (Find-PsxNode $l.root 'nope'))
eq 'Find-PsxParent returns the owning split' (Find-PsxParent $l.root $third).dir 'v'
ok 'root pane has no parent' ($null -eq (Find-PsxParent $l.root $rootId) -eq $false)

Set-PsxPaneApp $l $rootId 'claude' 'claude' $true 'Claude Code' | Out-Null
eq 'app set' (Find-PsxNode $l.root $rootId).command 'claude'
eq 'run flag set' (Find-PsxNode $l.root $rootId).run $true

Set-PsxSplitPercent $l $third 20
eq 'resize applied' (Find-PsxParent $l.root $third).percent 70
Set-PsxSplitPercent $l $third 999
eq 'resize clamps at 90' (Find-PsxParent $l.root $third).percent 90
Set-PsxSplitPercent $l $third -999
eq 'resize clamps at 10' (Find-PsxParent $l.root $third).percent 10

$focus = Remove-PsxPane $l $third
eq 'delete leaves two panes' @(Get-PsxPanes $l.root).Count 2
ok 'delete returns a live pane to focus' ($null -ne (Find-PsxNode $l.root $focus))
$null = Remove-PsxPane $l $second
eq 'delete leaves one pane' @(Get-PsxPanes $l.root).Count 1
eq 'collapse restored the pane content' $l.root.command 'claude'
ok 'refuses to delete the last pane' ($null -eq (Remove-PsxPane $l $l.root.id))

# ---------------------------------------------------------------- array discipline
# A PowerShell trap that has already bitten this codebase twice: a function
# returning a single item unrolls it, so .Count reports the hashtable's KEY
# count (6) instead of 1. Wrapping every call in @() is the fix. Returning
# `, $array` instead looks equivalent and is not - it makes @() nest, so one
# pane and three panes stop behaving the same. These assertions pin both ends.
section 'array discipline'

$one = New-PsxLayout 'one'
eq 'one pane counts as 1, not its key count' @(Get-PsxPanes $one.root).Count 1
eq 'one rect counts as 1' @(Get-PsxRects $one.root 0 0 20 6).Count 1

$many = New-PsxLayout 'many'
$m2 = Split-PsxPane $many $many.root.id 'h' 50
$null = Split-PsxPane $many $m2 'v' 50
eq 'three panes count as 3' @(Get-PsxPanes $many.root).Count 3
eq 'three rects count as 3' @(Get-PsxRects $many.root 0 0 40 12).Count 3

$types = @(Get-PsxPanes $one.root) | ForEach-Object { $_.type }
eq 'enumerating yields nodes, not a nested array' ($types -join ',') 'pane'

$oneRects = @(Get-PsxRects $one.root 0 0 20 6)
eq 'rects enumerate as hashtables' $oneRects[0].w 20
ok 'no accidental array-of-array' (-not ($oneRects[0] -is [array]))

# ---------------------------------------------------------------- geometry
section 'geometry'

$g = New-PsxLayout 'g'
$b = Split-PsxPane $g $g.root.id 'h' 50
$rects = @(Get-PsxRects $g.root 0 0 61 20)
eq 'two rects' $rects.Count 2
eq 'left starts at 0' $rects[0].x 0
eq 'rects share one border column' ($rects[0].x + $rects[0].w - 1) $rects[1].x
eq 'widths cover the box' ($rects[0].w + $rects[1].w - 1) 61
eq 'full height each' $rects[0].h 20

$g2 = New-PsxLayout 'g2'
$b2 = Split-PsxPane $g2 $g2.root.id 'h' 25
$r2 = @(Get-PsxRects $g2.root 0 0 61 20)
ok 'percent sizes the SECOND child' ($r2[1].w -lt $r2[0].w) "left=$($r2[0].w) right=$($r2[1].w)"
eq 'second child gets ~25%' $r2[1].w 16

$g3 = New-PsxLayout 'g3'
$null = Split-PsxPane $g3 $g3.root.id 'v' 50
$r3 = @(Get-PsxRects $g3.root 0 0 61 21)
eq 'vertical shares a border row' ($r3[0].y + $r3[0].h - 1) $r3[1].y
eq 'heights cover the box' ($r3[0].h + $r3[1].h - 1) 21

# ---------------------------------------------------------------- render
section 'render'

$d = New-PsxLayout 'dev'
$right = Split-PsxPane $d $d.root.id 'h' 45
$rb = Split-PsxPane $d $right 'v' 50
Set-PsxPaneApp $d $d.root.children[0].id 'claude' 'claude' $true 'Claude Code' | Out-Null
$out = Format-PsxLayout $d 60 16
eq 'line count matches height' $out.Lines.Count 16
eq 'every line is the full width' (($out.Lines | ForEach-Object { $_.Length } | Sort-Object -Unique) -join ',') '60'
ok 'top-left corner drawn' ($out.Lines[0][0] -eq '┌')
ok 'top-right corner drawn' ($out.Lines[0][59] -eq '┐')
ok 'a T-junction appears where the vertical divider meets the top' (($out.Lines[0] -split '') -contains '┬')
ok 'a T-junction appears on the right edge' (($out.Lines -join '') -match '┤')
ok 'label rendered' (($out.Lines -join '') -match 'Claude Code')

# ---------------------------------------------------------------- navigation
section 'navigation'

$rects = $out.Rects
$ids = @($rects | ForEach-Object { $_.id })
$leftId = $ids[0]
$rightTop = $ids[1]
$rightBot = $ids[2]
eq 'right of left pane is the top-right pane' (Find-PsxNeighbour $rects $leftId 'right') $rightTop
eq 'down from top-right is bottom-right' (Find-PsxNeighbour $rects $rightTop 'down') $rightBot
eq 'left from bottom-right is the left pane' (Find-PsxNeighbour $rects $rightBot 'left') $leftId
ok 'nothing to the left of the left pane' ($null -eq (Find-PsxNeighbour $rects $leftId 'left'))
ok 'nothing above the top-right pane' ($null -eq (Find-PsxNeighbour $rects $rightTop 'up'))

# ---------------------------------------------------------------- store
section 'store'

ok 'accepts a sane name' (Test-PsxName 'my-layout_2')
ok 'rejects a dotted name' (-not (Test-PsxName 'my.layout'))
ok 'rejects an empty name' (-not (Test-PsxName ''))
ok 'rejects a leading dash' (-not (Test-PsxName '-x'))
ok 'rejects a name with a space' (-not (Test-PsxName 'my layout'))

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("psxtest-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$origHome = $HOME
try {
  Set-Variable -Name HOME -Value $tmp -Scope Global -Force
  $rt = New-PsxLayout 'roundtrip' 'a desc'
  $r2id = Split-PsxPane $rt $rt.root.id 'h' 30
  Set-PsxPaneApp $rt $r2id 'htop' 'htop' $true 'htop' | Out-Null
  $path = Export-PsxTemplate $rt
  ok 'template file written' (Test-Path $path)

  $back = Import-PsxTemplate 'roundtrip'
  eq 'name survives' $back.name 'roundtrip'
  eq 'desc survives' $back.desc 'a desc'
  eq 'shape survives' @(Get-PsxPanes $back.root).Count 2
  eq 'split dir survives' $back.root.dir 'h'
  eq 'percent survives' $back.root.percent 30
  eq 'command survives' $back.root.children[1].command 'htop'
  eq 'run flag survives as a real boolean' $back.root.children[1].run $true
  # A JSON round-trip must not turn the tree into read-only PSCustomObjects:
  # the editor reshapes nodes in place, so this is the check that -AsHashtable
  # is really doing its job.
  $mutable = $false
  try { $null = Split-PsxPane $back $back.root.children[0].id 'v' 50; $mutable = $true } catch { $mutable = $false }
  ok 'loaded template is still mutable' $mutable
  ok 'listing finds it' ((Get-PsxTemplateNames) -contains 'roundtrip')
  ok 'delete works' (Remove-PsxTemplate 'roundtrip')
  ok 'delete of a missing template is not an error' (-not (Remove-PsxTemplate 'roundtrip'))
}
finally {
  Set-Variable -Name HOME -Value $origHome -Scope Global -Force
  Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------- build plan
section 'build plan'

$bp = New-PsxLayout 'bp'
$bRight = Split-PsxPane $bp $bp.root.id 'h' 45
$bBot = Split-PsxPane $bp $bRight 'v' 50
Set-PsxPaneApp $bp $bp.root.children[0].id 'claude' 'claude' $true 'Claude' | Out-Null
Set-PsxPaneApp $bp $bBot 'npm' 'npm run dev' $false 'npm' | Out-Null

$plan = Get-PsxBuildPlan $bp
$splits = @($plan | Where-Object { $_.op -eq 'split' })
$sends = @($plan | Where-Object { $_.op -eq 'send' })
eq 'two splits for three panes' $splits.Count 2
eq 'first split is horizontal' $splits[0].dir 'h'
eq 'first split percent' $splits[0].percent 45
eq 'second split is vertical' $splits[1].dir 'v'
eq 'sends only for panes with a command' $sends.Count 2
ok 'claude is marked run' (($sends | Where-Object { $_.command -eq 'claude' }).run -eq $true)
ok 'npm is marked typed-not-run' (($sends | Where-Object { $_.command -eq 'npm run dev' }).run -eq $false)
ok 'every send targets a pane the plan created' (
  @($sends | Where-Object { $_.pane -notin @($plan | Where-Object { $_.op -in 'root','split' } | ForEach-Object { $_.result }) }).Count -eq 0
)

# ---------------------------------------------------------------- editor keys
# The editor's key handling lives in Invoke-PsxEditorAction precisely so it can
# be exercised without a console. Only the keys that open a prompt (enter, d, w,
# q) stay in the input loop, and those report Handled = $false.
section 'editor keys'

function Keys { param($L, $Sel, $Key)
  $r = @(Get-PsxRects $L.root 0 0 60 16)
  Invoke-PsxEditorAction $L $Sel $r $Key
}

$e = New-PsxLayout 'ed'
$a = Keys $e $e.root.id '\'
eq 'backslash splits side by side' $e.root.dir 'h'
eq 'split selects the new pane' $a.Sel $e.root.children[1].id
ok 'split marks the layout dirty' $a.Dirty

$b2 = Keys $e $a.Sel '-'
eq 'dash splits top and bottom' (Find-PsxParent $e.root $b2.Sel).dir 'v'
eq 'three panes now' @(Get-PsxPanes $e.root).Count 3

$before = (Find-PsxParent $e.root $b2.Sel).percent
$r1 = Keys $e $b2.Sel ']'
eq 'bracket grows the split' (Find-PsxParent $e.root $b2.Sel).percent ($before + 5)
$r2 = Keys $e $b2.Sel '['
eq 'bracket shrinks it back' (Find-PsxParent $e.root $b2.Sel).percent $before

$fk = Keys $e $b2.Sel 'f'
eq 'f records the focus pane' $e.focus $b2.Sel
ok 'f explains itself' ($fk.Msg -ne '')

$nav = Keys $e @(Get-PsxPanes $e.root)[0].id 'right'
eq 'right moves to the pane on the right' $nav.Sel @(Get-PsxPanes $e.root)[1].id
$navEdge = Keys $e @(Get-PsxPanes $e.root)[0].id 'left'
eq 'left at the edge stays put' $navEdge.Sel @(Get-PsxPanes $e.root)[0].id

$del = Keys $e $b2.Sel 'x'
eq 'x deletes a pane' @(Get-PsxPanes $e.root).Count 2
ok 'x leaves a live pane selected' ($null -ne (Find-PsxNode $e.root $del.Sel))

$solo = New-PsxLayout 'solo'
$lastDel = Keys $solo $solo.root.id 'x'
eq 'x refuses on the last pane' @(Get-PsxPanes $solo.root).Count 1
ok 'and says why' ($lastDel.Msg -match 'at least one')
ok 'refusal is not a change' (-not $lastDel.Dirty)

$unhandled = Keys $e @(Get-PsxPanes $e.root)[0].id 'w'
ok 'save is left to the input loop' (-not $unhandled.Handled)
$unhandled2 = Keys $e @(Get-PsxPanes $e.root)[0].id 'z'
ok 'an unknown key changes nothing' ((-not $unhandled2.Handled) -and (-not $unhandled2.Dirty))

# ---------------------------------------------------------------- done
Write-Host ''
if ($script:Fail -eq 0) {
  Write-Host "$script:Pass passed, 0 failed" -ForegroundColor Green
  exit 0
}
Write-Host "$script:Pass passed, $script:Fail FAILED" -ForegroundColor Red
exit 1
