# Falcon 9 Reusable First-Stage Guidance

This directory contains kOS guidance for launching a two-stage RO vehicle and recovering its first stage. Recovery uses the `kOS-LTR` C# addon to propagate an open-loop lifting trajectory with an RKF45 integrator. The kOS guidance updates the body-fixed target and vehicle state before each prediction, then closes the loop around the predicted impact point.

The software provides:

- vertical launch, programmed pitch-over, MECO, and upper-stage handoff;
- LTR-predicted closed-loop boostback and entry burns toward a waypoint or vessel;
- LTR-predicted aerodynamic impact correction;
- spool-compensated landing-burn ignition;
- fixed-time quadratic landing guidance with a dynamic angle-of-attack limit;
- a terminal vertical braking phase using one continuous landing-engine ignition.

## Requirements and operation

- `Chris_GNC_Suite >= 0.9.9` is available.
- FAR and the `kOS-LTR` addon from `src/kOS-LTR` are installed for first-stage recovery.
- Engines must have the configured kOS tags. One engine may have several role tags if appropriate.
- Select an active waypoint or set a target vessel before recovery starts. The waypoint has precedence. A waypoint is cached; a vessel's position and altitude are refreshed every frame.
- Start `gof9u.ks` on the upper-stage CPU before launch and `gof9d.ks` on the booster CPU before separation.
- When prompted after the upper-stage throttle handoff, change action group 10 to release the launch script's steering and throttle locks.

All distances are metres, speeds are m/s, masses are tonnes as reported by kOS, times are seconds, and angles are degrees unless noted otherwise.

## Script responsibilities

| Script | Function |
|---|---|
| `params.ks` | Defines `F9_PARAMS` and tunes the kOS steering manager. This is the vehicle-specific configuration file. |
| `f9utility.ks` | Provides validation, fixed-row displays, target acquisition, the common downrange-offset target, LTR/FAR initialization and prediction, PEGLand-style thrust-axis/roll steering, body-fixed entry guidance, bounds updates, and continuous throttle mapping. |
| `f9launch.ks` | Implements the vertical rise, programmed pitch turn, MECO, separation, and upper-stage control handoff through `f9_launch(params)`. |
| `f9boostback.ks` | Implements post-separation engine reacquisition, LTR impact-error steering, and minimum-impact-error cutoff through `f9_boostback(params, targetContext)`. |
| `entryburn.ks` | Implements retrograde coast, the descending entry trigger, entry-burn alignment, guidance, and vertical-speed cutoff through `f9_entry_burn(params, targetContext)`. |
| `f9landingburn.ks` | Implements aerodynamic correction, landing ignition prediction, AOA-limited quadratic guidance, terminal braking, gear deployment, and engine cutoff through `f9_landing_burn(params, targetContext)`. |
| `gof9u.ks` | Upper-stage executive. Clears the display, loads the launch modules, and runs `f9_launch`. |
| `gof9d.ks` | Booster executive. Validates recovery configuration and kOS-LTR availability, initializes the target, then runs boostback, entry, and landing in sequence. |

Each public phase function returns a Boolean. The executive stops if target acquisition, configuration, engines, thrust data, or another prerequisite is unavailable.

## Guidance principles

### Target and reference frame

Guidance uses `SHIP:VELOCITY:SURFACE` and a body-fixed target. The final target altitude is

$$
h_T=h_{ASL}+h_{offset},
$$

where `h_ASL` is the waypoint or target-vessel altitude and `h_offset` is `altitudeOffset`. The target vector is always obtained with `GeoCoordinates:ALTITUDEPOSITION(h_T)`; terrain altitude is not substituted. Boostback, entry, and aerodynamic glide add `aeroTargetOffset` along downrange. Powered landing deliberately returns to the raw altitude-aware target.

The current surface normal and a fixed trajectory-plane normal define the steering frame. The requested thrust vector is corrected by the engine thrust-axis rotation `TiS`, while `targetRoll` fixes vehicle roll. For landing clearance, the bounds are sampled along thrust-down to obtain `bottomHeight`, then the code projects `SHIP:POSITION - bottomHeight * UP:FOREVECTOR` onto the target-altitude plane. Radar altitude is not used.

### Launch

The launch script starts the tagged liftoff engines, waits for spool-up, releases clamps/stages, and holds vertical until `turnSpeed`. Pitch then follows

$$
\theta(t)=\max\left(0,90^\circ-\omega_p(t-t_{turn})\right),
$$

