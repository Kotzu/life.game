<#
.SYNOPSIS
    Semi-automated freemode asset extraction + pipeline run (Windows).

.DESCRIPTION
    Automates everything around the CodeWalker export clicks:
      1. checks Python (+ pillow) availability;
      2. downloads the latest CodeWalker release from GitHub (if not present);
      3. launches CodeWalker and prints the exact export checklist
         (from mannequin_pipeline\EXTRACTION_LIST.md);
      4. after you finish exporting, runs: scan -> classify -> crosscheck
         and prints the reports summary.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\run-extraction.ps1
#>
param(
    [string]$GtaPath = "",          # optional: GTA V install dir hint for CodeWalker
    [switch]$SkipCodeWalkerDownload
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot          # fivem/trophy-room
$pipeDir = Join-Path $PSScriptRoot 'mannequin_pipeline'
$cwDir = Join-Path $PSScriptRoot 'codewalker'

function Ok($m)   { Write-Host "[OK] $m" -ForegroundColor Green }
function Warn($m) { Write-Host "[!] $m" -ForegroundColor Yellow }
function Fail($m) { Write-Host "[X] $m" -ForegroundColor Red; exit 1 }

# ---- 1. Python -------------------------------------------------------------
$py = Get-Command python -ErrorAction SilentlyContinue
if (-not $py) { Fail "Python not found in PATH. Install Python 3.10+ from python.org, then re-run." }
& python -c "import PIL" 2>$null
if ($LASTEXITCODE -ne 0) {
    Warn "Pillow missing - installing (enables automatic skin-texture analysis)"
    & python -m pip install --quiet pillow
}
Ok "Python + Pillow ready"

# ---- 2. CodeWalker ---------------------------------------------------------
$cwExe = Get-ChildItem -Path $cwDir -Filter 'CodeWalker*.exe' -Recurse -ErrorAction SilentlyContinue |
    Select-Object -First 1
if (-not $cwExe -and -not $SkipCodeWalkerDownload) {
    Warn "CodeWalker not found locally - fetching latest GitHub release (dexyfex/CodeWalker)"
    $rel = Invoke-RestMethod -Uri 'https://api.github.com/repos/dexyfex/CodeWalker/releases/latest' `
        -Headers @{ 'User-Agent' = 'kotzu-trophy-room' }
    $asset = $rel.assets | Where-Object { $_.name -match '\.zip$' } | Select-Object -First 1
    if (-not $asset) {
        Warn "No zip asset on the latest release ($($rel.tag_name)). Download CodeWalker manually (GitHub releases or its Discord) into tools\codewalker\ and re-run with -SkipCodeWalkerDownload."
        exit 1
    }
    New-Item -ItemType Directory -Force -Path $cwDir | Out-Null
    $zip = Join-Path $cwDir $asset.name
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zip
    Expand-Archive -Path $zip -DestinationPath $cwDir -Force
    Remove-Item $zip
    $cwExe = Get-ChildItem -Path $cwDir -Filter 'CodeWalker*.exe' -Recurse | Select-Object -First 1
    if (-not $cwExe) { Fail "Extraction finished but no CodeWalker exe found in $cwDir" }
    Ok "CodeWalker $($rel.tag_name) downloaded"
}

# ---- 3. Prepare pipeline config -------------------------------------------
Push-Location $pipeDir
if (-not (Test-Path 'config.json')) {
    Copy-Item 'config.example.json' 'config.json'
    Warn "created config.json from example - review paths/game build later if needed"
}
New-Item -ItemType Directory -Force -Path 'extracted\base_male', 'extracted\base_female', 'extracted\_png' | Out-Null

# ---- 4. Launch CodeWalker + checklist --------------------------------------
Write-Host ""
Write-Host "=== EXPORT CHECKLIST (full details: EXTRACTION_LIST.md) ===" -ForegroundColor Cyan
@"
In CodeWalker's RPF Explorer:
  1. Search each pattern below; select ALL results; right-click -> Export XML
     into the folder shown.
     -> extracted\base_male :   mp_m_freemode_01^head  ^hair  ^uppr  ^lowr
                                ^hand  ^feet  ^teef  ^jbib  ^accs  ^task
                                ^decl  ^berd  ^p_
     -> extracted\base_female : same 13 patterns with mp_f_freemode_01^...
  2. Textures: for the matching .ytd files also 'Export XML' AND open them and
     'Save All' textures as PNG into extracted\_png
  3. Close CodeWalker when done, come back here and press ENTER.
"@ | Write-Host
if ($cwExe) {
    if ($GtaPath) { Start-Process $cwExe.FullName -ArgumentList "`"$GtaPath`"" }
    else { Start-Process $cwExe.FullName }
    Ok "CodeWalker launched: $($cwExe.Name)"
} else {
    Warn "CodeWalker not launched automatically - open your own copy, then follow the checklist."
}
Read-Host "Press ENTER after finishing the export"

# ---- 5. Run the pipeline ---------------------------------------------------
Write-Host ""
Ok "running: scan"
& python -m pipeline scan
if ($LASTEXITCODE -ne 0) { Fail "scan failed" }
Ok "running: classify"
& python -m pipeline classify
Ok "running: crosscheck (vs reference catalog)"
& python -m pipeline crosscheck
$cross = $LASTEXITCODE

Write-Host ""
Write-Host "=== NEXT ===" -ForegroundColor Cyan
if ($cross -ne 0) {
    Warn "crosscheck found missing drawables - open build\crosscheck_report.json, export the missing ones in CodeWalker, then re-run this script (it is incremental)."
} else {
    Ok "extraction complete and verified against the reference catalog!"
    Write-Host "Continue with (Blender + Sollumz required):"
    Write-Host "  python -m pipeline convert"
    Write-Host "  python -m pipeline export"
    Write-Host "  python -m pipeline build-manifest"
    Write-Host "  python -m pipeline validate"
    Write-Host "  python -m pipeline report-coverage"
    Write-Host "Then share build\crosscheck_report.json + coverage_report.md with Claude to continue."
}
Pop-Location
