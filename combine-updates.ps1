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

# === CONFIGURATION ===
$FLINTV4_DIR    = Split-Path -Parent $MyInvocation.MyCommand.Path
$TEMP_DIR       = Join-Path $env:TEMP "flintv4-combine-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
$PISTON_REPO    = "https://github.com/themagicpiston/pistonware.git"
$CATV6_REPO     = "https://github.com/Maxlasertech/CatV6.git"
$FLINTV4_REPO   = "https://github.com/skidforce/flintv4.git"
$OLD_URL        = "themagicpiston/pistonware"
$NEW_URL        = "skidforce/flintv4"
$OLD_GITLAB     = "gitlab.com/pistonware/pistonware/-/raw/main/bedwars.lua"
$NEW_GITRAW     = "raw.githubusercontent.com/skidforce/flintv4/main/games/bedwars.lua"

# Files/folders to always take from Pistonware (base)
$PISTON_BASE_FILES = @("loader.lua", "main.lua", "NewMainScript.lua", "reinstall.lua", "loadstring", "whitelist.json", "gui.txt")

# Files to always take from CatV6 (extras)
$CATV6_EXTRAS = @("guis/liquidbounce.lua", "guis/wurst.lua", "libraries/premium.lua")

# Folders to merge (combine contents from both)
$MERGE_FOLDERS = @("games", "guis", "profiles", "libraries", "assets")

# Key system strings to remove if found in new code
$KEY_PATTERNS = @(
    'shared\.PistonwareAuthenticated',
    'shared\.PistonwareKey',
    'script_key\s*=',
    'GETKEY_URL',
    'SCRIPT_ID\s*=.*luarmor',
    'check_key\(',
    'authenticate\(',
    'askKey\(',
    'AskKey\(',
    'KEY_FILE',
    'pistonwarekey\.json'
)

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  FlintV4 Auto-Combine Script" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# === STEP 1: CLONE UPSTREAM REPOS ===
Write-Host "[1/7] Cloning upstream repos..." -ForegroundColor Yellow
New-Item -ItemType Directory -Path $TEMP_DIR -Force | Out-Null

Write-Host "  Cloning Pistonware..." -ForegroundColor Gray
git clone --quiet $PISTON_REPO (Join-Path $TEMP_DIR "pistonware") 2>&1 | Out-Null

Write-Host "  Cloning CatV6..." -ForegroundColor Gray
git clone --quiet $CATV6_REPO (Join-Path $TEMP_DIR "catv6") 2>&1 | Out-Null

Write-Host "  Done.`n" -ForegroundColor Green

# === STEP 2: PULL LATEST FLINTV4 ===
Write-Host "[2/7] Pulling latest FlintV4..." -ForegroundColor Yellow
Set-Location $FLINTV4_DIR
git pull --quiet 2>&1 | Out-Null
Write-Host "  Done.`n" -ForegroundColor Green

# === STEP 3: COPY PISTONWARE BASE FILES ===
Write-Host "[3/7] Updating Pistonware base files..." -ForegroundColor Yellow
foreach ($file in $PISTON_BASE_FILES) {
    $src = Join-Path $TEMP_DIR "pistonware" $file
    $dst = Join-Path $FLINTV4_DIR $file
    if (Test-Path $src) {
        if ($DryRun) {
            Write-Host "  [DRY] Would update: $file" -ForegroundColor Gray
        } else {
            Copy-Item $src $dst -Force
            Write-Host "  Updated: $file" -ForegroundColor Gray
        }
    }
}
Write-Host ""

# === STEP 4: COPY CATV6 EXTRAS ===
Write-Host "[4/7] Updating CatV6 extras..." -ForegroundColor Yellow
foreach ($file in $CATV6_EXTRAS) {
    $src = Join-Path $TEMP_DIR "catv6" $file
    $dst = Join-Path $FLINTV4_DIR $file
    if (Test-Path $src) {
        $dstDir = Split-Path $dst -Parent
        if (-not (Test-Path $dstDir)) {
            New-Item -ItemType Directory -Path $dstDir -Force | Out-Null
        }
        if ($DryRun) {
            Write-Host "  [DRY] Would update: $file" -ForegroundColor Gray
        } else {
            Copy-Item $src $dst -Force
            Write-Host "  Updated: $file" -ForegroundColor Gray
        }
    }
}
Write-Host ""

