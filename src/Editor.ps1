<#
  Editor.ps1 - the full-screen layout editor.

  This is the only file that touches the console, and it holds no layout logic
  of its own: it moves a selection around, calls Model/Render, and draws. That
  separation is what lets the geometry and navigation be tested without a
  terminal (see tests\run.ps1) - a TUI is otherwise close to untestable.

  Redraw strategy: park the cursor at 0,0 and overwrite, padding every line to
  the console width. Clear-Host each frame would flicker badly at this size.
#>

function Write-PsxLine {
  # One rendered row, with the selected pane's columns highlighted.
  param([string]$Line, $Rect, [int]$Row, [int]$Width)

  $pad = $Line.PadRight($Width)
  if (-not $Rect -or $Row -lt $Rect.y -or $Row -gt ($Rect.y + $Rect.h - 1)) {
    Write-Host $pad -ForegroundColor DarkGray
    return
  }
  $a = $Rect.x
  $b = [Math]::Min($Rect.x + $Rect.w, $pad.Length)
  Write-Host $pad.Substring(0, $a) -ForegroundColor DarkGray -NoNewline
  Write-Host $pad.Substring($a, $b - $a) -ForegroundColor Cyan -NoNewline
  Write-Host $pad.Substring($b) -ForegroundColor DarkGray
}

function Read-PsxLineInput {
  # Prompt on a cleared line at the bottom of the frame. Returns '' if cancelled.
  param([string]$Prompt, [string]$Default = '')
  Write-Host ''
  Write-Host "  $Prompt" -ForegroundColor Yellow -NoNewline
  if ($Default) { Write-Host " [$Default]" -ForegroundColor DarkGray -NoNewline }
  Write-Host ': ' -NoNewline
  $v = Read-Host
  if (-not $v) { return $Default }
  $v
}

function Show-PsxPicker {
  <#
    Vertical menu. Up/Down + Enter, Esc cancels. Returns the chosen catalogue
    entry, or $null.

    Unavailable programs are shown greyed out with a marker rather than hidden:
    if 'htop' silently vanished from the list you would assume psx did not
    support it, instead of learning that it is simply not installed.
  #>
  param([string]$Title = 'what runs in this pane?')

  $items = @(Get-PsxCatalog)
  $sel = 0
  while ($true) {
    Clear-Host
    Write-Host ''
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host ''
    for ($i = 0; $i -lt $items.Count; $i++) {
      $e = $items[$i]
      $have = Test-PsxAvailable $e
      $mark = if ($i -eq $sel) { ' > ' } else { '   ' }
      $name = $e.label.PadRight(16)
      $note = if (-not $have) { "not installed ($($e.needs))" } else { $e.hint }

      $col = if ($i -eq $sel) { 'Cyan' } elseif (-not $have) { 'DarkGray' } else { 'Gray' }
      Write-Host "$mark$name" -ForegroundColor $col -NoNewline
      Write-Host "  $note" -ForegroundColor DarkGray
    }
    Write-Host ''
    Write-Host '  up/down move    enter choose    esc cancel' -ForegroundColor DarkGray

    $k = [Console]::ReadKey($true)
    switch ($k.Key) {
      'UpArrow'   { $sel = ($sel - 1 + $items.Count) % $items.Count }
      'DownArrow' { $sel = ($sel + 1) % $items.Count }
      'Escape'    { return $null }
      'Enter'     { return $items[$sel] }
    }
  }
}

