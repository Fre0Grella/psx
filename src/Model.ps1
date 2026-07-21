<#
  Model.ps1 - the layout tree.

  A layout is a binary split tree, the same shape psmux itself uses:

      split(h,45)
       |-- pane "claude"
       `-- split(v,50)
            |-- pane "git status"
            `-- pane "npm run dev"

  Node shapes (plain hashtables so ConvertTo-Json just works):

    pane  @{ type='pane';  id='p3'; app='claude'; command='claude'; run=$true; label='Claude' }
    split @{ type='split'; dir='h'|'v'; percent=45; children=@(nodeA, nodeB) }

  'dir' matches the psmux flag: 'h' = side by side, 'v' = stacked.
  'percent' is the share taken by children[1] - the SECOND child - because that
  is what `split-window -p N` gives the newly created pane. Getting this
  backwards is the easiest way to build a mirrored layout, so it is asserted in
  the tests rather than left to memory.

  Everything here is pure: no psmux calls, no console output. That is what makes
  it testable without a terminal.
#>

$script:NextPaneId = 0

function New-PsxPane {
  param(
    [string]$App = 'shell',
    [string]$Command = '',
    [bool]$Run = $false,
    [string]$Label = 'shell'
  )
  $script:NextPaneId++
  @{
    type    = 'pane'
    id      = "p$script:NextPaneId"
    app     = $App
    command = $Command
    run     = $Run
    label   = $Label
  }
}

function New-PsxLayout {
  param([string]$Name, [string]$Desc = '')
  @{
    name    = $Name
    desc    = $Desc
    version = 1
    root    = New-PsxPane
  }
}

function Get-PsxPanes {
  <#
    Depth-first, left child first. This order IS the build order: it matches the
    sequence psmux creates panes in when Builder walks the same tree.

    ONE RULE FOR CALLERS: always wrap the call in @().

    PowerShell unrolls returned collections, so with a single pane this hands
    back a bare hashtable and .Count then reports its number of KEYS (6) rather
    than 1. @() makes that correct.

    Returning `, $array` to force an array looks like it fixes this and does
    not: the function then emits one object, so @() wraps it a second time and
    every caller silently gets an array-of-array. Unrolled + @() is the only
    combination that behaves the same for one pane and for many.
  #>
  param($Node)
  $acc = [Collections.ArrayList]::new()
  Collect-PsxPanes $Node $acc
  $acc.ToArray()
}

function Collect-PsxPanes {
  param($Node, $Acc)
  if ($null -eq $Node) { return }
  if ($Node.type -eq 'pane') { [void]$Acc.Add($Node); return }
  Collect-PsxPanes $Node.children[0] $Acc
  Collect-PsxPanes $Node.children[1] $Acc
}

function Find-PsxNode {
  # Returns the pane hashtable with this id (the live object, not a copy, so
  # callers can mutate it in place).
  param($Node, [string]$Id)
  if ($null -eq $Node) { return $null }
  if ($Node.type -eq 'pane') { if ($Node.id -eq $Id) { return $Node } else { return $null } }
  $a = Find-PsxNode $Node.children[0] $Id
  if ($a) { return $a }
  Find-PsxNode $Node.children[1] $Id
}

function Find-PsxParent {
  # Returns the split node that directly contains $Id, or $null if $Id is the root.
  param($Node, [string]$Id)
  if ($null -eq $Node -or $Node.type -ne 'split') { return $null }
  foreach ($c in $Node.children) {
    if ($c.type -eq 'pane' -and $c.id -eq $Id) { return $Node }
  }
  $a = Find-PsxParent $Node.children[0] $Id
  if ($a) { return $a }
  Find-PsxParent $Node.children[1] $Id
}

function Split-PsxPane {
  <#
    Replace pane $Id with a split holding the original pane plus a new one.
    Mutates $Layout in place. Returns the new pane's id.

    The original pane keeps its position (left / top); the new pane takes
    $Percent of the space on the right / bottom, matching split-window -p.
  #>
  param(
    $Layout,
    [string]$Id,
    [ValidateSet('h', 'v')][string]$Dir,
    [int]$Percent = 50
  )

  $target = Find-PsxNode $Layout.root $Id
  if (-not $target) { throw "no pane '$Id'" }

  $fresh = New-PsxPane
  # Copy the target's contents into a sibling, then convert the target node
  # itself into the split. Rewriting the node in place means the caller's
  # reference to the root stays valid even when splitting the root.
  $keep = @{
    type = 'pane'; id = $target.id; app = $target.app
    command = $target.command; run = $target.run; label = $target.label
  }

  $target.Remove('id'); $target.Remove('app'); $target.Remove('command')
  $target.Remove('run'); $target.Remove('label')
  $target.type = 'split'
  $target.dir = $Dir
  $target.percent = $Percent
  $target.children = @($keep, $fresh)

  $fresh.id
}

function Remove-PsxPane {
  <#
    Delete a pane; its sibling collapses upward into the parent's slot.
    Returns the id of the pane that should take focus afterwards, or $null if
    this was the last pane (the root is never removed - a layout always has at
    least one pane).
  #>
  param($Layout, [string]$Id)

  if ($Layout.root.type -eq 'pane') { return $null }   # last pane, refuse

  $parent = Find-PsxParent $Layout.root $Id
  if (-not $parent) { throw "no pane '$Id'" }

  $sibling = if ($parent.children[0].type -eq 'pane' -and $parent.children[0].id -eq $Id) {
    $parent.children[1]
  } else {
    $parent.children[0]
  }

  # Overwrite the parent node with the sibling's contents, in place.
  $parent.Remove('dir'); $parent.Remove('percent'); $parent.Remove('children')
  foreach ($k in $sibling.Keys) { $parent[$k] = $sibling[$k] }

  if ($parent.type -eq 'pane') { $parent.id } else { @(Get-PsxPanes $parent)[0].id }
}

function Set-PsxPaneApp {
  param($Layout, [string]$Id, [string]$App, [string]$Command, [bool]$Run, [string]$Label)
  $p = Find-PsxNode $Layout.root $Id
  if (-not $p) { throw "no pane '$Id'" }
  $p.app = $App; $p.command = $Command; $p.run = $Run; $p.label = $Label
  $p
}

function Set-PsxSplitPercent {
  # Resize the split that owns $Id. Clamped: psmux refuses degenerate panes, and
  # anything under ~10% is unusable anyway.
  param($Layout, [string]$Id, [int]$Delta)
  $parent = Find-PsxParent $Layout.root $Id
  if (-not $parent) { return }
  $new = $parent.percent + $Delta
  $parent.percent = [Math]::Max(10, [Math]::Min(90, $new))
}

function Reset-PsxPaneIds {
  # Renumber p1..pN depth-first. Called after loading so ids are stable and
  # readable, and so a hand-edited JSON file cannot contain duplicates.
  param($Layout)
  $script:NextPaneId = 0
  foreach ($p in @(Get-PsxPanes $Layout.root)) {
    $script:NextPaneId++
    $p.id = "p$script:NextPaneId"
  }
  $Layout
}