at `targetHeading`, where $\omega_p$ is `pitchOmega`. When mass reaches `mecoMass`, the script shuts down the liftoff engines, waits `stageSeparationDelay`, separates, waits `upperStageIgnitionDelay`, and commands the upper-stage throttle. After five seconds it waits for action group 10 to change before releasing its locks.

### Boostback

Let $\mathbf r_P$ be LTR's predicted impact position and $\mathbf r_T$ the altitude-aware, downrange-offset target. Boostback points thrust along

$$
\mathbf v_g \parallel \mathbf r_T-\mathbf r_P.
$$

The omitted positive scale is irrelevant to attitude. The stage waits for `boostBackMass`, delays by `boostBackDelay`, initializes LTR from the separated booster, aligns within `burnAlignTolerance`, and starts the burn. A fresh prediction is made after every guidance update. Cutoff occurs when $\lVert\mathbf r_T-\mathbf r_P\rVert$ first stops decreasing.

### Entry burn

During coast the vehicle holds surface retrograde. The entry sequence begins only while descending through the absolute ASL altitude `entryBurnAlt`. `entryVSpeed` is a positive magnitude, so the target post-burn radial velocity is

$$
v_E=-\texttt{entryVSpeed}.
$$

Let $\mathbf r$ and $\mathbf v$ be the current body-centred position and surface velocity, $v_r=\hat{\mathbf r}\cdot\mathbf v$, $h$ the radial height above the target, and $g=\mu/\lVert\mathbf r\rVert^2$. The target and current-state vacuum fall times are

$$
T_T=\frac{v_E+\sqrt{v_E^2+2gh}}{g},\qquad
T_P=\frac{v_r+\sqrt{v_r^2+2gh}}{g}.
$$

Using LTR's atmospheric impact point $\mathbf r_P$, entry steering applies the cancellation-safe, current-relative form

$$
\mathbf v_g=
\frac{\mathbf r_T-\mathbf r}{T_T}
-\frac{\mathbf r_P-\mathbf r}{T_P}
-\frac12\mathbf g(T_T-T_P).
$$

The prediction and remaining velocity are updated throughout alignment and powered flight. If the stage is already descending no faster than `entryVSpeed`, the burn is skipped. Otherwise cutoff occurs when vertical speed reaches $-\texttt{entryVSpeed}$.

### Aerodynamic guidance and landing ignition

Each glide update uses LTR's predicted impact at the configured target altitude. The body-centred impact error is projected into downrange and crossrange components. Independent pitch and yaw PIDs rotate the retrograde vector, bounded by `aeroMaxPitch` and `aeroMaxYaw`; dynamic pressure attenuates error authority to reduce high-q oscillation. A failed or timed-out individual prediction falls back to surface retrograde for that update.

Landing-engine spool-up is predicted with constant gravity:

$$
\mathbf v_f=\mathbf v-gT_s\hat{\mathbf u},\qquad
h_f=h+v_zT_s-\tfrac12gT_s^2.
$$

The future braking demand and reference acceleration are

$$
a_{req}=\frac{\lVert\mathbf v_f\rVert^2-v_{td}^2}{2\max(0.01,h_f)}+g,
\qquad
a_{ref}=\frac{1+\eta_{min}}{2}\frac{F_{max}}{m}.
$$

Ignition occurs only when `h_f <= landingBurnAltitude` and `a_req >= a_ref`. This prevents premature ignition while retaining spool-time compensation.

### Landing phase 1: quadratic guidance

Phase 1 uses the fixed-time form of PEGLand's quadratic-acceleration solution. For negative polynomial time $T=-t_{go}$, current/target states $(\mathbf R_I,\mathbf V_I)$, $(\mathbf R_T,\mathbf V_T)$, and terminal net acceleration $\mathbf A_T$, jerk and snap are

$$
\mathbf J=\frac{24}{T^3}(\mathbf R_I-\mathbf R_T)
-\frac{6}{T^2}(\mathbf V_I+3\mathbf V_T)-\frac{6}{T}\mathbf A_T,
$$

$$
\mathbf S=-\frac{72}{T^4}(\mathbf R_I-\mathbf R_T)
+\frac{24}{T^3}(\mathbf V_I+2\mathbf V_T)+\frac{12}{T^2}\mathbf A_T.
$$

The current net acceleration is $\mathbf A_I=\mathbf A_T+\mathbf JT+\tfrac12\mathbf ST^2$, and commanded thrust acceleration is $\mathbf A_I+g\hat{\mathbf u}$. Time-to-go is recomputed from total surface speed and the available start/end accelerations.

