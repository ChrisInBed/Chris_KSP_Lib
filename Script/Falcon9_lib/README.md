# BORG - Booster Operation, Recovery and Guidance

`Falcon9_lib` is the legacy directory name for BORG's kOS flight scripts. BORG
is a work-in-progress, general-purpose reusable-booster system. It is
hardware-aware after the player assigns engine-role tags, uses FAR data to
build an aerodynamic model, and supports fixed landing sites, waypoints,
moving vessels, and ASDS-style recovery.

The ascent and recovery programs are deliberately independent. The included
ascent program is a small open-loop launch example; the recovery program can
follow a booster launched by MechJeb, PEGAS, another kOS program, or a manual
pilot. The ascent system is responsible for leaving the first stage with a
recoverable state and enough propellant.

## Requirements

- kOS
- Ferram Aerospace Research (FAR)
- Chris GNC Suite (the current project targets v1.0.0 or later)
- the `kOS-LTR` addon from `src/kOS-LTR`
- the `kOS-GFOLD` addon from `src/kOS-GFOLD` for optimized landing guidance
- one kOS CPU on the upper stage and one on the reusable booster

LTR and FAR are required by the recovery executive. LTR must appear in the
kOS addon list as `LTR` (`ADDONS:HASADDON("LTR")` / `ADDONS:LTR`).
GFOLD is optional at runtime: install its DLL and MechJeb's `alglib.dll` to use
optimized landing guidance. If `ADDONS:HASADDON("GFOLD")` is false, BORG warns
and uses the original quadratic landing controller for the complete burn.

All distances are metres, speeds are m/s, masses are tonnes as reported by
kOS, times are seconds, and angles are degrees unless noted otherwise.

## Boot files and call chain

Each boot file owns a parameter lexicon and calls an executive. Do not put
vehicle parameters in a shared global parameter file.

| Boot file | CPU | Purpose |
|---|---|---|
| `boot/f9ascent.ks` | upper stage | Generic open-loop ascent example. |
| `boot/f9ascent_rp1.ks` | upper stage | Falcon 9 RP-1 profile. |
| `boot/f9ascent_rp1_asds.ks` | upper stage | Falcon 9 RP-1 ASDS profile. |
| `boot/f9recovery.ks` | booster | Generic recovery profile. |
| `boot/f9recovery_rp1.ks` | booster | Falcon 9 RP-1 recovery profile. |
| `boot/f9recovery_rp1_asds.ks` | booster | Falcon 9 RP-1 ASDS recovery profile. |
| `boot/zq3ascent.ks` / `zq3ascent_asds.ks` | upper stage | ZhuQue-3 ascent profiles. |
| `boot/zq3recovery.ks` / `zq3recovery_asds.ks` | booster | ZhuQue-3 recovery profiles. |

The normal execution chain is:

```text
ascent boot -> gof9u.ks -> f9utility.ks + f9launch.ks -> f9_launch
recovery boot -> gof9d.ks -> f9utility.ks
                            -> optional f9boostback.ks
                            -> f9entryburn.ks
                            -> f9landingburn.ks
```

The ascent boot waits for Action Group 10 while the vessel is prelaunch.
Pressing `0` starts `gof9u.ks`. The launch routine starts the tagged liftoff
engines, holds vertical, performs its programmed pitch-over, cuts off at
`mecoMass`, stages the first stage, ignites the upper stage, and waits for a
second Action Group 10 change before releasing its steering and throttle
locks.

The recovery boot can start before launch. `gof9d.ks` validates the recovery
lexicon and LTR, initializes the configured target, waits until the vessel
mass is below `boostBackMass`, then waits `boostBackDelay`. LTR is initialized
only after separation so FAR samples the booster rather than the complete
launch stack.

## Recovery target modes

`landingSiteUse` is explicit; no active waypoint or KSP target is consulted
implicitly.

### Fixed geoposition

```ks
"landingSiteUse", "geo",
"landingSiteGeo", LIST(longitude, latitude),
```

Terrain height at the coordinates is used as the raw target altitude.

### Waypoint

```ks
"landingSiteUse", "waypoint",
"landingSiteWaypoint", "ASDS-ZhuQue3-Cape",
```

The waypoint's geoposition and altitude are used. The name must match exactly.

### Vessel

```ks
"landingSiteUse", "vessel",
"landingSiteVessel", "drone",
```

The vessel's position and altitude are refreshed during guidance, so a moving
drone ship can be followed. The vessel name must match exactly.

### Automatic natural-impact target (`none`)

```ks
"landingSiteUse", "none",
```

