<#
.SYNOPSIS
    One-click sandbox setup for the Kotzu Trophy Room system (Windows).

.DESCRIPTION
    Copies resources/[kotzu] into a FiveM sandbox server's resources folder,
    verifies prerequisites, and prints the exact server.cfg lines to add.
    Safe to re-run (idempotent copy). NEVER points at the live server by default.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\setup-sandbox.ps1 `
        -ServerRoot "D:\FiveM-AI\Sandbox\server"
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$ServerRoot,

    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot   # fivem/trophy-room
$sourceRes = Join-Path $repoRoot 'resources\[kotzu]'

function Fail($msg) { Write-Host "[X] $msg" -ForegroundColor Red; exit 1 }
function Ok($msg)   { Write-Host "[OK] $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "[!] $msg" -ForegroundColor Yellow }

# ---- safety rails ------------------------------------------------------------
if ($ServerRoot -like 'E:\FiveMserver*' -and -not $Force) {
    Fail "Refusing to touch the LIVE server path ($ServerRoot). Acceptance must pass first (docs\validation-matrix.md). Use -Force only after full sign-off."
}
if (-not (Test-Path $sourceRes)) { Fail "Source not found: $sourceRes (run from the repo)" }

$resourcesDir = Join-Path $ServerRoot 'resources'
if (-not (Test-Path $resourcesDir)) {
    # txAdmin layouts vary; try the common nested layout before giving up
    $candidates = Get-ChildItem -Path $ServerRoot -Directory -Recurse -Depth 3 -Filter 'resources' -ErrorAction SilentlyContinue
    if ($candidates.Count -ge 1) {
        $resourcesDir = $candidates[0].FullName
        Warn "Using detected resources folder: $resourcesDir"
    } else {
        Fail "No 'resources' folder under $ServerRoot"
    }
}

# ---- prerequisite scan -------------------------------------------------------
$need = @('oxmysql')
$nice = @('qb-core', 'rcore_clothing', 'qb-target', 'ox_target', 'qb-inventory', 'ox_inventory')
foreach ($r in $need) {
    if (Get-ChildItem -Path $resourcesDir -Directory -Recurse -Depth 2 -Filter $r -ErrorAction SilentlyContinue) { Ok "found required resource: $r" }
    else { Warn "REQUIRED resource missing: $r - install it before starting" }
}
foreach ($r in $nice) {
    if (Get-ChildItem -Path $resourcesDir -Directory -Recurse -Depth 2 -Filter $r -ErrorAction SilentlyContinue) { Ok "found optional resource: $r" }
}

# ---- copy --------------------------------------------------------------------
$dest = Join-Path $resourcesDir '[kotzu]'
Write-Host "Copying $sourceRes -> $dest"
robocopy $sourceRes $dest /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { Fail "robocopy failed with code $LASTEXITCODE" }
Ok "resources copied (mirrored)"

# stream dir binaries live outside git; warn if the mannequin assets are absent
$streamFiles = Get-ChildItem -Path (Join-Path $dest 'kotzu_mannequin_assets\stream') -Filter '*.ydd' -ErrorAction SilentlyContinue
if (-not $streamFiles) {
    Warn "kotzu_mannequin_assets\stream has no built .ydd files yet - mannequin placement will refuse with MANIFEST_NOT_BUILT until you run tools\mannequin_pipeline (that is expected before Pasul 2)."
}

# ---- server.cfg guidance -----------------------------------------------------
Write-Host ""
Write-Host "Add these lines to your sandbox server.cfg (order matters):" -ForegroundColor Cyan
@"
ensure oxmysql
ensure qb-core
ensure rcore_clothing          # if installed
ensure kotzu_mannequin_assets
ensure kotzu_trophy_room
ensure kotzu_arch_proof        # sandbox only

add_ace group.admin kotzu.trophy.admin allow
add_ace group.admin kotzu.archproof allow
"@ | Write-Host

Write-Host ""
Ok "Setup done. Start the server, join, then run: /archproof run"
Write-Host "Full procedure: docs\acceptance-runbook.md"
