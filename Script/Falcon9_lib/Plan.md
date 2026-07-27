# Falcon-9 launch and recovery script

## Overall

- `Falcon9_lib/f9launch.ks`: Open loop ascent guidance for Falcon-9 rocket first stage, MECO at right timing to keep fuel for landing. This script is running on upper stage
- `Falcon9_lib/f9boostback.ks`: Align to horizontal remaining velocity and fire boostback engines, to a RTLS or drone ship trajectory
- `Falcon9_lib/entryburn.ks`: Wait until altitude reaches 80km, align to remaining velocity direction, fire entryburn engines to decelerate while still targeting target, until the remaining velocity are all executed
- `Falcon9_lib/f9landingburn.ks`: Perform a 2-stage suicide landing burn, the first stage use quadratic guidance to approach target, and the second stage use untargeted landing burn to touchdown safely to recovery site
- `gof9u.ks`: Execute upper stage script, manually activated on launch, responsible for launch, MECO, First stage seperation and keep going
- `gof9d.ks`: Execute first stage script, manually activated before First stage sepration, responsible of boost back, entry burn and final landing burn

## Launch

Timeline:

|Event|Description|
|--|--|
|Main Engine Start|State to activate engines which has `liftoff` in their label|
|Lift Off|After `spoolUpTime` seconds, stage to release launch clamps|
|Vertical Ascent|Hold steering to up until the ship reaches `turnSpeed = 50m/s`|
|Programmed Turn|Pitch down the rocket with angular speed of `pitchOmega = 1 deg/s`, to predefined `targetHeading`|
|MECO|Main Engine Cut Off. When the vessel mass is below `mecoMass`, trigger MECO (deactivate engines)|
|First Stage Sep|1 seconds after MECO, stage to seperate the First stage|
|Upper Stage Ignition|2 seconds after First Stage Sep, stage to activate upper stage engines, unlock steering, activate SAS, and exit program|

## Boost back

Timeline:

|Event|Description|
|--|--|
|Boost back|2 seconds after First Stage Sep|

**Boost back maneuver description**

1. Seach for engines with `boostback` in their label, use them for the maneuver.
2. Decide landing target: first read activated waypoint, if there is no waypoint, then get the geoposition of target vessel. The landing target could move in the whole reentry and landing procedure, so acquire new landing target every time you wanna use it.
3. Align to a horizontal remaining velocity, fire engines until the norm of remaining velocity is increasing (smallest error)
4. Because the First stage sep is triggered on another CPU (upper stage). You can monitor the vessel mass is lower than `boostBackMass` to check if First Stage Sep event has been triggered.

// TODO: Review the remaining velocity equation and assess feasibility
$$
\text{current state:  } (\bold{r, v})\\
\text{landing target:  } \bold{r}_T\\
\text{remaining velocity:  } \bold{v}_g\\
$$

$$
\text{horizontal condition:  } \bold{r}\cdot\bold{v}_g=0\\
\text{aiming condition:  } \bold{r} + (\bold{v} + \bold{v}_g)T + \frac{1}{2}\bold{g}T^2=\bold{r}_T
$$

Solve these equations, we have

$$
T=\frac{1}{g}\left(
    v_r+\sqrt{v_r^2+2gh}
\right)\\
\text{where vertical speed  } v_r=\hat{\bold r}\cdot \bold{v};\text{ altitude  } h=\hat{\bold r}\cdot ({\bold r}-{\bold r}_T)\\
\bold{v}_g=\frac{1}{T}\left(\bold{r}_T - \bold{r} - \frac{1}{2}\bold{g}T^2\right)-\bold{v}
$$

Note: For attitude control while the whole reentry and landing burn procedures, you should decide a roll angle to keep attitude consistent. You can mimic the way how `PEGLand` does it (`the get_target_rotation` function)

Note: in all remaining velocity calculation in the project, use surface velocity (`ship:velocity:surface`) and ignore body spin

## Entry Burn

Timeline:

|Event|Description|
|--|--|
|Entry Burn|Until the altitude hit `EntryBurnAlt = 80km`|

