<#
  Store.ps1 - where templates live.

  Templates are JSON under ~/.psx/templates, NOT inside this repo. That
  separation is deliberate: pulling a new version of psx must never touch or
  overwrite layouts you made yourself.

  The repo's templates/ folder holds starter layouts, copied in on first run
  only if the user has none.
#>

function Get-PsxTemplateDir {
  $d = Join-Path $HOME '.psx\templates'
  if (-not (Test-Path $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
  $d
}

function Test-PsxName {
  # Session names go straight to psmux, which dislikes dots and colons, and to
  # a filename. One rule for both, checked up front.
  param([string]$Name)
  $Name -match '^[A-Za-z0-9][A-Za-z0-9_-]{0,31}$'
}

function Get-PsxTemplatePath {
  param([string]$Name)
  Join-Path (Get-PsxTemplateDir) "$Name.json"
}

function Get-PsxTemplateNames {
  Get-ChildItem (Get-PsxTemplateDir) -Filter '*.json' -ErrorAction SilentlyContinue |
    Sort-Object Name |
    ForEach-Object { $_.BaseName }
}

function Import-PsxTemplate {
  param([string]$Name)
  $p = Get-PsxTemplatePath $Name
  if (-not (Test-Path $p)) { return $null }
  # -AsHashtable keeps the model mutable; ConvertFrom-Json would otherwise hand
  # back PSCustomObjects, which cannot be reshaped in place the way Model.ps1 does.
  $t = Get-Content $p -Raw | ConvertFrom-Json -AsHashtable -Depth 30
  Reset-PsxPaneIds $t
}

function Export-PsxTemplate {
  param($Layout)
  if (-not (Test-PsxName $Layout.name)) {
    throw "bad template name '$($Layout.name)': letters, digits, - and _ only, max 32"
  }
  $p = Get-PsxTemplatePath $Layout.name
  $Layout | ConvertTo-Json -Depth 30 | Set-Content -Path $p -Encoding utf8
  $p
}

function Remove-PsxTemplate {
  param([string]$Name)
  $p = Get-PsxTemplatePath $Name
  if (-not (Test-Path $p)) { return $false }
  Remove-Item $p -Force
  $true
}

function Initialize-PsxTemplates {
  # First run: seed the starter templates. Never overwrites an existing file, so
  # editing 'dev' and then updating psx keeps your version.
  param([string]$SeedDir)
  if (-not (Test-Path $SeedDir)) { return }
  $dst = Get-PsxTemplateDir
  foreach ($f in Get-ChildItem $SeedDir -Filter '*.json') {
    $target = Join-Path $dst $f.Name
    if (-not (Test-Path $target)) { Copy-Item $f.FullName $target }
  }
}
