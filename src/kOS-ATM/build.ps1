[CmdletBinding()]
param(
    [string]$KspRoot = 'D:/opt/entertainments/Steam/steamapps/common/KSP_instances/KSP_main_Sol/Kerbal Space Program',
    [string]$ReferenceRoot = '',
    [switch]$RunTests
)
$ErrorActionPreference = 'Stop'
if (-not $ReferenceRoot) { $ReferenceRoot = Join-Path $PSScriptRoot 'references' }
$srcRoot = Split-Path $PSScriptRoot -Parent
$repoRoot = Split-Path $srcRoot -Parent
$managedPath = Join-Path $KspRoot 'KSP_x64_Data/Managed'
$frameworkPath = Join-Path ([Environment]::GetFolderPath('ProgramFilesX86')) 'Reference Assemblies/Microsoft/Framework/.NETFramework/v4.8'
$artifactsPath = Join-Path $PSScriptRoot 'artifacts'
$null = New-Item -ItemType Directory -Force -Path $artifactsPath
$sdkLine = (& dotnet --list-sdks | Select-Object -Last 1)
if ($sdkLine -notmatch '^([^ ]+) \[(.+)\]$') { throw 'A .NET SDK with Roslyn is required.' }
$compilerPath = Join-Path $Matches[2] ($Matches[1] + '/Roslyn/bincore/csc.dll')
$baseRefs = @()
foreach ($name in @('mscorlib.dll','System.dll','System.Core.dll')) { $baseRefs += Join-Path $frameworkPath $name }
$gameRefs = @()
foreach ($name in @('Assembly-CSharp.dll','Assembly-CSharp-firstpass.dll','UnityEngine.dll','UnityEngine.CoreModule.dll')) { $gameRefs += Join-Path $managedPath $name }
foreach ($name in @('kOS.dll','kOS.Safe.dll')) { $gameRefs += Join-Path $KspRoot ('GameData/kOS/Plugins/' + $name) }
$aeroRefs = @()
foreach ($spec in @(
    @('Unity.Mathematics.dll','000_KSPBurst/Plugins/Unity.Mathematics.dll'),
    @('FerramAerospaceResearch.dll','FerramAerospaceResearch/Plugins/FerramAerospaceResearch.dll'),
    @('FerramAerospaceResearch.Base.dll','FerramAerospaceResearch/Plugins/FerramAerospaceResearch.Base.dll'))) {
    $localPath = Join-Path $ReferenceRoot $spec[0]
    if (Test-Path -LiteralPath $localPath) { $aeroRefs += $localPath }
    else { $aeroRefs += Join-Path $KspRoot ('GameData/' + $spec[1]) }
}
function Invoke-Compiler([string]$Output, [string[]]$Sources, [string[]]$References, [string]$Target = 'library', [string]$EntryPoint = '') {
    $null = New-Item -ItemType Directory -Force -Path (Split-Path $Output -Parent)
    $compilerArgs = @('/nologo',('/target:' + $Target),'/langversion:7.3','/nostdlib+','/optimize+','/warn:4','/warnaserror+',('/out:' + $Output))
    foreach ($refPath in $References) {
        if (-not (Test-Path -LiteralPath $refPath)) { throw "Missing reference: $refPath" }
        $compilerArgs += '/r:' + $refPath
    }
    if ($EntryPoint) { $compilerArgs += '/main:' + $EntryPoint }
    $compilerArgs += $Sources
    & dotnet $compilerPath @compilerArgs
    if ($LASTEXITCODE -ne 0) { throw "Compilation failed: $Output" }
}
$atmSources = @('ManagedMath.cs','AtmosphereSnapshot.cs','AtmosphereCapture.cs','ATMAddon.cs','Properties/AssemblyInfo.cs') | ForEach-Object { Join-Path $PSScriptRoot $_ }
$atmDll = Join-Path $PSScriptRoot 'bin/Release/kOS-ATM.dll'
Invoke-Compiler $atmDll $atmSources ($baseRefs + $gameRefs)
foreach ($kind in @('AFS','LTR')) {
    $projectPath = Join-Path $srcRoot ("kOS-$kind/kOS-$kind")
    $sources = @(($kind + '.cs'),($kind + 'Addon.cs'),'Properties/AssemblyInfo.cs') | ForEach-Object { Join-Path $projectPath $_ }
    Invoke-Compiler (Join-Path $projectPath "bin/Release/kOS-$kind.dll") $sources ($baseRefs + $gameRefs + $aeroRefs + $atmDll)
}
if ($RunTests) {
    $testExe = Join-Path $artifactsPath 'AtmosphereTests.exe'
    Invoke-Compiler $testExe @((Join-Path $PSScriptRoot 'ManagedMath.cs'),(Join-Path $PSScriptRoot 'AtmosphereSnapshot.cs'),(Join-Path $PSScriptRoot 'tests/AtmosphereTests.cs')) $baseRefs 'exe'
    & $testExe
    if ($LASTEXITCODE -ne 0) { throw 'Managed atmosphere tests failed.' }
    $predictorExe = Join-Path $artifactsPath 'PredictorTests.exe'
    $predictorSources = @('ManagedMath.cs','AtmosphereSnapshot.cs','tests/AtmosphereTests.cs','tests/PredictorTests.cs') | ForEach-Object { Join-Path $PSScriptRoot $_ }
    $predictorSources += Join-Path $srcRoot 'kOS-AFS/kOS-AFS/AFS.cs'
    $predictorSources += Join-Path $srcRoot 'kOS-LTR/kOS-LTR/LTR.cs'
    Invoke-Compiler $predictorExe $predictorSources ($baseRefs + $gameRefs + $aeroRefs) 'exe' 'PredictorTests'
    foreach ($refPath in ($gameRefs + $aeroRefs)) { Copy-Item -LiteralPath $refPath -Destination $artifactsPath -Force }
    & $predictorExe
    if ($LASTEXITCODE -ne 0) { throw 'AFS/LTR predictor tests failed.' }
    $scriptTestExe = Join-Path $artifactsPath 'ScriptCompileTests.exe'
    Invoke-Compiler $scriptTestExe @((Join-Path $PSScriptRoot 'tests/ScriptCompileTests.cs')) ($baseRefs + (Join-Path $KspRoot 'GameData/kOS/Plugins/kOS.Safe.dll')) 'exe'
    & $scriptTestExe $repoRoot
    if ($LASTEXITCODE -ne 0) { throw 'Installed kOS compiler rejected a script.' }
    & python (Join-Path $PSScriptRoot 'tests/check_integration.py')
    if ($LASTEXITCODE -ne 0) { throw 'Integration and KerboScript identifier checks failed.' }
}
$packagePath = Join-Path $artifactsPath 'package'
foreach ($kind in @('ATM','AFS','LTR')) {
    $sourceDll = if ($kind -eq 'ATM') { $atmDll } else { Join-Path $srcRoot "kOS-$kind/kOS-$kind/bin/Release/kOS-$kind.dll" }
    $destination = Join-Path $packagePath "GameData/kOS-$kind/Plugins"
    $null = New-Item -ItemType Directory -Force -Path $destination
    Copy-Item -LiteralPath $sourceDll -Destination $destination -Force
}
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'README.md') -Destination (Join-Path $packagePath 'INSTALL.md') -Force
$scriptPaths = @('boot/atm_check.ks','uentry.ks','lib/atm_utils.ks','lib/edllib/uentry_core.ks','lib/edllib/gui_utils.ks','Falcon9_lib/f9utility.ks')
foreach ($rel in $scriptPaths) {
    $destination = Join-Path $packagePath ('Script/' + $rel)
    $null = New-Item -ItemType Directory -Force -Path (Split-Path $destination -Parent)
    Copy-Item -LiteralPath (Join-Path $repoRoot ('Script/' + $rel)) -Destination $destination -Force
}
$manifest = @()
foreach ($path in ($baseRefs + $gameRefs + $aeroRefs + $atmDll)) {
    $manifest += [ordered]@{ path = $path; sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash }
}
$manifest | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $artifactsPath 'build-references.json') -Encoding UTF8
$archivePath = Join-Path $artifactsPath 'kOS-ATM-integration.zip'
Compress-Archive -Path (Join-Path $packagePath '*') -DestinationPath $archivePath -Force
if ($RunTests) {
    & python (Join-Path $PSScriptRoot 'tests/check_package.py') $archivePath
    if ($LASTEXITCODE -ne 0) { throw 'Package validation failed.' }
}
Write-Output "Built and packaged: $archivePath"
Write-Output 'With KSP closed, replace all three addon DLLs and copy the included Script files to the kOS archive.'