**Entry Burn maneuver description:**

1. Align to `srfretrograde` while gliding & waiting
2. Fire engines (with `entry` in label) as soon as hitting planned altitude, align to remaining velocity
3. Cut off engines when the vertical speed is less than `entryVSpeed = 2km/s`

// TODO: Review the remaining velocity equation and assess feasibility
$$
\text{current state:  } (\bold{r, v})\\
\text{landing target:  } \bold{r}_T\\
\text{remaining velocity:  } \bold{v}_g\\
$$

$$
\text{teminal vertical speed condition:  } 
\hat{\bold{r}}\cdot(\bold{v}+\bold{v}_g)=v_E\\
\text{aiming condition:  } \bold{r} + (\bold{v} + \bold{v}_g)T + \frac{1}{2}\bold{g}T^2=\bold{r}_T
$$

Solve these equations, we have

$$
T=\frac{1}{g}\left(
    v_E+\sqrt{v_E^2+2gh}
\right)\\
\text{where altitude  } h=\hat{\bold r}\cdot ({\bold r}-{\bold r}_T)\\
\bold{v}_g=\frac{1}{T}\left(\bold{r}_T - \bold{r} - \frac{1}{2}\bold{g}T^2\right)-\bold{v}
$$

## Landing Burn

Timeline:

|Event|Description|
|--|--|
|Aerodynamic guidance|As soon as entry burn ended, use pitch and yaw to utilize aerodynamic force to keep predicted impact point near the target|
|Phase 1 landing burn|fire when the landing burn condition is met|
|Phase 2 landing burn|activate when the estimated time is less than 5 seconds|

**Gliding phase description:**

- Use `Trajectories` to predict impact point. You can acquire the impact position using the library function `get_impact_geo`
- Use PID to steer to target landing site (arc impact position error $\bold{e}=(\bold{r}_{impact}-\bold{r}_T)/|\bold{r}-\bold{r}_T|$), central steering is `srfretrograde`

**Final landing phase 1 description:**

1. Acquire landing burn engine, the ones with `landing` in their label. Get thrust and minimum throttle. The reference landing thrust should be in the middle of the feasible thrust range $f_{ref}=\frac{1}{2}(1+\sigma_{min})*f_{max}$
2. Then decide the reference landing burn deceleration  $a_{ref}=f_{ref}/m$
3. Command landing burn deceleration $a_{cmd}=\frac{v^2-v_f^2}{2h}+g$, where $v_f$ is the final touch down speed `touchDownSpeed = 0.2m/s`
4. When the command deceleration is larger than reference deceleration, engage landing phase 1
5. Use the quadratice guidance same in PEGLand. You need to feed a burning time to the guidance, $T = (v-v_f)/(a_{ref}-g)$. Then theoretically the quadratic guidance should keep thrust near the reference throttle.
6. When the remaining time is less than `landingPhase2Time = 5s`, switch to next phase

**Final Landing phase 2 description:**

1. This is an simple untargeted landing guidance. Lock steering to up (of course considering target roll), perform the landing burn sticking to $a_{cmd}$
2. Cutoff if vertical speed is non-negative (implying the rocket is flying upward), or the bottom altitude is lower than 20cm

Note:

1. Ship coordinates: use the scheme `ship:position - bottom_height * up:vector`. Just like `approch phase` in `PEGLand`. Donnot use `bottomaltradar` or center of mass, they are buggy for long thin rocket
2. Deploy landing legs `GEAR ON.` 3 seconds after landing burn phase 2 started
3. update bounding box and `bottom_height` per second because landing legs changes bounding box.


## Implement requirements

1. Declare important parameters in `Falcon9_lib/params.ks` using a `Lexicon` object, and write comments to explain their meanings. This is for convenience if someone want to change parameters to serve his reusable rocket design
2. Before implementation, read `PEGLand` project in the repository, and use quadratic guidance implemented in this project
3. Donnot assume engine parameters, you can use functions in `lib/engine_utility.ks` to search engines and acquire engine parameters