After separation and `boostBackDelay`, BORG runs an LTR prediction at a
temporary sea-level target, samples the terrain/ocean altitude at that impact,
then repeats the prediction. The resulting geoposition is written into
`targetContext` and is treated as a fixed target for the rest of the flight.
This mode is intended for surveying where to place an ASDS or a downrange
landing pad. For a survey flight, use:

```ks
"landingSiteUse", "none",
"enableBoostBack", FALSE,
```

Read the predicted latitude and longitude from the recovery display, place the
ship or pad there, create a waypoint (or use the vessel name), and update the
recovery boot file for the operational flight.

`altitudeOffset` is added to the selected waypoint, vessel, or geoposition
altitude. It is also applied to an automatically resolved target.

## Engine-role tags

The engine search is substring-based: an engine belongs to a group when its
kOS tag contains the configured string. A combined tag can therefore assign
several roles to one engine. Keep configured strings from unintentionally
containing one another.

The standard Falcon 9 example uses labels like these:

| Role | Example tag |
|---|---|
| All liftoff engines | `liftoff_` |
| Boostback engines | `liftoff_boostback_entry_` |
| Entry engines | `liftoff_boostback_entry_` |
| Final landing engines | `liftoff_boostback_entry_landing2_` |

The recovery lexicon separates the role selectors:

```ks
"boostbackEngineTag", "boostback_",
"entryEngineTag", "entry_",
"landingDecEngineTag", "landing1_",
"landingEngineTag", "landing2_",
```

`landingDecEngineTag` selects the initial landing-deceleration set and
`landingEngineTag` selects the final landing set. If no deceleration engines
match, the final landing set is used as the fallback. When the two sets
overlap, an engine matching the final landing tag is not shut down during the
deceleration-to-landing transition.

## Recovery phases

### 1. Separation and target preparation

The recovery executive always waits for the booster mass to fall below
`boostBackMass`, then waits `boostBackDelay`. It initializes the target and LTR
after this handoff. The LTR body model calls `InitAtmModel` and sets body spin
from `BODY:ANGULARVEL`; aerodynamic coefficients are sampled from FAR using
the configured speed and altitude grids.

### 2. Boostback

If `enableBoostBack` is `TRUE`, BORG predicts the impact error, aligns the
boostback engine thrust axis, and fires the tagged engines at
`boostBackThrottle`. The prediction is refreshed asynchronously while the
burn runs. The steering and cutoff logic accounts for prediction latency and
cuts off when the predicted error is no longer improving. If the switch is
`FALSE`, no boostback hook, engine lookup, alignment, or burn is performed.

### 3. Entry phase

`f9_entry_burn` is always called so the phase boundary remains consistent. It
calls the entry hook and then:

- when `enableEntryBurn` is `TRUE`, holds the booster retrograde while
  descending to `entryBurnAlt`, iteratively computes a target-correcting VGO,
  aligns the entry engines, and burns at `entryThrottle` until the configured
  `entryVSpeed` is reached;
- when `enableEntryBurn` is `FALSE`, skips only the engine lookup, alignment,
  ignition, and powered burn. The following aerodynamic gliding phase is still
  executed by `f9_landing_burn`.

### 4. Aerodynamic descent, GFOLD planning, and landing ignition

`f9_landing_burn` begins with an unpowered aerodynamic-guidance loop. LTR
predicts the impact point using the configured AOA profile and FAR-derived
coefficients. Independent pitch and yaw PID loops correct downrange and
crossrange impact error, with `aeroMaxPitch`, `aeroMaxYaw`, dynamic-pressure
attenuation, and `aeroTargetOffset` limiting the correction.

During the glide, BORG estimates the surface-velocity derivative and applies
exponential smoothing. A constant-vector-acceleration intercept predicts when
the vehicle bottom will reach `landingBurnAltitude`. Once that intercept is
within `gfold_planningTime`, BORG starts exactly one asynchronous GFOLD cold
solve using the predicted position and velocity at the burn-altitude crossing.

Landing ignition remains spool-compensated, but the same measured vector
acceleration now predicts the bottom point over the deceleration engines'
spool-up time. Powered guidance starts only after the actual bottom point has
reached the burn altitude and spool-up has elapsed. GFOLD is accepted only if
the cold solve is already successful at that crossing; otherwise the landing
permanently uses the quadratic fallback.

### 5. GFOLD tracking, fallback, and terminal guidance

The landing burn uses one continuous loop containing three guidance regimes:

1. **GFOLD phase 1:** BORG analytically samples the reference state and control,
   computes the six-component position/velocity error, applies the returned
   3x6 LQR gain, and commands `u_ref + K e`. At most one asynchronous update is
   started per `gfold_updateInterval`. A failed update is discarded while the
   last accepted reference remains active. Engines switch at the cold-solve
   epoch plus `gfold_engineSwitchTime`.
