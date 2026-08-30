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

$defaults = @{ gfold_lqrLambda = 0.5; gfold_nodes = 20 }
$configured = @{ gfold_lqrLambda = 2.0 }
foreach ($entry in $defaults.GetEnumerator()) {
    if (-not $configured.ContainsKey($entry.Key)) { $configured[$entry.Key] = $entry.Value }
}
Assert-Near $configured.gfold_lqrLambda 2.0 0 'explicit configuration precedence'
Assert-Near $configured.gfold_nodes 20 0 'missing default insertion'

Write-Host 'BORG GFOLD helper checks passed.'
