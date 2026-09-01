$ErrorActionPreference = 'Stop'

function Assert-Near([double]$Actual, [double]$Expected, [double]$Tolerance, [string]$Label) {
    if ([Math]::Abs($Actual - $Expected) -gt $Tolerance) {
        throw "${Label}: expected $Expected, got $Actual"
    }
}

function Dot($Left, $Right) {
    return $Left[0] * $Right[0] + $Left[1] * $Right[1] + $Left[2] * $Right[2]
}

function Map-Basis($InputVector, $Source, $Destination) {
    [double]$eastComponent = Dot $Source.east $InputVector
    [double]$upComponent = Dot $Source.up $InputVector
    [double]$northComponent = Dot $Source.north $InputVector
    return [double[]]@(
        ($Destination.east[0] * $eastComponent + $Destination.up[0] * $upComponent + $Destination.north[0] * $northComponent),
        ($Destination.east[1] * $eastComponent + $Destination.up[1] * $upComponent + $Destination.north[1] * $northComponent),
        ($Destination.east[2] * $eastComponent + $Destination.up[2] * $upComponent + $Destination.north[2] * $northComponent)
    )
}

# A physical 0.4..1 throttle range with ten-percent span margins is 0.46..0.94.
$physicalMinimum = 0.4
$margin = 0.1
Assert-Near ($physicalMinimum + (1 - $physicalMinimum) * $margin) 0.46 1e-12 'safe minimum throttle'
Assert-Near (1 - (1 - $physicalMinimum) * $margin) 0.94 1e-12 'safe maximum throttle'

# 100 + (-10)t + 0.5(-2)t^2 = 50 has the positive root -5 + 5*sqrt(3).
$heightOffset = 50.0
$verticalRate = -10.0
$verticalAcceleration = -2.0
$discriminant = $verticalRate * $verticalRate - 2 * $verticalAcceleration * $heightOffset
$intercept = (-$verticalRate - [Math]::Sqrt($discriminant)) / $verticalAcceleration
Assert-Near $intercept (-5 + 5 * [Math]::Sqrt(3)) 1e-12 'altitude intercept'

# Verify current->frozen->current basis mapping is lossless for orthonormal axes.
$currentBasis = @{
    east = [double[]]@(1,0,0)
    up = [double[]]@(0,1,0)
    north = [double[]]@(0,0,1)
}
$frozenBasis = @{
    east = [double[]]@(0,1,0)
    up = [double[]]@(-1,0,0)
    north = [double[]]@(0,0,1)
}
$sample = [double[]]@(2,-3,5)
$mapped = Map-Basis $sample $currentBasis $frozenBasis
$roundTrip = Map-Basis $mapped $frozenBasis $currentBasis
for ($index = 0; $index -lt 3; $index++) {
    Assert-Near $roundTrip[$index] $sample[$index] 1e-12 "basis round trip component $index"
}

# Verify row-major 3x6 multiplication and default-overlay precedence.
$gain = @(
    @(1,2,3,4,5,6),
    @(0,1,0,1,0,1),
    @(-1,0,1,0,-1,0)
)
$stateError = @(1,2,3,4,5,6)
$expectedControl = @(91,12,-3)
for ($row = 0; $row -lt 3; $row++) {
    $sum = 0.0
    for ($column = 0; $column -lt 6; $column++) {
        $sum += $gain[$row][$column] * $stateError[$column]
    }
    Assert-Near $sum $expectedControl[$row] 1e-12 "gain row $row"
}

$defaults = @{ gfold_lqrLambda = 0.5; gfold_nodes = 20; gfold_epsilon = 0.15 }
$configured = @{ gfold_lqrLambda = 2.0 }
foreach ($entry in $defaults.GetEnumerator()) {
    if (-not $configured.ContainsKey($entry.Key)) { $configured[$entry.Key] = $entry.Value }
}
Assert-Near $configured.gfold_lqrLambda 2.0 0 'explicit configuration precedence'
Assert-Near $configured.gfold_nodes 20 0 'missing default insertion'
Assert-Near $configured.gfold_epsilon 0.15 0 'aerodynamic gate default'

# Independent scalar check of the analytical quadratic lookahead used for the
# future GFOLD initialization state.
$lookahead = 3.0
$predictedPosition = 100 + (-10) * $lookahead + 0.5 * 2 * $lookahead * $lookahead + (0.5 / 6) * [Math]::Pow($lookahead, 3) + (0.2 / 24) * [Math]::Pow($lookahead, 4)
$predictedVelocity = -10 + 2 * $lookahead + 0.5 * 0.5 * $lookahead * $lookahead + (0.2 / 6) * [Math]::Pow($lookahead, 3)
Assert-Near $predictedPosition 81.925 1e-12 'quadratic future position'
Assert-Near $predictedVelocity -0.85 1e-12 'quadratic future velocity'

# Measured acceleration 5 minus gravity -10 and achieved thrust 14 leaves
# aerodynamic acceleration 1; relative to 20 available this is a 0.05 gate.
$aerodynamicRatio = [Math]::Abs(5 - (-10) - 14) / 20
Assert-Near $aerodynamicRatio 0.05 1e-12 'aerodynamic disturbance ratio'