function Resolve-PsxApp {
  <#
    Turn a catalogue choice into the concrete (command, run, label) to store.
    'custom' and 'ssh' need a follow-up question; everything else is fixed.
  #>
  param($Entry)
  if (-not $Entry) { return $null }

  if ($Entry.key -eq 'custom') {
    Clear-Host
    Write-Host ''
    Write-Host '  custom command' -ForegroundColor Cyan
    $cmd = Read-PsxLineInput 'command to put in this pane'
    if (-not $cmd) { return $null }

    Write-Host ''
    Write-Host '  run it automatically, or just type it and wait for you?' -ForegroundColor Cyan
    Write-Host '    [r] run on open      starts immediately' -ForegroundColor Gray
    Write-Host '    [t] type only        sits at the prompt, you press Enter' -ForegroundColor Gray
    Write-Host ''
    $run = $false
    while ($true) {
      $k = [Console]::ReadKey($true)
      if ($k.KeyChar -eq 'r') { $run = $true; break }
      if ($k.KeyChar -eq 't') { $run = $false; break }
      if ($k.Key -eq 'Escape') { return $null }
    }
    $label = ($cmd -split '\s+')[0]
    return @{ app = 'custom'; command = $cmd; run = $run; label = $label }
  }

  if ($Entry.prompt) {
    Clear-Host
    Write-Host ''
    Write-Host "  $($Entry.label)" -ForegroundColor Cyan
    $arg = Read-PsxLineInput $Entry.prompt
    if (-not $arg) { return $null }
    return @{ app = $Entry.key; command = ($Entry.command -f $arg); run = $Entry.run; label = "$($Entry.key) $arg" }
  }

  @{ app = $Entry.key; command = $Entry.command; run = $Entry.run; label = $Entry.label }
}

function Invoke-PsxEditorAction {
  <#
    Every editor key that does NOT need to ask the user something. Pulled out of
    the input loop so it can be tested without a console: the loop then only
    reads keys and draws.

    Returns @{ Sel; Dirty; Msg; Handled }. Handled = $false means the caller
    should deal with it (the keys that open a prompt: enter, d, w, q).
  #>
  param($Layout, [string]$Sel, $Rects, [string]$Key)

  $res = @{ Sel = $Sel; Dirty = $false; Msg = ''; Handled = $true }

  switch -CaseSensitive ($Key) {
    'left'  { $t = Find-PsxNeighbour $Rects $Sel 'left';  if ($t) { $res.Sel = $t }; return $res }
    'right' { $t = Find-PsxNeighbour $Rects $Sel 'right'; if ($t) { $res.Sel = $t }; return $res }
    'up'    { $t = Find-PsxNeighbour $Rects $Sel 'up';    if ($t) { $res.Sel = $t }; return $res }
    'down'  { $t = Find-PsxNeighbour $Rects $Sel 'down';  if ($t) { $res.Sel = $t }; return $res }

    '\' { $res.Sel = Split-PsxPane $Layout $Sel 'h' 50; $res.Dirty = $true; return $res }
    '-' { $res.Sel = Split-PsxPane $Layout $Sel 'v' 50; $res.Dirty = $true; return $res }

    'x' {
      $next = Remove-PsxPane $Layout $Sel
      if ($null -eq $next) { $res.Msg = 'a layout needs at least one pane' }
      else { $res.Sel = $next; $res.Dirty = $true }
      return $res
    }

    '[' { Set-PsxSplitPercent $Layout $Sel -5; $res.Dirty = $true; return $res }
    ']' { Set-PsxSplitPercent $Layout $Sel 5;  $res.Dirty = $true; return $res }

    'f' {
      $Layout.focus = $Sel
      $res.Dirty = $true
      $res.Msg = 'this pane will be focused when the session opens'
      return $res
    }
  }

  $res.Handled = $false
  $res
}

