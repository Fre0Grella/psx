<#
  Builder.ps1 - turn a layout tree into a running psmux session.

  Split in two on purpose:

    Get-PsxBuildPlan    pure. tree -> ordered list of operations. Testable.
    Invoke-PsxBuildPlan impure. runs the plan against psmux.

  The plan speaks in MODEL pane ids (p1, p2...). Invoke maps those to real psmux
  pane ids (%1, %2...) as it goes.

  Why pane IDs and never indices: psmux 3.3.7's pane-index lookup ignores
  pane-base-index, so with `pane-base-index 1` set (as in ~/.psmux.conf) the
  target ':1.1' resolves to the SECOND pane and the first is unreachable
  entirely. Worse, psmux resolves an invalid target to the ACTIVE pane instead
  of failing, so the symptom is commands landing in the wrong pane rather than
  an error. Pane ids are immune.
#>

function Get-PsxFirstPaneId {
  param($Node)
  if ($Node.type -eq 'pane') { return $Node.id }
  Get-PsxFirstPaneId $Node.children[0]
}

function Get-PsxBuildPlan {
  <#
    Ops:
      @{ op='root';  result=<paneId> }                      the session's initial pane
      @{ op='split'; target=<paneId>; dir; percent; result=<paneId> }
      @{ op='send';  pane=<paneId>; command; run }
      @{ op='focus'; pane=<paneId> }

    Invariant that makes this simple: splitting a region leaves the ORIGINAL
    psmux pane covering the first child, so the occupant of any subtree is
    always that subtree's first (depth-first) pane.
  #>
  param($Layout)

  $plan = @(@{ op = 'root'; result = (Get-PsxFirstPaneId $Layout.root) })

  function Walk {
    param($Node, $Acc)
    if ($Node.type -ne 'split') { return }
    $occupant = Get-PsxFirstPaneId $Node.children[0]
    $newPane = Get-PsxFirstPaneId $Node.children[1]
    $Acc.Add(@{
      op      = 'split'
      target  = $occupant
      dir     = $Node.dir
      percent = $Node.percent
      result  = $newPane
    }) | Out-Null
    Walk $Node.children[0] $Acc
    Walk $Node.children[1] $Acc
  }

  $acc = [Collections.ArrayList]::new()
  Walk $Layout.root $acc
  $plan += @($acc)

  foreach ($p in @(Get-PsxPanes $Layout.root)) {
    if ($p.command) {
      $plan += @{ op = 'send'; pane = $p.id; command = $p.command; run = [bool]$p.run }
    }
  }

  $focus = if ($Layout.focus -and (Find-PsxNode $Layout.root $Layout.focus)) {
    $Layout.focus
  } else {
    Get-PsxFirstPaneId $Layout.root
  }
  $plan += @{ op = 'focus'; pane = $focus }

  $plan
}

# --------------------------------------------------------------------------
# Execution
# --------------------------------------------------------------------------

function Get-PsxActivePane {
  param([string]$Session)
  $line = @(psmux list-panes -t $Session 2>&1 | Where-Object { $_ -match '\(active\)' })[0]
  $id = [regex]::Match("$line", '%\d+').Value
  # Never let an empty target through: psmux would silently fall back to the
  # active pane and build the wrong layout.
  if ($id -notmatch '^%\d+$') { throw "could not resolve the active pane (got '$line')" }
  $id
}

function Get-PsxFirstRealPane {
  param([string]$Session)
  # @() is load-bearing: with a single pane this returns one bare string, and
  # [0] would then index the first CHARACTER ('%') rather than the first element.
  $ids = @(psmux list-panes -t $Session 2>&1 |
      ForEach-Object { [regex]::Match("$_", '%\d+').Value } |
      Where-Object { $_ })
  if ($ids.Count -lt 1) { throw "session '$Session' has no panes" }
  $ids[0]
}

function Wait-PsxPane {
  <#
    send-keys into a shell that has not finished starting is SILENTLY LOST - no
    error, the keystrokes simply vanish. A fixed sleep is not enough: it only
    ever covered the first pane, so the last pane created (youngest shell)
    reliably came up empty. Poll for a rendered prompt instead.
  #>
  param([string]$Pane, [int]$TimeoutMs = 8000)
  $sw = [Diagnostics.Stopwatch]::StartNew()
  while ($sw.ElapsedMilliseconds -lt $TimeoutMs) {
    $out = @(psmux capture-pane -p -t $Pane 2>$null | Where-Object { "$_".Trim() -ne '' })
    if ($out.Count -gt 0) { return $true }
    Start-Sleep -Milliseconds 100
  }
  $false
}

function Invoke-PsxBuildPlan {
  param(
    $Plan,
    [string]$Session,
    [string]$Dir
  )

  $real = @{}    # model pane id -> psmux %id

  psmux new-session -d -s $Session -c $Dir 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "psmux could not create session '$Session'" }

  foreach ($op in $Plan) {
    switch ($op.op) {

      'root' { $real[$op.result] = Get-PsxFirstRealPane $Session }

      'split' {
        $target = $real[$op.target]
        if (-not $target) { throw "build plan is inconsistent: no pane for '$($op.target)'" }
        $flag = if ($op.dir -eq 'h') { '-h' } else { '-v' }
        psmux split-window $flag -t $target -p $op.percent -c $Dir 2>&1 | Out-Null
        $real[$op.result] = Get-PsxActivePane $Session   # the new pane becomes active
      }

      'send' {
        $pane = $real[$op.pane]
        # Every shell was started by the splits above, so by now they have all
        # been booting in parallel; this usually returns immediately.
        if (-not (Wait-PsxPane $pane)) {
          Write-Host "  warning: pane $pane never showed a prompt, '$($op.command)' may be lost" -ForegroundColor Yellow
        }
        if ($op.run) { psmux send-keys -t $pane $op.command Enter 2>&1 | Out-Null }
        else { psmux send-keys -t $pane $op.command 2>&1 | Out-Null }
      }

      'focus' {
        $pane = $real[$op.pane]
        if ($pane) { psmux select-pane -t $pane 2>&1 | Out-Null }
      }
    }
  }

  $real
}