2. **Quadratic fallback:** if GFOLD is missing, late, infeasible, or fails its
   cold solve, the original AOA-constrained fixed-time controller flies phase
   1. Its sampled-demand engine-switch rule is preserved.
3. **Terminal quadratic phase:** either GFOLD time-to-go reaching
   `landingPhase2Time` or bottom altitude reaching `landingPhase2Alt` causes a
   one-way transition. GFOLD updates stop, the final engine set is selected,
   AOA is exactly zero, and the original upward-biased retrograde command is
   preserved. An out-of-range GFOLD reference also enters this phase without
   attempting an invalid addon sample.

GFOLD's body-fixed coordinates are frozen when initialization starts. BORG
builds target-centered east/up/north bases with a polar fallback, maps the
current bottom point and surface velocity into that frozen basis, and maps the
specific-thrust command back before steering. A moving target's position is
refreshed, but its velocity is deliberately not subtracted. This implements
the selected position-only target-tracking policy.

The requested acceleration is converted through a minimum-throttle-aware
throttle mapper. During every update, BORG samples several points of the
remaining quadratic trajectory. Deceleration engines are shut down only when
all sampled thrust demands are below the final landing-engine cutoff
capability. Engines that are also final landing engines remain active.

Landing legs deploy below `legDeploySpeed`. Engines are cut off when vertical
speed becomes non-negative or the bottom of the vehicle reaches
`landingCutoffHeight`. The script then holds the vehicle upright for five
seconds before releasing steering and throttle locks.

## Script responsibilities

| Script | Responsibility |
|---|---|
| `GFOLD_defaults.ks` | Vessel-independent GFOLD and terminal-guidance defaults. Boot values override these entries. |
| `f9utility.ks` | Parameter/default validation, display helpers, target acquisition/refresh, LTR/FAR setup, GFOLD frame/math helpers, steering transforms, bottom-height calculation, and throttle mapping. |
| `f9launch.ks` | Included open-loop ascent: liftoff, vertical hold, programmed turn, MECO, staging, upper-stage ignition, and Action Group 10 handoff. |
| `f9boostback.ks` | Optional post-separation boostback alignment, latency-aware impact-error guidance, throttle control, and cutoff. |
| `f9entryburn.ks` | Optional powered entry burn and VGO iteration. It keeps the entry phase callable when the powered burn is disabled. |
| `f9landingburn.ks` | Aerodynamic impact correction, asynchronous GFOLD planning/replanning, LQR tracking, quadratic fallback/terminal guidance, spool-aware ignition, engine transition, gear deployment, and cutoff. |
| `gof9u.ks` | Upper-stage executive; loads launch modules and runs `f9_launch`. |
| `gof9d.ks` | Booster executive; validates, waits for separation, resolves targets, and runs the recovery phases. |

Each public phase returns a Boolean. The executive stops when configuration,
target acquisition, addon availability, engine discovery, thrust data, or a
prediction prerequisite fails.

## Configuration reference

The tables below show the defaults in `boot/f9recovery.ks`. RP-1, ASDS, and
ZhuQue-3 boot files intentionally override vehicle-specific values; always
edit the boot file that is installed on the actual craft.

### Ascent parameters

The included generic ascent defaults are:

| Key | Default | Meaning |
|---|---:|---|
| `kOSIPU` | `2000` | kOS instructions per update. |
| `liftoffEngineTag` | `"liftoff_"` | Engines started for liftoff and MECO. |
| `payloadMass` | `16.651` | Payload mass in tonnes. |
| `mecoMass` | `190 + payloadMass` | Mass threshold for first-stage MECO. |
| `targetHeading` | `80` | Programmed ascent heading. |
| `targetRoll` | `0` | Programmed roll angle. |
| `turnSpeed` | `50` | Surface speed at which pitch-over starts. |
| `pitchOmega` | `0.42` | Programmed pitch decrease in degrees per second. |
| `stageSeparationDelay` | `1` | Delay between MECO and staging. |
| `upperStageIgnitionDelay` | `2` | Delay between staging and upper-stage ignition. |

This ascent is not an orbit optimizer. Reserve first-stage propellant and use
another ascent system if the mission needs a different trajectory.

### Recovery target, tags, and switches