# The boot value is measured from powered-guidance entry while GFOLD expects
# an event time relative to its future initialization state.
function Get-GfoldSwitchDelay(
    [bool]$AlreadySwitched,
    [double]$ConfiguredDuration,
    [double]$FutureEpoch,
    [double]$BurnStartEpoch
) {
    if ($AlreadySwitched) { return 0.0 }
    return [Math]::Max(0.0, $ConfiguredDuration - ($FutureEpoch - $BurnStartEpoch))
}
Assert-Near (Get-GfoldSwitchDelay $false 10 106 100) 4 0 'future engine switch delay'
Assert-Near (Get-GfoldSwitchDelay $false 5 106 100) 0 0 'elapsed engine switch delay'
Assert-Near (Get-GfoldSwitchDelay $true 10 102 100) 0 0 'already switched delay'

# Powered descent must retain the initialization trajectory. The addon still
# exposes Update for other callers, but BORG must not invoke it in flight.
$landingSource = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot '..\f9landingburn.ks')
$defaultsSource = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot '..\GFOLD_defaults.ks')
if ($defaultsSource -notmatch '(?i)"gfold_epsilon"\s*,\s*0\.15') {
    throw 'GFOLD defaults do not define gfold_epsilon = 0.15'
}
if ($landingSource -match '(?i)gfoldAddonRef\s*:\s*(AsyncUpdate|Update)\s*\(') {
    throw 'BORG landing guidance still invokes a GFOLD update API'
}
if ($landingSource -notmatch '(?i)GetRefState\s*\(') {
    throw 'BORG landing guidance no longer samples the fixed GFOLD reference'
}
if ($landingSource -notmatch '(?i)aerodynamicDisturbanceRatio\s*<=\s*params\["gfold_epsilon"\]') {
    throw 'BORG landing guidance does not gate GFOLD initialization on aerodynamic disturbance'
}
if ($landingSource -notmatch '(?i)gfoldAddonRef\s*:\s*AsyncInitialize\s*\(') {
    throw 'BORG landing guidance no longer starts the hybrid GFOLD initialization'
}
if ($landingSource -notmatch '(?is)"thrustMin1"\s*,\s*mode1EngineLimits\["thrustMin"\].*"thrustMin2"\s*,\s*mode2EngineLimits\["thrustMin"\].*"engineSwitchTime"\s*,\s*engineSwitchDelay') {
    throw 'GFOLD initialization no longer preserves distinct engine modes and switch delay'
}
if ($landingSource -notmatch '(?is)IF hasShutdown\s*\{\s*SET mode1EngineLimitsNow TO mode2EngineLimitsNow') {
    throw 'Already-switched initialization does not use landing limits for both modes'
}
$sampleSwitchIndex = $landingSource.IndexOf('f9_quadratic_engine_switch_ready(')
$initializationGateIndex = $landingSource.IndexOf('aerodynamicDisturbanceRatio <= params["gfold_epsilon"]')
if ($sampleSwitchIndex -lt 0 -or $initializationGateIndex -lt 0 -or $sampleSwitchIndex -gt $initializationGateIndex) {
    throw 'Quadratic sampled switching is not evaluated before GFOLD initialization'
}
if ($landingSource -notmatch '(?is)NOT gfoldSwitchScheduleActive\s+AND f9_quadratic_engine_switch_ready') {
    throw 'Pending GFOLD scheduling does not inhibit the quadratic switch rule'
}
if ($landingSource -notmatch '(?is)FAIL " \+ gfoldReference\["status"\].*SET gfoldSwitchScheduleActive TO FALSE') {
    throw 'A failed GFOLD initialization does not release engine-switch ownership'
}
if ($landingSource -notmatch '(?is)TIME:SECONDS > gfoldInitEpoch\s*\+ gfoldHandoffGraceDuration.*SET gfoldSwitchScheduleActive TO FALSE.*FAIL LATE') {
    throw 'A late GFOLD task does not release engine-switch ownership'
}
if ($landingSource -notmatch '(?is)guidanceMode = "gfold" AND NOT hasShutdown\s+AND TIME:SECONDS >= gfoldSwitchEpoch') {
    throw 'GFOLD tracking does not switch the physical engines at its event epoch'
}
if ($landingSource -notmatch '(?is)guidanceMode = "terminal" AND gfoldSwitchScheduleActive.*SET gfoldSwitchScheduleActive TO FALSE.*guidanceMode = "terminal" AND NOT hasShutdown.*deactivate_engines\(shutDownEngines\).*activate_engines\(landingEngines\)') {
    throw 'Terminal quadratic guidance does not reclaim switch ownership and select landing engines'
}
if ($landingSource -notmatch '(?is)IF NOT decEngineRef:TAG:CONTAINS\(params\["landingEngineTag"\]\).*shutDownEngines:ADD\(decEngineRef\)') {
    throw 'Overlapping deceleration and landing engines are not preserved during switching'
}

$expectedBootSwitches = @{
    'f9recovery.ks' = 10
    'f9recovery_rp1.ks' = 10
    'f9recovery_rp1_asds.ks' = 10
    'zq3recovery.ks' = 8
    'zq3recovery_asds.ks' = 8
}
foreach ($bootEntry in $expectedBootSwitches.GetEnumerator()) {
    $bootSource = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot "..\..\boot\$($bootEntry.Key)")
    if ($bootSource -notmatch "(?i)`"gfold_engineSwitchTime`"\s*,\s*$($bootEntry.Value)(?:\D|$)") {
        throw "$($bootEntry.Key) does not define the expected GFOLD engine-switch time"
    }
}

Write-Host 'BORG GFOLD helper checks passed.'
