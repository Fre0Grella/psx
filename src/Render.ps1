<#
  Render.ps1 - layout tree -> character grid.

  Pure. Takes a tree and a box size, returns lines plus the rectangle each pane
  occupies. No console calls, so it can be tested by diffing strings.

  Two things worth knowing:

  1. Adjacent panes SHARE a border column/row. Rects therefore overlap by one
     cell, which is why the widths add up to w+1 rather than w.
  2. Borders are accumulated as direction bitmasks and only turned into
     characters at the end. Drawing box characters directly would leave wrong
     glyphs where three lines meet - you would get a corner where a T belongs.
#>

$script:BoxChars = @{
  0  = ' '; 1  = '│'; 2  = '│'; 3  = '│'
  4  = '─'; 5  = '┘'; 6  = '┐'; 7  = '┤'
  8  = '─'; 9  = '└'; 10 = '┌'; 11 = '├'
  12 = '─'; 13 = '┴'; 14 = '┬'; 15 = '┼'
}
$script:B_UP = 1; $script:B_DOWN = 2; $script:B_LEFT = 4; $script:B_RIGHT = 8

function Get-PsxRects {
  <#
    Assign every pane a rectangle inside (X,Y,W,H). Adjacent rects share their
    dividing border, so a split of width W yields widths that sum to W+1.
  #>
  param($Node, [int]$X = 0, [int]$Y = 0, [int]$W = 60, [int]$H = 20)

  if ($null -eq $Node) { return @() }

  # Same rule as Get-PsxPanes: returns unrolled, callers wrap in @().
  if ($Node.type -eq 'pane') {
    return @{ id = $Node.id; x = $X; y = $Y; w = $W; h = $H; node = $Node }
  }

  $p = $Node.percent

  if ($Node.dir -eq 'h') {
    # +1 on each side because the shared border column belongs to both.
    $w1 = [Math]::Round(($W - 1) * $p / 100.0) + 1
    $w1 = [Math]::Max(3, [Math]::Min($W - 2, $w1))
    $w0 = $W - $w1 + 1
    return @(Get-PsxRects $Node.children[0] $X $Y $w0 $H) +
           @(Get-PsxRects $Node.children[1] ($X + $w0 - 1) $Y $w1 $H)
  }

  $h1 = [Math]::Round(($H - 1) * $p / 100.0) + 1
  $h1 = [Math]::Max(3, [Math]::Min($H - 2, $h1))
  $h0 = $H - $h1 + 1
  @(Get-PsxRects $Node.children[0] $X $Y $W $h0) +
  @(Get-PsxRects $Node.children[1] $X ($Y + $h0 - 1) $W $h1)
}