To retain aerodynamic attitude control, thrust AOA relative to surface retrograde is limited to

$$
\alpha_{max}=\min\left(
\frac{\texttt{QuadraticAOABase}}{1+101q/10},
\texttt{QuadraticAOADot}\,t_{go}
\right),
$$

where `SHIP:Q` is kOS dynamic pressure. If the unconstrained command exceeds this cone, its direction is clipped and scaled to preserve the required vertical thrust component; jerk, snap, and the implied horizontal terminal point are then rebuilt. This is a low-cost, height-preserving AOA constraint rather than a numerical optimizer.

Thrust demand is converted through the shared minimum-throttle-aware controller and clamped above zero, keeping the landing engines continuously ignited. Gear deploys when airspeed falls below `legDeploySpeed`. Phase 2 begins when time-to-go reaches `landingPhase2Time` or bottom height reaches the cutoff threshold.

### Landing phase 2: terminal braking

Terminal guidance uses downward vertical-speed magnitude $v_d$:

$$
a_{cmd}=\frac{v_d^2-v_{td}^2}{2\max(0.01,h)}+g.
$$

The same continuous throttle mapping is retained. Steering stays surface retrograde while horizontal motion is significant, then becomes target-local up. The engines shut down when vertical speed becomes non-negative or bottom height falls below `landingCutoffHeight`; all guidance locks are then released.

## Configuring `params.ks`

Copy the existing `params.ks` as the starting point and change values for the actual vehicle. At minimum:

1. Tag engines and verify each role is discoverable after staging.
2. Measure wet/staging masses and set `mecoMass` and `boostBackMass`.
3. Set the launch azimuth, target roll, and target altitude offset.
4. Set entry and landing envelopes from vehicle heating, thrust, throttle, and ignition limits.
5. Tune aerodynamic pitch and yaw independently in repeated flights, starting with small gains and correction limits.
6. Tune quadratic AOA limits only after the unpowered approach and landing ignition are reliable.

The executives validate the main required and safety-critical values before commanding the vehicle, but they cannot prove that a configured value is physically achievable.

### Runtime, tags, and vehicle

| Parameter | Current default | Meaning |
|---|---:|---|
| `kOSIPU` | `2000` | Requested kOS instructions per update. Lower it if the processor cannot sustain this value. |
| `liftoffEngineTag` | `"liftoff"` | Engine tag used for launch and MECO. |
| `boostbackEngineTag` | `"boostback"` | Engine tag reacquired for boostback after separation. |
| `entryEngineTag` | `"entry"` | Engine tag used for the entry burn. |
| `landingEngineTag` | `"landing"` | Engine tag used for the continuous landing burn. |
| `payloadMass` | `16.651` | Payload mass used to construct the current MECO mass setting. It is a local convenience value, also copied into `F9_PARAMS`. |
| `mecoMass` | `190 + payloadMass` | Vehicle mass at launch-engine cutoff. Include the payload and upper stage still attached at MECO. |
| `boostBackMass` | `150` | Booster mass below which the recovery script recognizes separation and starts its post-separation delay. |
| `targetHeading` | `80` | Launch heading and heading used for the initial vertical attitude. |
| `targetRoll` | `0` | Roll held by powered recovery steering. Match vehicle aerodynamics and control authority. |
| `altitudeOffset` | `0` | Metres added once to waypoint/vessel ASL altitude to locate the desired touchdown surface relative to the marker or vessel centre. May be positive or negative. |

### Launch and powered-burn sequencing

| Parameter | Current default | Meaning |
|---|---:|---|
| `turnSpeed` | `50` | Surface speed at which the vertical hold ends and pitch-over begins. |
| `pitchOmega` | `0.42` | Programmed pitch decrease in degrees per second. |
| `stageSeparationDelay` | `1` | Delay from MECO to the separation stage command. |
| `upperStageIgnitionDelay` | `2` | Delay after separation before upper-stage throttle handoff. |
| `boostBackDelay` | `4` | Delay after the mass-based separation detection before boostback engine reacquisition. |
| `burnAlignTolerance` | `130` | Maximum steering error allowed before boostback or entry engine activation. A large value favors immediate ignition; reduce it only if ignition timing allows alignment. |

### Entry guidance

| Parameter | Current default | Meaning |
|---|---:|---|
| `entryBurnAlt` | `60000` | Absolute ASL altitude at which a descending stage may begin entry-burn alignment. It is not relative to target altitude. |
| `entryVSpeed` | `650` | Positive magnitude of the desired downward vertical speed after entry burn. |

