param(
    [ValidateSet('Debug','Release')]
    [string]$Configuration = 'Release'
)
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$cliProject = Join-Path $projectRoot 'kOS-GFOLD.Cli\kOS-GFOLD.Cli.csproj'
$cli = Join-Path $projectRoot "kOS-GFOLD.Cli\bin\$Configuration\kOS-GFOLD.Cli.exe"
$fixtures = Join-Path $PSScriptRoot 'fixtures'
$results = Join-Path $PSScriptRoot 'results'
$analyzer = Join-Path $projectRoot 'tools\analyze_gfold.py'

New-Item -ItemType Directory -Path $results -Force | Out-Null
dotnet msbuild $cliProject -p:Configuration=$Configuration -v:minimal
if ($LASTEXITCODE -ne 0) { throw 'CLI build failed' }
& $cli selftest
if ($LASTEXITCODE -ne 0) { throw 'Core self-test failed' }

foreach ($name in @('surface','pit')) {
    $scenario = Join-Path $fixtures "$name.json"
    $result = Join-Path $results "$name-result.json"
    & $cli solve --input $scenario --output $result
    if ($LASTEXITCODE -ne 0) { throw "$name solve failed" }
    $doc = Get-Content -Raw -LiteralPath $result | ConvertFrom-Json
    if (-not $doc.ok -or $doc.status -ne 'SOLVED') { throw "$name did not return SOLVED" }
    if ($doc.K.Count -ne 3 -or $doc.K[0].Count -ne 6) { throw "$name did not return a 3x6 LQR gain" }
    foreach ($point in $doc.trajectory) { if ($point.controlBefore.Count -ne 3 -or $point.controlAfter.Count -ne 3) { throw "$name omitted one-sided controls" } }
    $analysisDir = Join-Path $results $name
    python $analyzer --scenario $scenario --result $result --output-dir $analysisDir
    if ($LASTEXITCODE -ne 0) { throw "$name independent analysis failed" }
}

$sequenceResult = Join-Path $results 'sequence-result.json'
& $cli sequence --input (Join-Path $fixtures 'sequence.json') --output $sequenceResult
if ($LASTEXITCODE -ne 0) { throw 'Sequence solve failed' }
$sequence = Get-Content -Raw -LiteralPath $sequenceResult | ConvertFrom-Json
if (-not $sequence.ok -or $sequence.updates.Count -lt 1 -or -not $sequence.updates[0].ok) { throw 'Sequence result is incomplete' }
$initialK = $sequence.initialize.K | ConvertTo-Json -Compress
$updatedK = $sequence.updates[0].K | ConvertTo-Json -Compress
if ($initialK -cne $updatedK) { throw 'LQR gain changed across Update' }

$benchmarkResult = Join-Path $results 'benchmark-20x20-result.json'
& $cli solve --input (Join-Path $fixtures 'benchmark-20x20.json') --output $benchmarkResult
if ($LASTEXITCODE -ne 0) { throw '20-node/20-candidate benchmark failed' }
$benchmark = Get-Content -Raw -LiteralPath $benchmarkResult | ConvertFrom-Json
if (-not $benchmark.ok) { throw 'Benchmark did not return a validated trajectory' }
Write-Host ("20x20 benchmark: {0:F3} s, {1} evaluations" -f $benchmark.solveTime, $benchmark.searchEvaluations)

$closestResult = Join-Path $results 'closest-reachable-result.json'
& $cli solve --input (Join-Path $fixtures 'closest-reachable.json') --output $closestResult
if ($LASTEXITCODE -ne 0) { throw 'Closest-reachable solve failed' }
$closest = Get-Content -Raw -LiteralPath $closestResult | ConvertFrom-Json
if (-not $closest.ok -or $closest.landingError -lt 1.0 -or $closest.landingError -gt 50.01) { throw 'Closest-reachable result did not preserve the expected nonzero landing error' }

$invalidPath = Join-Path $results 'invalid-geometry.json'
$invalid = Get-Content -Raw -LiteralPath (Join-Path $fixtures 'surface.json') | ConvertFrom-Json
$invalid.targetPosition[1] = 1.0
$invalid | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $invalidPath -Encoding UTF8
& $cli solve --input $invalidPath --output (Join-Path $results 'invalid-result.json')
if ($LASTEXITCODE -ne 64) { throw 'Offset cylinder-floor target was not rejected as invalid input' }

$invalidLqrPath = Join-Path $results 'invalid-lqr.json'
$invalidLqr = Get-Content -Raw -LiteralPath (Join-Path $fixtures 'surface.json') | ConvertFrom-Json
$invalidLqr.lqrDt = 0.0
$invalidLqr | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $invalidLqrPath -Encoding UTF8
& $cli solve --input $invalidLqrPath --output (Join-Path $results 'invalid-lqr-result.json')
if ($LASTEXITCODE -ne 64) { throw 'Invalid LQR sample period was not rejected as invalid input' }

$invalidLqr.lqrDt = 0.1
$invalidLqr | Add-Member -NotePropertyName lqrLambda -NotePropertyValue 0.0 -Force
$invalidLqr | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $invalidLqrPath -Encoding UTF8
& $cli solve --input $invalidLqrPath --output (Join-Path $results 'invalid-lqr-result.json')
if ($LASTEXITCODE -ne 64) { throw 'Invalid LQR control weight was not rejected as invalid input' }

$invalidLqr.lqrLambda = 0.5
$invalidLqr | Add-Member -NotePropertyName lqrBeta -NotePropertyValue -1.0 -Force
$invalidLqr | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $invalidLqrPath -Encoding UTF8
& $cli solve --input $invalidLqrPath --output (Join-Path $results 'invalid-lqr-result.json')
if ($LASTEXITCODE -ne 64) { throw 'Invalid LQR velocity weight was not rejected as invalid input' }

Write-Host "GFOLD numerical tests passed. Results: $results"
