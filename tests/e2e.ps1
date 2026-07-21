<#
  End-to-end check: build a real psmux session from a template and verify the
  geometry and the commands actually landed where the plan said they would.

  Runs on its own psmux server socket (-L psxe2e) so it can never disturb a
  session you are using, and kills it afterwards.

    pwsh -File tests\e2e.ps1
#>

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. "$root\src\Model.ps1"
. "$root\src\Render.ps1"
. "$root\src\Catalog.ps1"
. "$root\src\Store.ps1"
. "$root\src\Builder.ps1"

$script:Pass = 0; $script:Fail = 0
function ok { param([string]$W, [bool]$C, [string]$D = '')
  if ($C) { $script:Pass++; Write-Host "  ok   $W" -ForegroundColor DarkGreen }
  else { $script:Fail++; Write-Host "  FAIL $W" -ForegroundColor Red; if ($D) { Write-Host "       $D" -ForegroundColor DarkGray } }
}
function eq { param([string]$W, $A, $E) ok $W ($A -eq $E) "expected [$E] got [$A]" }

# Isolated server socket. Everything below talks to this one only.
function psmux { & (Get-Command psmux.exe).Source -L psxe2e @args }

$sess = 'e2e'
$dir = $env:TEMP

Write-Host ''
Write-Host 'render every starter template' -ForegroundColor Cyan
foreach ($f in Get-ChildItem (Join-Path $root 'templates') -Filter *.json) {
  $t = Get-Content $f.FullName -Raw | ConvertFrom-Json -AsHashtable -Depth 30
  $t = Reset-PsxPaneIds $t
  $r = Format-PsxLayout $t 60 14
  $widths = @($r.Lines | ForEach-Object { $_.Length } | Sort-Object -Unique)
  ok "$($f.BaseName): renders as a clean 60x14 block" ($r.Lines.Count -eq 14 -and $widths.Count -eq 1 -and $widths[0] -eq 60)
  ok "$($f.BaseName): every pane got a rect" (@($r.Rects).Count -eq @(Get-PsxPanes $t.root).Count)
}

Write-Host ''
Write-Host 'build the dev template for real' -ForegroundColor Cyan
$layout = Get-Content (Join-Path $root 'templates\dev.json') -Raw | ConvertFrom-Json -AsHashtable -Depth 30
$layout = Reset-PsxPaneIds $layout
$plan = Get-PsxBuildPlan $layout

psmux kill-session -t $sess 2>&1 | Out-Null
try {
  $map = Invoke-PsxBuildPlan $plan $sess $dir

  $panes = @(psmux list-panes -t $sess 2>&1 | Where-Object { "$_".Trim() })
  eq 'three panes exist' $panes.Count 3

  # The left pane should be the wide one; the two right panes stacked.
  $dims = @($panes | ForEach-Object {
      $m = [regex]::Match("$_", '\[(\d+)x(\d+)\]')
      @{ w = [int]$m.Groups[1].Value; h = [int]$m.Groups[2].Value }
    })
  ok 'first pane is the widest (the 45% split went to the NEW pane)' (
    $dims[0].w -gt $dims[1].w
  ) ("widths: " + (($dims | ForEach-Object { $_.w }) -join ', '))
  ok 'the two right panes are shorter than the left one' (
    $dims[1].h -lt $dims[0].h -and $dims[2].h -lt $dims[0].h
  ) ("heights: " + (($dims | ForEach-Object { $_.h }) -join ', '))

  # Commands landed in the right panes. The two cases need different evidence:
  #
  #   run = $false  the command sits unexecuted on the prompt, so it is visible
  #                 on screen and matching the text is the whole check.
  #   run = $true   the program has started and may well have repainted the pane
  #                 (Claude Code does), so the text is gone. Ask psmux what is
  #                 actually running instead - if it is still pwsh, nothing ran.
  #
  # Matching text for both was the original mistake here: it reported a working
  # 'claude' pane as broken because Claude's own UI had replaced the echo.
  Start-Sleep -Milliseconds 1500
  foreach ($op in @($plan | Where-Object { $_.op -eq 'send' })) {
    $real = $map[$op.pane]

    if ($op.run) {
      $proc = (psmux display-message -p -t $real '#{pane_current_command}' 2>&1 | Select-Object -First 1)
      ok "'$($op.command)' is RUNNING in pane $($op.pane) ($real)" ("$proc".Trim() -ne 'pwsh') "pane_current_command = $proc"
    }
    else {
      $text = @(psmux capture-pane -p -S -200 -t $real 2>$null | Where-Object { "$_".Trim() -ne '' })
      $joined = $text -join "`n"
      ok "'$($op.command)' is TYPED but not run in pane $($op.pane) ($real)" (
        $joined -match [regex]::Escape($op.command)
      ) "pane showed: $(if ($text.Count) { $text[-1] } else { '<empty>' })"

      $proc = (psmux display-message -p -t $real '#{pane_current_command}' 2>&1 | Select-Object -First 1)
      ok "  ...and really did not run (still at the shell)" ("$proc".Trim() -eq 'pwsh') "pane_current_command = $proc"
    }
  }
}
finally {
  psmux kill-session -t $sess 2>&1 | Out-Null
  psmux kill-server 2>&1 | Out-Null
}

Write-Host ''
if ($script:Fail -eq 0) { Write-Host "$script:Pass passed, 0 failed" -ForegroundColor Green; exit 0 }
Write-Host "$script:Pass passed, $script:Fail FAILED" -ForegroundColor Red
exit 1
