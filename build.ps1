<#
.SYNOPSIS
    Build win_ca.exe and win_dut.exe for the Windows DUT agent.

.DESCRIPTION
    Requires Visual Studio Build Tools 2019/2022 (or full Visual Studio)
    with the "Desktop development with C++" workload and a Windows SDK.

    The original projects are Visual Studio 2010 / Win32 projects. MSBuild
    from a newer Visual Studio can build them by selecting a newer toolset.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\build.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\build.ps1 -Configuration Debug -Toolset v142
#>
[CmdletBinding()]
param(
    [ValidateSet('Release', 'Debug')]
    [string]$Configuration = 'Release',

    [ValidateSet('Win32')]
    [string]$Platform = 'Win32',

    # Leave empty to auto-detect v143/v142/v141 from the MSBuild path.
    [string]$Toolset = ''
)

$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$distDir = Join-Path $scriptRoot 'dist'

Write-Host "Project root : $scriptRoot"
Write-Host "Configuration: $Configuration"
Write-Host "Platform     : $Platform"
Write-Host ""

function Get-MSBuildPath {
    $programFilesX86 = [Environment]::GetFolderPath('ProgramFilesX86')
    $vswhere = Join-Path $programFilesX86 'Microsoft Visual Studio\Installer\vswhere.exe'

    if (Test-Path $vswhere) {
        $found = & $vswhere -latest -products * -requires Microsoft.Component.MSBuild `
            -find 'MSBuild\**\Bin\MSBuild.exe' 2>$null
        if ($found) {
            $first = @($found)[0]
            if (Test-Path $first) {
                return $first
            }
        }
    }

    $candidates = @(
        (Join-Path $env:ProgramFiles 'Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe'),
        (Join-Path $programFilesX86 'Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe'),
        (Join-Path $env:ProgramFiles 'Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe'),
        (Join-Path $programFilesX86 'Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe'),
        (Join-Path $programFilesX86 'Microsoft Visual Studio\2019\BuildTools\MSBuild\Current\Bin\MSBuild.exe'),
        (Join-Path $env:ProgramFiles 'Microsoft Visual Studio\2019\Community\MSBuild\Current\Bin\MSBuild.exe'),
        (Join-Path $programFilesX86 'Microsoft Visual Studio\2019\Community\MSBuild\Current\Bin\MSBuild.exe')
    )

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path $candidate)) {
            return $candidate
        }
    }

    return $null
}

function Get-DefaultToolset {
    param([string]$MSBuildPath)

    if ($MSBuildPath -match '\\2022\\') { return 'v143' }
    if ($MSBuildPath -match '\\2019\\') { return 'v142' }
    if ($MSBuildPath -match '\\2017\\') { return 'v141' }
    return ''
}

function Find-SdkFile {
    param(
        [string]$SdkRoot,
        [string]$RelativePath
    )

    if (-not (Test-Path $SdkRoot)) { return $null }

    $separator = $RelativePath.IndexOf('\')
    if ($separator -lt 1) { return $null }

    $topLevel = $RelativePath.Substring(0, $separator)
    $remainder = $RelativePath.Substring($separator + 1)
    $versionDirs = Get-ChildItem (Join-Path $SdkRoot $topLevel) -Directory -ErrorAction SilentlyContinue

    foreach ($versionDir in $versionDirs) {
        $candidate = Join-Path $versionDir.FullName $remainder
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    return $null
}

$msbuild = Get-MSBuildPath
if (-not $msbuild) {
    Write-Host "MSBuild was not found." -ForegroundColor Red
    Write-Host ""
    Write-Host "Install Visual Studio Build Tools first (run as Administrator):"
    Write-Host "  https://aka.ms/vs/17/release/vs_buildtools.exe"
    Write-Host ""
    Write-Host "Silent install example:"
    Write-Host '  .\vs_buildtools.exe --wait --norestart --nocache --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended'
    Write-Host ""
    Write-Host "Or install full Visual Studio and select 'Desktop development with C++'."
    exit 1
}

if (-not $Toolset) {
    $Toolset = Get-DefaultToolset -MSBuildPath $msbuild
}

Write-Host "MSBuild : $msbuild"
if ($Toolset) {
    Write-Host "Toolset : $Toolset"
} else {
    Write-Host "Toolset : (project default)"
}
Write-Host ""

# ---------------------------------------------------------------------------
# Prerequisite checks (warnings only; the compiler will report real errors)
# ---------------------------------------------------------------------------
$sdkRoot = Join-Path ([Environment]::GetFolderPath('ProgramFilesX86')) 'Windows Kits\10'
$trafficLib = Find-SdkFile -SdkRoot $sdkRoot -RelativePath 'Lib\um\x86\Traffic.lib'
$ntddndis   = Find-SdkFile -SdkRoot $sdkRoot -RelativePath 'Include\um\NtDDNdis.h'

if (-not $trafficLib) {
    Write-Warning "Traffic.lib was not found in the Windows SDK (Lib\<version>\um\x86)."
    Write-Warning "Install the Windows 10/11 SDK component. Linking win_dut will fail without it."
} else {
    Write-Host "Traffic.lib : $trafficLib"
}

if (-not $ntddndis) {
    Write-Warning "NtDDNdis.h was not found in the Windows SDK (Include\<version>\um)."
    Write-Warning "If compilation fails, install the WDK or add a compatibility definition."
} else {
    Write-Host "NtDDNdis.h : $ntddndis"
}

$pthreadLib = Join-Path $scriptRoot 'external\pthreadlib\lib\pthreadVSE2.lib'
if (-not (Test-Path $pthreadLib)) {
    Write-Warning "pthreadVSE2.lib was not found at $pthreadLib."
}

$pthreadDll = Get-ChildItem $scriptRoot -Recurse -Filter 'pthreadVSE2.dll' -File -ErrorAction SilentlyContinue |
    Select-Object -First 1

if (-not $pthreadDll) {
    foreach ($dir in ($env:PATH -split ';')) {
        if (-not $dir) { continue }
        $candidate = Join-Path $dir 'pthreadVSE2.dll'
        if (Test-Path $candidate) {
            $pthreadDll = Get-Item $candidate
            break
        }
    }
}

if (-not $pthreadDll) {
    Write-Warning "pthreadVSE2.dll was not found. The repo only contains the .lib import library."
    Write-Warning "If the exe fails to start with a missing-DLL error, copy pthreadVSE2.dll next to it."
} else {
    Write-Host "pthread DLL : $($pthreadDll.FullName)"
}
Write-Host ""

# ---------------------------------------------------------------------------
# Build both solutions
# ---------------------------------------------------------------------------
$solutions = @(
    (Join-Path $scriptRoot 'win_ca\win_ca.sln'),
    (Join-Path $scriptRoot 'win_dut\win_dut.sln')
)

foreach ($solution in $solutions) {
    if (-not (Test-Path $solution)) {
        throw "Solution not found: $solution"
    }

    $msbuildArgs = @(
        $solution,
        '/m',
        '/t:Rebuild',
        "/p:Configuration=$Configuration",
        "/p:Platform=$Platform"
    )
    if ($Toolset) {
        $msbuildArgs += "/p:PlatformToolset=$Toolset"
    }

    Write-Host "==== Building $solution ====" -ForegroundColor Cyan
    & $msbuild @msbuildArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Build failed with exit code $LASTEXITCODE : $solution"
    }
    Write-Host ""
}

# ---------------------------------------------------------------------------
# Collect outputs
# ---------------------------------------------------------------------------
New-Item -ItemType Directory -Force -Path $distDir | Out-Null

foreach ($exeName in @('win_ca.exe', 'win_dut.exe')) {
    $exe = Get-ChildItem $scriptRoot -Recurse -Filter $exeName -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notlike "$distDir*" } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if (-not $exe) {
        throw "Build completed but $exeName was not found."
    }

    Copy-Item $exe.FullName (Join-Path $distDir $exeName) -Force
    Write-Host "Output: $($exe.FullName) -> dist\$exeName"
}

if ($pthreadDll) {
    Copy-Item $pthreadDll.FullName (Join-Path $distDir 'pthreadVSE2.dll') -Force
    Write-Host "Copied pthreadVSE2.dll to dist\"
}

$myping = Join-Path $scriptRoot 'Tools\myping\Release\myping.exe'
if (Test-Path $myping) {
    Copy-Item $myping (Join-Path $distDir 'myping.exe') -Force
    Write-Host "Copied myping.exe to dist\"
}

Write-Host ""
Write-Host "Build finished. Output directory: $distDir" -ForegroundColor Green
Get-ChildItem $distDir | Format-Table Name, Length, LastWriteTime -AutoSize

exit 0
