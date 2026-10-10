[CmdletBinding()]
param(
    [string]$KspRoot = 'D:/opt/entertainments/Steam/steamapps/common/KSP_instances/KSP_main_Sol/Kerbal Space Program',
    [switch]$RunTests
)
$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot
$compilerPath = Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
$managedPath = Join-Path $KspRoot 'KSP_x64_Data/Managed'
$outputPath = Join-Path $projectRoot 'bin/Release'
$artifactPath = Join-Path $projectRoot 'artifacts'
$pluginPath = Join-Path $artifactPath 'GameData/KSPAtmosphereResearch'
$null = New-Item -ItemType Directory -Force -Path $outputPath, $pluginPath
$referenceNames = @('Assembly-CSharp.dll', 'Assembly-CSharp-firstpass.dll', 'UnityEngine.dll', 'UnityEngine.CoreModule.dll', 'UnityEngine.UI.dll', 'UnityEngine.IMGUIModule.dll')
$compilerArgs = @('/nologo', '/target:library', '/optimize+', '/warn:4', '/warnaserror+', ('/out:' + (Join-Path $outputPath 'KSP-AtmosphereResearch.dll')))
foreach ($referenceName in $referenceNames) {
    $referencePath = Join-Path $managedPath $referenceName
    if (-not (Test-Path -LiteralPath $referencePath)) { throw "Missing KSP reference: $referencePath" }
    $compilerArgs += '/r:' + $referencePath
}
$sourceNames = @('AtmosphereApi.cs', 'ModCandidates.cs', 'FlightRecorder.cs', 'ThermalSnapshot.cs', 'NativeBenchmark.cs', 'Properties/AssemblyInfo.cs')
foreach ($sourceName in $sourceNames) { $compilerArgs += Join-Path $projectRoot $sourceName }
& $compilerPath @compilerArgs
if ($LASTEXITCODE -ne 0) { throw "C# compilation failed ($LASTEXITCODE)" }
if ($RunTests) {
    $testPath = Join-Path $artifactPath 'ApiContractTests.exe'
    & $compilerPath /nologo /warn:4 /warnaserror+ ('/out:' + $testPath) (Join-Path $projectRoot 'AtmosphereApi.cs') (Join-Path $projectRoot 'tools/ApiContractTests.cs')
    if ($LASTEXITCODE -ne 0) { throw 'API contract test compilation failed' }
    & $testPath
    if ($LASTEXITCODE -ne 0) { throw 'API contract tests failed' }
    $thermalTestPath = Join-Path $artifactPath 'ThermalSnapshotTests.exe'
    & $compilerPath /nologo /warn:4 /warnaserror+ ('/out:' + $thermalTestPath) (Join-Path $projectRoot 'ThermalSnapshot.cs') (Join-Path $projectRoot 'tools/ThermalSnapshotTests.cs')
    if ($LASTEXITCODE -ne 0) { throw 'Thermal snapshot test compilation failed' }
    & $thermalTestPath
    if ($LASTEXITCODE -ne 0) { throw 'Thermal snapshot tests failed' }
    & python -m unittest discover -s (Join-Path $projectRoot 'tools') -p 'test_*.py' -v
    if ($LASTEXITCODE -ne 0) { throw 'CSV comparison tests failed' }
}
Copy-Item -LiteralPath (Join-Path $outputPath 'KSP-AtmosphereResearch.dll') -Destination $pluginPath -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'packaging/AtmosphereResearch.cfg') -Destination $pluginPath -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'docs/FlightTest.md') -Destination $pluginPath -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'docs/NativeBenchmark.md') -Destination $pluginPath -Force
$archivePath = Join-Path $artifactPath 'KSP-AtmosphereResearch.zip'
Compress-Archive -LiteralPath $pluginPath -DestinationPath $archivePath -Force
Write-Output "Built: $archivePath"
Write-Output 'Extract the ZIP into GameData with KSP closed, then start KSP and enter flight.'
