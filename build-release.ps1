#Requires -Version 5.1
<#
.SYNOPSIS
Build and package Chris GNC Suite using the published distribution layout.
.EXAMPLE
powershell -NoProfile -ExecutionPolicy Bypass -File build-release.ps1 -Version 1.0.5
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^\d+\.\d+\.\d+(?:-[A-Za-z0-9]+(?:[.-][A-Za-z0-9]+)*)?$')]
    [string]$Version,
    [string]$KspRoot = 'D:/opt/entertainments/Steam/steamapps/common/KSP_instances/KSP_main_Sol/Kerbal Space Program',
    [string]$ReferenceRoot = '',
    [string]$OutputRoot = '',
    [switch]$SkipTests,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$repoRoot = $PSScriptRoot
if (-not $OutputRoot) { $OutputRoot = Join-Path $repoRoot 'dist' }
$outputDirectory = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputRoot)
$outputPrefix = $outputDirectory.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
$packageName = "Chris_GNC_Suite-v$Version"
$packagePath = Join-Path $outputDirectory $packageName
$archivePath = Join-Path $outputDirectory ($packageName + '.zip')
$checksumPath = $archivePath + '.sha256'

function Remove-OutputPath([string]$TargetPath) {
    $absoluteTarget = [IO.Path]::GetFullPath($TargetPath)
    if (-not $absoluteTarget.StartsWith($outputPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove a path outside the output directory: $absoluteTarget"
    }
    if (Test-Path -LiteralPath $absoluteTarget) {
        $item = Get-Item -LiteralPath $absoluteTarget -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "Refusing to remove a linked output path: $absoluteTarget"
        }
        Remove-Item -LiteralPath $absoluteTarget -Recurse -Force
    }
}

foreach ($targetPath in @($packagePath, $archivePath, $checksumPath)) {
    if ((Test-Path -LiteralPath $targetPath) -and -not $Force) {
        throw "Output already exists: $targetPath. Use -Force to replace this version or choose another output directory."
    }
}

# Read tracked paths, but copy current working-tree content, including release edits.
# Local boot scripts, caches, sources and dependency DLLs are not distribution files.
Push-Location -LiteralPath $repoRoot
try {
    $contentPaths = @(& git -c core.quotepath=false ls-files -- Script docs crafts)
    if ($LASTEXITCODE -ne 0 -or $contentPaths.Count -eq 0) {
        throw 'Cannot enumerate release content. Run this script from a Git checkout with Git installed.'
    }
}
finally { Pop-Location }

$buildArguments = @{ KspRoot = $KspRoot; RunTests = (-not $SkipTests) }
if ($ReferenceRoot) { $buildArguments.ReferenceRoot = $ReferenceRoot }
if ($SkipTests) { Write-Warning 'Release validation tests were explicitly skipped.' }
& (Join-Path $repoRoot 'src/kOS-ATM/build.ps1') @buildArguments

$null = New-Item -ItemType Directory -Path $outputDirectory -Force
$stageRoot = Join-Path $outputDirectory ($packageName + '.staging-' + [Guid]::NewGuid().ToString('N'))
$stagePath = Join-Path $stageRoot $packageName
$stageArchive = $stageRoot + '.zip'
$stageChecksum = $stageArchive + '.sha256'
try {
    $null = New-Item -ItemType Directory -Path $stagePath -Force
    foreach ($relativePath in $contentPaths) {
        $destinationRelative = if ($relativePath.StartsWith('Script/')) { 'Ships/' + $relativePath } else { $relativePath }
        $destinationPath = Join-Path $stagePath $destinationRelative
        $null = New-Item -ItemType Directory -Path (Split-Path $destinationPath -Parent) -Force
        Copy-Item -LiteralPath (Join-Path $repoRoot $relativePath) -Destination $destinationPath
    }
    foreach ($rootFile in @('README.md', 'README_中文.md', 'Changelog.md', '更新日志.md', 'LICENSE', 'INSTALL.md', 'BUILDING.md')) {
        Copy-Item -LiteralPath (Join-Path $repoRoot $rootFile) -Destination (Join-Path $stagePath $rootFile)
    }
    foreach ($kind in @('ATM', 'AFS', 'LTR')) {
        $dllRelative = if ($kind -eq 'ATM') { 'src/kOS-ATM/bin/Release/kOS-ATM.dll' } else { "src/kOS-$kind/kOS-$kind/bin/Release/kOS-$kind.dll" }
        $pluginPath = Join-Path $stagePath "GameData/kOS-Addons/$kind"
        $null = New-Item -ItemType Directory -Path $pluginPath -Force
        Copy-Item -LiteralPath (Join-Path $repoRoot $dllRelative) -Destination $pluginPath
    }

    $packageFiles = @(Get-ChildItem -LiteralPath $stagePath -File -Recurse)
    $expectedNames = @($packageFiles | ForEach-Object { $_.FullName.Substring($stagePath.Length + 1).Replace('\', '/') })
    $expectedDlls = @('GameData/kOS-Addons/ATM/kOS-ATM.dll', 'GameData/kOS-Addons/AFS/kOS-AFS.dll', 'GameData/kOS-Addons/LTR/kOS-LTR.dll')
    $actualDlls = @($expectedNames | Where-Object { $_.EndsWith('.dll', [StringComparison]::OrdinalIgnoreCase) })
    if (Compare-Object $expectedDlls $actualDlls) { throw 'Package must contain exactly the three suite addon DLLs.' }

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::CreateFromDirectory($stageRoot, $stageArchive, [IO.Compression.CompressionLevel]::Optimal, $false)
    $zip = [IO.Compression.ZipFile]::OpenRead($stageArchive)
    try {
        $archiveNames = @($zip.Entries | Where-Object { $_.Name } | ForEach-Object { $_.FullName.Replace('\', '/') })
        $expectedArchiveNames = @($expectedNames | ForEach-Object { $packageName + '/' + $_ })
        if (Compare-Object $expectedArchiveNames $archiveNames) { throw 'ZIP contents do not match the staged distribution.' }
    }
    finally { $zip.Dispose() }
    $archiveHash = (Get-FileHash -LiteralPath $stageArchive -Algorithm SHA256).Hash.ToLowerInvariant()
    "$archiveHash  $packageName.zip" | Set-Content -LiteralPath $stageChecksum -Encoding ASCII

    # Replace previous output only after compilation, checks and ZIP creation succeed.
    foreach ($targetPath in @($packagePath, $archivePath, $checksumPath)) {
        if ($Force) { Remove-OutputPath $targetPath }
        elseif (Test-Path -LiteralPath $targetPath) { throw "Output appeared during the build: $targetPath" }
    }
    Move-Item -LiteralPath $stagePath -Destination $packagePath
    Move-Item -LiteralPath $stageArchive -Destination $archivePath
    Move-Item -LiteralPath $stageChecksum -Destination $checksumPath
}
finally {
    foreach ($temporaryPath in @($stageRoot, $stageArchive, $stageChecksum)) { Remove-OutputPath $temporaryPath }
}

Write-Output "Distribution: $packagePath"
Write-Output "Archive: $archivePath"
Write-Output "SHA256: $checksumPath"