function Invoke-PsxEditor {
  <#
    Edit $Layout in place. Returns $true if it was saved, $false if abandoned.
  #>
  param($Layout)

  $sel = (Get-PsxFirstPaneId $Layout.root)
  $dirty = $false
  $msg = ''

  while ($true) {
    $cw = try { [Console]::WindowWidth } catch { 100 }
    if ($cw -lt 40) { $cw = 40 }
    $boxW = [Math]::Min(76, $cw - 4)
    $boxH = 16

    $r = Format-PsxLayout $Layout $boxW $boxH
    $rects = @($r.Rects)
    if (-not @($rects | Where-Object { $_.id -eq $sel })) { $sel = $rects[0].id }
    $cur = @($rects | Where-Object { $_.id -eq $sel })[0]

    try { [Console]::SetCursorPosition(0, 0) } catch { Clear-Host }

    $title = "  psx  -  $($Layout.name)"
    if ($dirty) { $title += '  *' }
    Write-Host $title.PadRight($cw) -ForegroundColor Cyan
    Write-Host ("  " + $(if ($Layout.desc) { $Layout.desc } else { '(no description)' })).PadRight($cw) -ForegroundColor DarkGray
    Write-Host ''.PadRight($cw)

    for ($i = 0; $i -lt $r.Lines.Count; $i++) {
      Write-Host '  ' -NoNewline
      Write-PsxLine $r.Lines[$i] $cur $i ($cw - 2)
    }

    Write-Host ''.PadRight($cw)
    $n = $cur.node
    $what = if ($n.command) { "$($n.command)  ($(if ($n.run) { 'runs on open' } else { 'typed, not run' }))" } else { 'plain shell' }
    $focusTag = if ($Layout.focus -eq $sel) { '   [starts focused]' } else { '' }
    Write-Host ("  selected: $($n.label)  ->  $what$focusTag").PadRight($cw) -ForegroundColor White
    Write-Host ''.PadRight($cw)
    Write-Host '  arrows move   \ split side-by-side   - split top/bottom   enter set command'.PadRight($cw) -ForegroundColor DarkGray
    Write-Host '  x delete pane   [ ] resize   f focus here   d description   w save   q quit'.PadRight($cw) -ForegroundColor DarkGray
    Write-Host ("  $msg").PadRight($cw) -ForegroundColor Yellow
    $msg = ''

    $k = [Console]::ReadKey($true)

    # Normalise the key to the token Invoke-PsxEditorAction understands. hjkl
    # move too, for anyone whose hands already do that.
    $ch = switch ($k.Key) {
      'LeftArrow'  { 'left' }
      'RightArrow' { 'right' }
      'UpArrow'    { 'up' }
      'DownArrow'  { 'down' }
      'Delete'     { 'x' }
      'Enter'      { "`r" }
      default {
        switch ($k.KeyChar) {
          'h' { 'left' } 'l' { 'right' } 'k' { 'up' } 'j' { 'down' }
          default { [string]$k.KeyChar }
        }
      }
    }

    $act = Invoke-PsxEditorAction $Layout $sel $rects $ch
    $sel = $act.Sel
    if ($act.Dirty) { $dirty = $true }
    if ($act.Msg) { $msg = $act.Msg }
    if ($act.Handled) {
      if ($ch -eq 'x') { Clear-Host }   # the frame shrinks, so wipe the old one
      continue
    }

    switch -CaseSensitive ($ch) {

      "`r" {
        $entry = Show-PsxPicker
        $app = Resolve-PsxApp $entry
        if ($app) {
          Set-PsxPaneApp $Layout $sel $app.app $app.command $app.run $app.label | Out-Null
          $dirty = $true
        }
        Clear-Host
      }

      'd' {
        Clear-Host
        $d = Read-PsxLineInput 'description' $Layout.desc
        $Layout.desc = $d
        $dirty = $true
        Clear-Host
      }

      'w' {
        $p = Export-PsxTemplate $Layout
        $dirty = $false
        $msg = "saved to $p"
      }

      'q' {
        if (-not $dirty) { Clear-Host; return $false }
        Clear-Host
        Write-Host ''
        Write-Host '  unsaved changes. [s] save and quit   [q] quit anyway   [esc] keep editing' -ForegroundColor Yellow
        while ($true) {
          $c = [Console]::ReadKey($true)
          if ($c.KeyChar -eq 's') { Export-PsxTemplate $Layout | Out-Null; Clear-Host; return $true }
          if ($c.KeyChar -eq 'q') { Clear-Host; return $false }
          if ($c.Key -eq 'Escape') { break }
        }
        Clear-Host
      }
    }
  }
}
