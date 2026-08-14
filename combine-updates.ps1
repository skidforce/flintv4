<#
.SYNOPSIS
    Automatically combines updates from Pistonware and CatV6 into FlintV4.
.DESCRIPTION
    Pulls latest from both upstream repos, merges new/updated files,
    rebrands references, removes key systems, and pushes to FlintV4.
.PARAMETER SkipPush
    Skip the final git push (for testing).
.PARAMETER DryRun
    Show what would be changed without making changes.
.EXAMPLE
    .\combine-updates.ps1
    .\combine-updates.ps1 -SkipPush
    .\combine-updates.ps1 -DryRun
#>

param(
    [switch]$SkipPush,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$FLINTV4_DIR    = Split-Path -Parent $MyInvocation.MyCommand.Path
$TEMP_DIR       = Join-Path $env:TEMP "flintv4-combine-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
$PISTON_REPO    = "https://github.com/themagicpiston/pistonware.git"
$CATV6_REPO     = "https://github.com/Maxlasertech/CatV6.git"

$PISTON_BASE_FILES = @("loader.lua", "main.lua", "NewMainScript.lua", "reinstall.lua", "loadstring", "whitelist.json", "gui.txt")
$CATV6_EXTRAS = @("guis/liquidbounce.lua", "guis/wurst.lua", "libraries/premium.lua")
$MERGE_FOLDERS = @("games", "guis", "profiles", "libraries", "assets")

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  FlintV4 Auto-Combine Script" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# === STEP 1: CLONE UPSTREAM REPOS ===
Write-Host "[1/8] Cloning upstream repos..." -ForegroundColor Yellow
New-Item -ItemType Directory -Path $TEMP_DIR -Force | Out-Null
Write-Host "  Cloning Pistonware..." -ForegroundColor Gray
git clone --quiet $PISTON_REPO (Join-Path $TEMP_DIR "pistonware") 2>&1 | Out-Null
Write-Host "  Cloning CatV6..." -ForegroundColor Gray
git clone --quiet $CATV6_REPO (Join-Path $TEMP_DIR "catv6") 2>&1 | Out-Null
Write-Host "  Done.`n" -ForegroundColor Green

# === STEP 2: PULL LATEST FLINTV4 ===
Write-Host "[2/8] Pulling latest FlintV4..." -ForegroundColor Yellow
Set-Location $FLINTV4_DIR
git pull --quiet 2>&1 | Out-Null
Write-Host "  Done.`n" -ForegroundColor Green

# === STEP 3: COPY PISTONWARE BASE FILES ===
Write-Host "[3/8] Updating Pistonware base files..." -ForegroundColor Yellow
foreach ($file in $PISTON_BASE_FILES) {
    $src = Join-Path $TEMP_DIR "pistonware" $file
    $dst = Join-Path $FLINTV4_DIR $file
    if (Test-Path $src) {
        if (-not $DryRun) { Copy-Item $src $dst -Force }
        Write-Host "  $(if($DryRun){'[DRY] Would update'}else{'Updated'}): $file" -ForegroundColor Gray
    }
}
Write-Host ""

# === STEP 4: COPY CATV6 EXTRAS ===
Write-Host "[4/8] Updating CatV6 extras..." -ForegroundColor Yellow
foreach ($file in $CATV6_EXTRAS) {
    $src = Join-Path $TEMP_DIR "catv6" $file
    $dst = Join-Path $FLINTV4_DIR $file
    if (Test-Path $src) {
        $dstDir = Split-Path $dst -Parent
        if (-not (Test-Path $dstDir)) { New-Item -ItemType Directory -Path $dstDir -Force | Out-Null }
        if (-not $DryRun) { Copy-Item $src $dst -Force }
        Write-Host "  $(if($DryRun){'[DRY] Would update'}else{'Updated'}): $file" -ForegroundColor Gray
    }
}
Write-Host ""

# === STEP 5: MERGE FOLDERS ===
Write-Host "[5/8] Merging folders..." -ForegroundColor Yellow
foreach ($folder in $MERGE_FOLDERS) {
    $pistonDir = Join-Path $TEMP_DIR "pistonware" $folder
    $catv6Dir  = Join-Path $TEMP_DIR "catv6" $folder
    $flintDir  = Join-Path $FLINTV4_DIR $folder

    $pistonFiles = @(); $catv6Files = @()
    if (Test-Path $pistonDir) {
        $pistonFiles = Get-ChildItem $pistonDir -Recurse -File | ForEach-Object { $_.FullName.Replace($pistonDir, "").TrimStart("\", "/") }
    }
    if (Test-Path $catv6Dir) {
        $catv6Files = Get-ChildItem $catv6Dir -Recurse -File | ForEach-Object { $_.FullName.Replace($catv6Dir, "").TrimStart("\", "/") }
    }

    $allFiles = ($pistonFiles + $catv6Files) | Sort-Object -Unique
    $updated = 0
    foreach ($relPath in $allFiles) {
        $pistonSrc = Join-Path $pistonDir $relPath
        $catv6Src  = Join-Path $catv6Dir $relPath
        $dst       = Join-Path $flintDir $relPath
        $src = $null
        if (Test-Path $pistonSrc) { $src = $pistonSrc }
        elseif (Test-Path $catv6Src) { $src = $catv6Src }
        if ($src) {
            $dstDir = Split-Path $dst -Parent
            if (-not (Test-Path $dstDir)) { New-Item -ItemType Directory -Path $dstDir -Force | Out-Null }
            if (-not $DryRun) { Copy-Item $src $dst -Force }
            $updated++
        }
    }
    Write-Host "  $folder`: $updated files processed" -ForegroundColor Gray
}
Write-Host ""

# === STEP 6: REBRAND ALL REFERENCES ===
Write-Host "[6/8] Rebranding references..." -ForegroundColor Yellow
if (-not $DryRun) {
    $luaFiles = Get-ChildItem $FLINTV4_DIR -Recurse -Include "*.lua" | Where-Object { $_.FullName -notlike "*\.git*" }
    $rebrandCount = 0
    foreach ($file in $luaFiles) {
        $content = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
        if (-not $content) { continue }
        $original = $content

        # URLs
        $content = $content -replace 'themagicpiston/pistonware', 'skidforce/flintv4'
        $content = $content -replace 'gitlab\.com/pistonware/pistonware/-/raw/main/bedwars\.lua', 'raw.githubusercontent.com/skidforce/flintv4/main/games/bedwars.lua'
        $content = $content -replace 'codeberg\.org/pistonware/pistonware/raw/branch/main/', 'raw.githubusercontent.com/skidforce/flintv4/main/'
        $content = $content -replace 'Maxlasertech/CatV6', 'skidforce/flintv4'

        # Paths
        $content = $content -replace "'pistonware/", "'flintv4/"
        $content = $content -replace '"pistonware/', '"flintv4/'
        $content = $content -replace 'catsix/', 'flintv4/'

        # Strings
        $content = $content -replace '\[pistonware\]', '[flintv4]'
        $content = $content -replace "'Pistonware'", "'FlintV4'"
        $content = $content -replace '"Pistonware"', '"FlintV4"'
        $content = $content -replace 'PistonwareDownloader', 'FlintV4Downloader'
        $content = $content -replace 'PistonwareLoaderBoot', 'FlintV4LoaderBoot'
        $content = $content -replace 'PistonwareLoaderTeardown', 'FlintV4LoaderTeardown'
        $content = $content -replace 'PistonwareLoader', 'FlintV4Loader'
        $content = $content -replace 'PistonwareDeveloper', 'FlintV4Developer'
        $content = $content -replace 'PistonwareSessionRejected', 'FlintV4SessionRejected'
        $content = $content -replace 'PistonwareBedwarsLoaded', 'FlintV4BedwarsLoaded'
        $content = $content -replace 'PistonwareSyncResult', 'FlintV4SyncResult'
        $content = $content -replace 'PistonwareAuthenticated', 'FlintV4Authenticated'

        # CatV6 commit.txt fix
        $content = $content -replace "readfile\('flintv4/profiles/commit\.txt'\)", "'main'"

        if ($content -ne $original) {
            Set-Content $file.FullName $content -NoNewline
            $rebrandCount++
        }
    }
    Write-Host "  Rebranded $rebrandCount Lua files" -ForegroundColor Gray
} else {
    Write-Host "  [DRY] Would rebrand all references" -ForegroundColor Gray
}
Write-Host ""

# === STEP 7: REMOVE KEY SYSTEMS FROM GAME SCRIPTS ===
Write-Host "[7/8] Removing key systems from game scripts..." -ForegroundColor Yellow
if (-not $DryRun) {
    $gameFiles = Get-ChildItem (Join-Path $FLINTV4_DIR "games") -Include "*.lua" -Recurse
    $keyRemoved = 0
    foreach ($file in $gameFiles) {
        $content = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
        if (-not $content) { continue }
        $original = $content

        # Remove auth guards: if not shared.XAuthenticated then warn... return end
        $content = $content -replace "(?s)if not shared\.\w+Authenticated then\s*warn\('[^']*'\)\s*return\s*end\r?\n?", ""

        # Remove republishKey function block
        $content = $content -replace "(?s)local function republishKey\(\).*?end\r?\n?", ""

        # Remove republishKey() calls and the surrounding if block
        $content = $content -replace "(?s)if not republishKey\(\) then.*?end\r?\n?", ""

        # Remove shared.XKey and script_key references
        $content = $content -replace "shared\.\w+Key\s*=\s*[^;]+;\s*", ""
        $content = $content -replace "script_key\s*=\s*[^;]+;\s*", ""

        if ($content -ne $original) {
            Set-Content $file.FullName $content -NoNewline
            $keyRemoved++
        }
    }
    Write-Host "  Cleaned key systems from $keyRemoved game scripts" -ForegroundColor Gray
} else {
    Write-Host "  [DRY] Would remove key systems" -ForegroundColor Gray
}
Write-Host ""

# === STEP 8: COMMIT & PUSH ===
Write-Host "[8/8] Committing and pushing..." -ForegroundColor Yellow
Set-Location $FLINTV4_DIR
git add -A
$changes = git diff --cached --stat
if ($changes) {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm"
    $commitMsg = "Auto-update $timestamp - merged Pistonware + CatV6"
    if (-not $DryRun) {
        git commit -m $commitMsg 2>&1 | Out-Null
        Write-Host "  Committed: $commitMsg" -ForegroundColor Gray
        if (-not $SkipPush) {
            git push 2>&1 | Out-Null
            Write-Host "  Pushed to GitHub" -ForegroundColor Gray
        } else {
            Write-Host "  Skipped push (-SkipPush)" -ForegroundColor Gray
        }
    } else {
        Write-Host "  [DRY] Would commit and push" -ForegroundColor Gray
    }
} else {
    Write-Host "  No changes to commit" -ForegroundColor Gray
}

# === CLEANUP ===
Write-Host "`nCleaning up temp files..." -ForegroundColor Gray
Remove-Item $TEMP_DIR -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Done! FlintV4 is up to date." -ForegroundColor Green
Write-Host "  Repo: https://github.com/skidforce/flintv4" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan
