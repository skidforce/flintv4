<#
.SYNOPSIS
    Generates the next SkidV5 version using clean semver (major.minor.patch)
    instead of a random-looking timestamp.
.DESCRIPTION
    Reads the current version from version.txt, bumps it (patch by default,
    or major/minor with the matching switch), and writes the result back to
    both the repo root version.txt and profiles/version.txt (where the GUI
    displays it). If the existing version is not valid semver (e.g. a legacy
    timestamp), a clean baseline of 1.0.0 is used.
.PARAMETER Major
    Bump the major version (X.0.0).
.PARAMETER Minor
    Bump the minor version (X.Y.0).
.PARAMETER Patch
    Bump the patch version (X.Y.Z). This is the default.
.PARAMETER Set
    Write an exact version instead of bumping, e.g. -Set "2.1.0".
.PARAMETER RepoDir
    Path to the repo. Defaults to this script's directory.
.EXAMPLE
    .\make-version.ps1
    .\make-version.ps1 -Minor
    .\make-version.ps1 -Major
    .\make-version.ps1 -Set 2.0.0
#>

param(
    [switch]$Major,
    [switch]$Minor,
    [switch]$Patch,
    [string]$Set,
    [string]$RepoDir = (Split-Path -Parent $MyInvocation.MyCommand.Path)
)

$ErrorActionPreference = "Stop"

$VERSION_FILE    = Join-Path $RepoDir "version.txt"
$PROFILES_VERSION = Join-Path (Join-Path $RepoDir "profiles") "version.txt"

function Get-CurrentVersion {
    if (Test-Path $VERSION_FILE) {
        $raw = (Get-Content $VERSION_FILE -Raw).Trim()
        if ($raw -match '^(\d+)\.(\d+)\.(\d+)$') {
            return [PSCustomObject]@{
                Major = [int]$Matches[1]
                Minor = [int]$Matches[2]
                Patch = [int]$Matches[3]
            }
        }
    }
    # No file or a legacy timestamp: start from a clean baseline
    return [PSCustomObject]@{ Major = 1; Minor = 0; Patch = 0 }
}

function Write-VersionFile {
    param([string]$Version)
    Set-Content $VERSION_FILE $Version -NoNewline
    $profilesDir = Split-Path $PROFILES_VERSION -Parent
    if (-not (Test-Path $profilesDir)) {
        New-Item -ItemType Directory -Path $profilesDir -Force | Out-Null
    }
    Set-Content $PROFILES_VERSION $Version -NoNewline
}

$current = Get-CurrentVersion

if ($Set) {
    if ($Set -notmatch '^(\d+)\.(\d+)\.(\d+)$') {
        throw "Invalid version '$Set' - expected major.minor.patch (e.g. 2.1.0)"
    }
    $newVersion = $Set
} elseif ($Major) {
    $newVersion = "$($current.Major + 1).0.0"
} elseif ($Minor) {
    $newVersion = "$($current.Major).$($current.Minor + 1).0"
} else {
    $newVersion = "$($current.Major).$($current.Minor).$($current.Patch + 1)"
}

Write-VersionFile $newVersion
Write-Host "Version: $newVersion" -ForegroundColor Green
# Emit to the pipeline so callers (combine-updates.ps1) can capture it
$newVersion