| Key | Default | Meaning |
|---|---:|---|
| `kOSIPU` | `2000` | kOS instructions per update. |
| `landingSiteUse` | `"waypoint"` | `geo`, `waypoint`, `vessel`, or `none`. |
| `landingSiteGeo` | `LIST(0, 0)` | Longitude/latitude for `geo`. |
| `landingSiteWaypoint` | `"VAB"` | Waypoint name for `waypoint`. |
| `landingSiteVessel` | `"drone"` | Vessel name for `vessel`. |
| `boostbackEngineTag` | `"boostback_"` | Boostback engine selector. |
| `entryEngineTag` | `"entry_"` | Entry engine selector. |
| `landingDecEngineTag` | `"landing1_"` | Initial landing-deceleration selector. |
| `landingEngineTag` | `"landing2_"` | Final landing selector. |
| `boostBackMass` | `150` | Mass below which separation is recognized. |
| `DryMass` | `25` Falcon / `45` ZhuQue-3 | Guessed dry mass in tonnes used to compute GFOLD fuel as `SHIP:MASS-DryMass`; tune before flight. |
| `targetRoll` | `0` | Powered recovery roll command. |
| `altitudeOffset` | `0` | Altitude added to the selected target. |
| `enableBoostBack` | `TRUE` | Run the boostback phase. |
| `boostBackDelay` | `4` | Delay after separation detection. |
| `burnAlignTolerance` | `130` | Alignment error accepted before powered burn. |
| `boostBackThrottle` | `1` | Boostback throttle command. |
| `enableEntryBurn` | `TRUE` | Run the powered entry burn; gliding still runs when `FALSE`. |
| `entryBurnAlt` | `60000` | Absolute ASL descending entry-burn altitude. |
| `entryVSpeed` | `650` | Positive target downward speed after entry burn. |
| `entryThrottle` | `1` | Entry throttle command. |

### LTR prediction

| Key | Default | Meaning |
|---|---:|---|
| `ltrCtrlSpeedSamples` | `LIST(300, 600, 1000)` | Speed axis for the open-loop AOA profile. |
| `ltrCtrlAOASamples` | `LIST(0, 8, 10)` | AOA values corresponding to the speed axis. |
| `ltrAeroSpeedSamples` | `LIST(100, 500, 1000, 2000, 3000)` | FAR coefficient speed samples. |
| `ltrAeroAltitudeSamples` | `LIST(0, 10000, 30000, 50000, 70000)` | FAR coefficient altitude samples. |
| `ltrCdFactor` | `1` | Drag-coefficient calibration multiplier. |
| `ltrClFactor` | `1` | Lift-coefficient calibration multiplier. |
| `ltrPredictMinStep` | `0.001` | Minimum RKF45 step in seconds. |
| `ltrPredictMaxStep` | `0.5` | Maximum RKF45 step in seconds. |
| `ltrPredictTMax` | `1200` | Maximum prediction duration. |

LTR samples FAR after separation, initializes the body's atmosphere and spin,
and asynchronously propagates the trajectory. A failed or timed-out
prediction is reported to the active phase; aerodynamic guidance falls back to
surface retrograde for an individual invalid glide prediction.

### Aerodynamic guidance

| Key | Default | Meaning |
|---|---:|---|
| `aeroPitchKp` / `aeroPitchKi` / `aeroPitchKd` | `10 / 0 / 0.5` | Downrange PID gains. |
| `aeroYawKp` / `aeroYawKi` / `aeroYawKd` | `10 / 0 / 0.5` | Crossrange PID gains. |
| `aeroMaxPitch` | `6` | Maximum pitch correction in degrees. |
| `aeroMaxYaw` | `10` | Maximum yaw correction in degrees. |
| `aeroTargetOffset` | `0` | Downrange offset applied to boostback, entry, and glide targets. |

### Landing guidance

| Key | Default | Meaning |
|---|---:|---|
| `QuadraticAOABase` | `30` | Low-q upper bound for quadratic-phase AOA. |
| `QuadraticAOADot` | `1` | AOA allowance in degrees per second of time-to-go. |
| `landingBurnAltitude` | `2300` | Spool-predicted ignition-height threshold. |
| `legDeploySpeed` | `90` | Airspeed below which landing gear deploys. |
| `touchDownSpeed` | `0.1` | Positive terminal downward-speed magnitude. |
| `landingPhase2Time` | `4` | Time-to-go at which terminal guidance begins. |
| `landingCutoffHeight` | `0.2` | Bottom height at which engines are cut off. |
| `boundsUpdatePeriod` | `1` | Vessel-bounds refresh interval. |
| `minLandingThrottleCommand` | `0.01` | Minimum positive landing throttle command. |