function Format-PsxLayout {
  <#
    Returns @{ Lines = string[]; Rects = <rects> }.
    Rects come back so the caller can colour the selected pane and navigate
    between panes by position.
  #>
  param($Layout, [int]$Width = 60, [int]$Height = 20)

  $rects = @(Get-PsxRects $Layout.root 0 0 $Width $Height)

  # borders[y][x] = bitmask, text[y][x] = char
  $borders = New-Object 'int[][]' $Height
  $text = New-Object 'char[][]' $Height
  for ($y = 0; $y -lt $Height; $y++) {
    $borders[$y] = New-Object 'int[]' $Width
    $text[$y] = New-Object 'char[]' $Width
    for ($x = 0; $x -lt $Width; $x++) { $text[$y][$x] = ' ' }
  }

  function Add-H { param($bd, $y, $x1, $x2, $W, $H)
    for ($i = $x1; $i -le $x2; $i++) {
      if ($i -lt 0 -or $i -ge $W -or $y -lt 0 -or $y -ge $H) { continue }
      if ($i -gt $x1) { $bd[$y][$i] = $bd[$y][$i] -bor 4 }
      if ($i -lt $x2) { $bd[$y][$i] = $bd[$y][$i] -bor 8 }
    }
  }
  function Add-V { param($bd, $x, $y1, $y2, $W, $H)
    for ($j = $y1; $j -le $y2; $j++) {
      if ($j -lt 0 -or $j -ge $H -or $x -lt 0 -or $x -ge $W) { continue }
      if ($j -gt $y1) { $bd[$j][$x] = $bd[$j][$x] -bor 1 }
      if ($j -lt $y2) { $bd[$j][$x] = $bd[$j][$x] -bor 2 }
    }
  }

  foreach ($r in $rects) {
    $x2 = $r.x + $r.w - 1
    $y2 = $r.y + $r.h - 1
    Add-H $borders $r.y   $r.x $x2 $Width $Height
    Add-H $borders $y2    $r.x $x2 $Width $Height
    Add-V $borders $r.x   $r.y $y2 $Width $Height
    Add-V $borders $x2    $r.y $y2 $Width $Height
  }

  foreach ($r in $rects) {
    $inW = $r.w - 2
    if ($inW -lt 1) { continue }
    $n = $r.node

    $lines = @()
    $lines += $n.label
    if ($r.h -ge 5) {
      $cmd = if ($n.command) { $n.command } else { '(nothing typed)' }
      $mark = if (-not $n.command) { '' } elseif ($n.run) { 'run: ' } else { 'typed: ' }
      $lines += "$mark$cmd"
    }

    $startY = $r.y + [Math]::Floor(($r.h - $lines.Count) / 2)
    for ($k = 0; $k -lt $lines.Count; $k++) {
      $s = $lines[$k]
      if ($s.Length -gt $inW) { $s = $s.Substring(0, [Math]::Max(1, $inW - 1)) + '~' }
      $sx = $r.x + 1 + [Math]::Floor(($inW - $s.Length) / 2)
      $sy = $startY + $k
      if ($sy -le $r.y -or $sy -ge ($r.y + $r.h - 1)) { continue }
      for ($i = 0; $i -lt $s.Length; $i++) {
        $tx = $sx + $i
        if ($tx -gt $r.x -and $tx -lt ($r.x + $r.w - 1) -and $tx -lt $Width) {
          $text[$sy][$tx] = $s[$i]
        }
      }
    }
  }

  $out = @()
  for ($y = 0; $y -lt $Height; $y++) {
    $sb = [Text.StringBuilder]::new()
    for ($x = 0; $x -lt $Width; $x++) {
      $b = $borders[$y][$x]
      if ($b -ne 0) { [void]$sb.Append($script:BoxChars[$b]) }
      else { [void]$sb.Append($text[$y][$x]) }
    }
    $out += $sb.ToString()
  }

  @{ Lines = $out; Rects = $rects }
}

function Find-PsxNeighbour {
  <#
    Spatial navigation: "the box to my right", not the next box in tree order.

    Reference point is the current pane's TOP-LEFT corner, not its centre.
    Centres look reasonable and are quietly ambiguous: a tall left pane centred
    at row 8 against a right column split at row 7 lands one pixel inside the
    BOTTOM pane, so pressing Right from the left pane jumps to the lower-right
    box. Anchoring on the top edge means Right always reaches the topmost pane
    of the column to the right, and Down always reaches the leftmost pane of the
    row below - predictable, and the same convention tmux uses.
  #>
  param($Rects, [string]$Id, [ValidateSet('left', 'right', 'up', 'down')][string]$Dir)

  $cur = @($Rects | Where-Object { $_.id -eq $Id })[0]
  if (-not $cur) { return $null }

  $refX = $cur.x + 1     # just inside the border
  $refY = $cur.y + 1

  $ahead = @()
  foreach ($r in $Rects) {
    if ($r.id -eq $Id) { continue }
    $ok = switch ($Dir) {
      'left'  { ($r.x + $r.w - 1) -le $cur.x }
      'right' { $r.x -ge ($cur.x + $cur.w - 1) }
      'up'    { ($r.y + $r.h - 1) -le $cur.y }
      'down'  { $r.y -ge ($cur.y + $cur.h - 1) }
    }
    if ($ok) { $ahead += $r }
  }
  if ($ahead.Count -eq 0) { return $null }

  # Prefer panes straddling the reference line; among those, the nearest.
  $aligned = @($ahead | Where-Object {
      if ($Dir -in 'left', 'right') { $refY -ge $_.y -and $refY -le ($_.y + $_.h - 1) }
      else { $refX -ge $_.x -and $refX -le ($_.x + $_.w - 1) }
    })
  $pool = if ($aligned.Count) { $aligned } else { $ahead }

  $best = $null; $bestD = [double]::MaxValue
  foreach ($r in $pool) {
    $d = switch ($Dir) {
      'left'  { $cur.x - ($r.x + $r.w - 1) }
      'right' { $r.x - ($cur.x + $cur.w - 1) }
      'up'    { $cur.y - ($r.y + $r.h - 1) }
      'down'  { $r.y - ($cur.y + $cur.h - 1) }
    }
    # Break remaining ties toward the top-left, so movement is repeatable.
    $tie = if ($Dir -in 'left', 'right') { $r.y } else { $r.x }
    $score = $d * 1000 + $tie
    if ($score -lt $bestD) { $bestD = $score; $best = $r }
  }
  if ($best) { $best.id } else { $null }
}