# === STEP 5: MERGE FOLDERS ===
Write-Host "[5/7] Merging folders..." -ForegroundColor Yellow
foreach ($folder in $MERGE_FOLDERS) {
    $pistonDir = Join-Path $TEMP_DIR "pistonware" $folder
    $catv6Dir  = Join-Path $TEMP_DIR "catv6" $folder
    $flintDir  = Join-Path $FLINTV4_DIR $folder

    # Get all files from both repos
    $pistonFiles = @()
    $catv6Files  = @()

    if (Test-Path $pistonDir) {
        $pistonFiles = Get-ChildItem $pistonDir -Recurse -File | ForEach-Object {
            $_.FullName.Replace($pistonDir, "").TrimStart("\", "/")
        }
    }
    if (Test-Path $catv6Dir) {
        $catv6Files = Get-ChildItem $catv6Dir -Recurse -File | ForEach-Object {
            $_.FullName.Replace($catv6Dir, "").TrimStart("\", "/")
        }
    }

    $allFiles = ($pistonFiles + $catv6Files) | Sort-Object -Unique
    $updated = 0

    foreach ($relPath in $allFiles) {
        $pistonSrc = Join-Path $pistonDir $relPath
        $catv6Src  = Join-Path $catv6Dir $relPath
        $dst       = Join-Path $flintDir $relPath

        # Determine source: prefer Pistonware for shared files, CatV6 for unique
        $src = $null
        $inPiston = Test-Path $pistonSrc
        $inCatv6  = Test-Path $catv6Src

        if ($inPiston -and $inCatv6) {
            # Both have it - use Pistonware as base (same as our merge strategy)
            $src = $pistonSrc
        } elseif ($inPiston) {
            $src = $pistonSrc
        } else {
            $src = $catv6Src
        }

        if ($src) {
            $dstDir = Split-Path $dst -Parent
            if (-not (Test-Path $dstDir)) {
                New-Item -ItemType Directory -Path $dstDir -Force | Out-Null
            }
            if ($DryRun) {
                if (-not (Test-Path $dst) -or (Get-Item $src).LastWriteTime -gt (Get-Item $dst).LastWriteTime) {
                    Write-Host "  [DRY] Would update: $folder/$relPath" -ForegroundColor Gray
                    $updated++
                }
            } else {
                Copy-Item $src $dst -Force
                $updated++
            }
        }
    }
    Write-Host "  $folder`: $updated files processed" -ForegroundColor Gray
}
Write-Host ""

# === STEP 6: REBRAND & REMOVE KEY SYSTEM ===
Write-Host "[6/7] Rebranding and removing key systems..." -ForegroundColor Yellow

if (-not $DryRun) {
    # Replace URLs in all Lua files
    $luaFiles = Get-ChildItem $FLINTV4_DIR -Recurse -Include "*.lua" | Where-Object { $_.FullName -notlike "*\.git*" }
    $rebrandCount = 0

    foreach ($file in $luaFiles) {
        $content = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
        if (-not $content) { continue }

        $original = $content

        # Rebrand URLs
        $content = $content -replace [regex]::Escape($OLD_URL), $NEW_URL
        $content = $content -replace [regex]::Escape($OLD_GITLAB), $NEW_GITRAW

        # Rebrand pistonware -> flintv4 in paths and strings
        $content = $content -replace "'pistonware/", "'flintv4/"
        $content = $content -replace '"pistonware/', '"flintv4/'
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

        # Remove key system patterns
        foreach ($pattern in $KEY_PATTERNS) {
            $content = $content -replace $pattern, ""
        }

        if ($content -ne $original) {
            Set-Content $file.FullName $content -NoNewline
            $rebrandCount++
        }
    }
    Write-Host "  Rebranded $rebrandCount files" -ForegroundColor Gray

    # Also update non-Lua files (loadstring, reinstall.lua already handled above)
    $textFiles = @("loadstring", "reinstall.lua")
    foreach ($tf in $textFiles) {
        $path = Join-Path $FLINTV4_DIR $tf
        if (Test-Path $path) {
            $content = Get-Content $path -Raw
            $content = $content -replace [regex]::Escape($OLD_URL), $NEW_URL
            Set-Content $path $content -NoNewline
        }
    }
} else {
    Write-Host "  [DRY] Would rebrand and clean key systems" -ForegroundColor Gray
}
Write-Host ""

# === STEP 7: COMMIT & PUSH ===
Write-Host "[7/7] Committing and pushing..." -ForegroundColor Yellow

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