The following vessel-specific keys are required in every recovery boot. The
included values are estimates: Falcon/Falcon-RP1 profiles use `DryMass=25` and
`gfold_engineSwitchTime=10`; ZhuQue-3 profiles use `DryMass=45` and switch time
`8`. All examples select surface mode with zero pit radius, buffer, and depth.

| Key | Meaning |
|---|---|
| `DryMass` | Vessel dry mass in tonnes. BORG never derives this from resources. |
| `gfold_engineSwitchTime` | Seconds after the predicted initialization epoch to change engine modes. |
| `gfold_pitRadius` | Physical landing-cylinder radius in metres; zero for surface mode. |
| `gfold_wallBuffer` | Radial clearance inside the cylinder wall. |
| `gfold_pitDepth` | Rim-to-floor depth; the target is always the floor center. |

`GFOLD_defaults.ks` supplies these universal values only when the boot lexicon
omits them:

| Key | Default | Meaning |
|---|---:|---|
| `gfold_planningTime` | `6` | Cold-solve lead time before predicted ignition altitude. |
| `gfold_updateInterval` | `1` | Minimum interval between asynchronous replans. |
| `gfold_thrustMargin` | `0.1` | Fraction of usable throttle span reserved at each end. |
| `gfold_accelerationSmoothing` | `0.2` | New-sample weight in the acceleration filter. |
| `gfold_nodes` | `20` | Exact number of GFOLD state nodes. |
| `gfold_maxSearchEvaluations` | `20` | Cold/update outer-search budget. |
| `gfold_lqrDt` | `0.1` | Discrete LQR controller period. |
| `gfold_lqrLambda` | `0.5` | LQR control-deviation weight. |
| `gfold_lqrBeta` | `1` | LQR velocity-error weight relative to position. |
| `gfold_descentMaxSpeed` | `600` | Descent-phase speed limit. |
| `gfold_descentTilt` | `45` | Descent-phase thrust tilt limit in degrees. |
| `gfold_descentGlideSlope` | `20` | Outside-pit glide-slope angle. |
| `gfold_entryMaxSpeed` | `100` | Pit-entry speed limit. |
| `gfold_entryTilt` | `30` | Pit-entry thrust tilt limit. |
| `gfold_entryGlideSlope` | `0` | Inner glide-slope angle; zero disables it. |
| `gfold_terminalTilt` | `10` | GFOLD terminal-window thrust tilt limit. |
| `gfold_terminalTiltWindow` | `3` | Duration of GFOLD's terminal tilt window. |
| `landingPhase2Alt` | `50` | Bottom-altitude trigger for terminal quadratic guidance. |

Optional positive `gfold_tfMin` and `gfold_tfMax` values constrain GFOLD's
flight-time search; when absent, the fields are omitted and the addon derives
its own bounds. For an engine set whose physical minimum throttle is `f_min`
and margin is `m`, BORG gives GFOLD the conservative range
`f_min + (1-f_min)m` through `1-(1-f_min)m`, multiplied by composite maximum
thrust. Composite effective Isp comes from the same tagged engine set.

## Hooks and tuning order

Recovery boot files define three hooks:

- `pre_boostback_hook`: runs after the separation delay and before boostback
  engine lookup;
- `pre_entryburn_hook`: runs at the entry phase boundary, including when the
  powered entry burn is disabled;
- `pre_landingburn_hook`: runs before aerodynamic descent and landing.

Use these hooks for vehicle-specific steering-manager settings. Tune the
attitude controller first, then engine tags and thrust data, then the measured
`DryMass`, LTR/AOA profiles, aerodynamic PID limits, entry parameters, GFOLD
feasibility limits, and finally LQR weights. The included dry masses and switch
times are guesses, not certified vehicle data. A poor steering-manager response
can make a correct impact prediction or trajectory look like a guidance
failure.

## Testing workflow

1. Confirm that all engine tags are discoverable after staging and that the
   configured `boostBackMass` is below the attached launch-vehicle mass but
   above the separated-booster mass.
2. Run an ASDS survey with `landingSiteUse = "none"` and
   `enableBoostBack = FALSE`; record the displayed natural impact coordinates.
3. Place the recovery ship or pad, configure a waypoint or vessel target, and
   rerun the flight with the intended burn switches.
4. Verify the first-stage fuel reserve, engine restart count, minimum throttle,
   spool time, and touchdown clearance before a full mission.
5. Test GFOLD-unavailable, cold-solve failure/latency, update failure, both
   terminal triggers, both engine-set overlap cases, and moving-target behavior
   in a disposable simulation before operational use.

The included ascent guidance is only a convenience. A player-controlled,
MechJeb, PEGAS, or other ascent can be used as long as the booster reaches
separation in a state the recovery profile can physically recover.