### LTR prediction

| Parameter | Current default | Meaning |
|---|---:|---|
| `ltrCtrlSpeedSamples` | `0, 500, 1000, 2000, 3000` | Strictly increasing speed axis for the open-loop AOA profile. |
| `ltrCtrlAOASamples` | `0, 0, 0, 0, 0` | AOA commands corresponding to `ltrCtrlSpeedSamples`, in degrees. |
| `ltrAeroSpeedSamples` | `100, 500, 1000, 2000, 3000` | Strictly increasing speeds at which FAR coefficients are sampled after separation. |
| `ltrAeroAltitudeSamples` | `0, 10000, 30000, 50000, 70000` | Altitudes at which FAR coefficients and density coordinates are sampled. Must be strictly monotonic. |
| `ltrCdFactor` | `1` | Multiplier applied to sampled drag coefficients for model calibration. |
| `ltrClFactor` | `1` | Multiplier applied to sampled lift coefficients for model calibration. |
| `ltrPredictMinStep` | `0.001` | Minimum accepted RKF45 step in seconds. |
| `ltrPredictMaxStep` | `0.5` | Maximum RKF45 step in seconds. |
| `ltrPredictTMax` | `1200` | Maximum propagated flight time in seconds before a prediction reports `TIMEOUT`. |

The speed and altitude grids control startup cost and interpolation fidelity. Coefficients are sampled only once, after separation, while mass and the moving target are refreshed before every prediction.

### Aerodynamic guidance

| Parameter | Current default | Meaning |
|---|---:|---|
| `aeroPitchKp` | `15` | Proportional gain for normalized downrange impact error. |
| `aeroPitchKi` | `0.5` | Integral gain for downrange error; excessive values cause wind-up and oscillation. |
| `aeroPitchKd` | `0.5` | Derivative gain for downrange damping. |
| `aeroYawKp` | `15` | Proportional gain for normalized crossrange impact error. |
| `aeroYawKi` | `0.5` | Integral gain for crossrange error. |
| `aeroYawKd` | `0.5` | Derivative gain for crossrange damping. |
| `aeroMaxPitch` | `15` | Maximum aerodynamic pitch correction from surface retrograde. |
| `aeroMaxYaw` | `15` | Maximum aerodynamic yaw correction from surface retrograde. |
| `aeroTargetOffset` | `0` | Signed downrange displacement of the LTR aim point used by boostback, entry, and glide. It does not move the powered-landing target. |

### Landing guidance

| Parameter | Current default | Meaning |
|---|---:|---|
| `QuadraticAOABase` | `20` | Low-q upper bound for quadratic-phase thrust AOA. Dynamic pressure reduces this value. |
| `QuadraticAOADot` | `0.5` | AOA allowance in degrees per second of time-to-go; tightens the cone near touchdown. |
| `landingBurnAltitude` | `3000` | Maximum spool-predicted bottom height at which the acceleration-demand ignition condition may fire. |
| `legDeploySpeed` | `90` | Airspeed below which phase 1 deploys the landing gear. |
| `touchDownSpeed` | `0.1` | Positive magnitude of commanded downward terminal speed. |
| `landingPhase2Time` | `8` | Time-to-go threshold for transition from quadratic guidance to terminal braking. |
| `landingCutoffHeight` | `0.2` | Bottom height at which landing engines are shut down, unless non-negative vertical speed triggers cutoff first. |
| `boundsUpdatePeriod` | `1` | Interval between vessel-bound refreshes used to estimate the lowest point. |
| `minLandingThrottleCommand` | `0.01` | Smallest positive throttle lock during landing, preventing an RO shutdown and additional ignition use. |

The final `"_", ""` lexicon entry is only a trailing syntax placeholder; it is not a tunable parameter.

### Steering-manager tuning

The first lines of `params.ks` also set `STEERINGMANAGER` response: `MAXSTOPPINGTIME`, pitch/yaw/roll torque settling times, and roll PID derivative gain. These are not guidance gains. Tune them for the vehicle's actuator strength and inertia before tuning aerodynamic or landing guidance; an unstable attitude controller invalidates higher-level guidance tests.

Flight-test all changes in simulation. In particular, confirm engine tag changes across staging, available landing thrust at minimum throttle, ignition count, impact-prediction convention, target altitude, and vessel bounds before attempting a full recovery.
