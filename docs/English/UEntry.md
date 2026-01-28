# UEntry: Universal Atmospheric Lift Reentry Guidance

`uentry` is one of the most exciting programs in this mod. From 1960-1980s, NASA developed reentry guidance programs for their capsules and space shuttles, but limited by the computing power of the time, the guidance algorithms were full of empirical parameters and various clever tricks. Today we can run more advanced guidance algorithms on personal computers, using the same algorithm to guide the reentry process of multiple spacecraft. This algorithm is improved from the reentry guidance algorithm published by Lu et al. in 2013. UEntry can achieve:

- High lift-to-drag ratio/low lift-to-drag ratio spacecraft, precise pinpoint guidance for reentry from low orbit/flyby trajectory into the atmosphere
- Considers heat flux, g-load, and dynamic pressure constraints to ensure safe reentry
- Reentry trajectory planner: Plans maneuver nodes before reentry, predicts feasible landing sites, plans reentry process in advance

Reference: [Entry Guidance: A Unified Method](https://arc.aiaa.org/doi/10.2514/1.62605)

## Algorithm Principles

### Lift Reentry

Early capsules used **ballistic reentry** to return to the ground. When the capsule fell into denser atmosphere, drag suddenly increased, causing the ship to slow down. The trajectory was then pulled down by gravity, leading to increased descent rate, which further increased drag. This death spiral continued until the ship's velocity was reduced sufficiently, forcing the brave pioneers inside to endure about 10G of g-load - even the best pilots couldn't reduce this number by a fraction.

So engineers came up with an idea: they shifted the capsule's center of gravity to one side, causing a natural angle of attack during reentry. The capsule in the atmosphere now experiences not only drag but also **lift**. This precious lift allows us to counter gravity and prevent the spacecraft from descending too quickly, enjoying smoother braking in the thin upper atmosphere. Meanwhile, since pilots can control the lift direction, they can plan the reentry trajectory to some extent, making the landing point more precise than ballistic reentry. Capsules using lift reentry can control landing range within a few kilometers, while ballistic reentry has landing errors of tens of kilometers. The space shuttle's lift-to-drag ratio is even better than capsules, capable of reducing peak reentry heat flux by more than 50%, so the space shuttle doesn't need a heavy heat shield.

### Lift Reentry Vehicle Control

- Angle of Attack (AOA, α): The angle between the vehicle's aerodynamic plane and the airflow direction. For most vehicles, lift and drag increase with angle of attack;
- Bank Angle (σ): The angle between the vehicle's lift direction and the vertical plane.

<img src=../pictures/UEntry/bank_scheme.png width=70%>

However, in actual operation, reentry vehicles usually primarily control **bank angle**, while **angle of attack** serves only as auxiliary control or is not controlled at all. There are three main reasons for this:

1. Angle of attack is more difficult to control and maintain. Vehicles rely on RCS and aerodynamic control surfaces to control angle of attack, which can provide limited control torque, so the vehicle's usable angle of attack range is limited. Outside the trim angle of attack, if using RCS control, it will consume large amounts of RCS fuel. Capsule-type spacecraft have almost no pitch control at all; they rely purely on the trim angle of attack caused by center of gravity offset to provide lift. In contrast, bank angle control is much more convenient - the vehicle only needs to roll to the corresponding angle without additional torque to maintain it.
2. Aerodynamic parameters are complex functions of angle of attack and velocity. Without comprehensive understanding of the spacecraft's aerodynamic properties, changing angle of attack makes the trajectory difficult to predict. Bank angle is independent of aerodynamic parameters and only affects lift direction, making guidance calculations much simpler.
3. The safe angle of attack range for reentry vehicles is very narrow; they can only withstand the high temperature of the forward plasma within specific angle of attack ranges. The space shuttle's angle of attack during the early reentry segment is strictly limited with a movable range of only 2°.

Bank angle can control lift direction. When bank angle is 0, the lift component in the gravity direction is maximum, and the ship will enter the atmosphere more slowly or even bounce back to space; when bank angle is 90°, the lift component in the gravity direction is 0, and the ship's altitude profile behaves like ballistic reentry. The guidance algorithm controls descent rate by adjusting bank angle. Descent rate affects future drag, and drag affects range and landing point position, making it possible to achieve landing point control by controlling bank angle.

In UEntry's basic strategy, the angle of attack command is predefined by the user as a function of velocity:

$$\alpha_{cmd}=\alpha_{cmd}(v)$$

The bank angle command is a linear function of specific energy:

$$\sigma_{base}(E)=\sigma_i+(\sigma_f-\sigma_i)\frac{E-E_i}{E_f-E_i}$$

where specific energy $$E=\frac12v^2-\frac{\mu}{r}$$

UEntry uses a standard predictor-corrector guidance method. In one guidance cycle, UEntry integrates the dynamic equations from the current state to calculate the endpoint position, then updates the guidance parameter $\sigma_i$ based on endpoint position error (note that $\sigma_f$ is constant).

Beyond the basic strategy, UEntry also introduces two additional constraint terms: **Quasi-Equilibrium Gliding Condition (QEGC)** and **physical boundary constraints**.

- QEGC is introduced to make the trajectory smoother. High-lift vehicles like to skip along the atmospheric boundary, which isn't friendly for landing point control, so the QEGC constraint term is needed to penalize large changes in flight path angle. The strength of this constraint is controlled by the $k_{QEGC}$ parameter.
- Physical boundary constraints control heat flux, g-load, and dynamic pressure to not exceed user-specified boundaries. UEntry dynamically predicts heat flux, g-load, and dynamic pressure after a future period (T-Lag) during reentry. If any of them exceeds the boundary value, the physical constraint term applies a penalty to the excess. The strength of this constraint is controlled by the $k_C$ parameter. Note this is not a hard boundary - the ship's state may still exceed these boundaries.

Although UEntry can constrain physical states to some extent, it's clear that physical states on the trajectory largely depend on the state at reentry initiation (Entry Interface). Without appropriate initial values, UEntry can hardly save the ship from high temperature, g-load, and overpressure.

<img src=../pictures/UEntry/reentry_corridor_eng.jpg width=60%>

This is the typical reentry constraint profile for the space shuttle; the vertical axis is drag, horizontal axis is velocity. Peak heat flux occurs early in reentry when the ship is still at the atmospheric boundary where air is extremely thin - there isn't enough lift available, and guidance can barely control peak heat flux. Therefore, you need to plan the reentry orbit in advance so that the flight path angle at the entry interface is within a reasonable range. If the flight path angle is too large, the ship will quickly plunge into the atmosphere, causing uncontrollable overheating and g-load; if the path angle is too small, the ship will bounce back to space.

### Cross Range Control

When you bank your ship to the right, not only does vertical lift decrease, but horizontal rightward lift also increases. This gives your ship some cross range maneuver capability, allowing you to fly to areas outside the orbital plane. High lift-to-drag ratio vehicles have excellent cross range maneuver capability - the space shuttle can even tolerate cross range errors of thousands of kilometers. UEntry uses a very simple cross range control strategy: when it finds the target azimuth and current velocity heading error exceeds a threshold (Heading Tol), UEntry switches the bank direction to the other side.

## Using UEntry

Unlike PEGLand's convenience, UEntry requires some setup to run properly. To understand the role of various parameters, it's recommended you read the [Algorithm Principles](#algorithm-principles) section before this section.

### Step 1. Set Landing Target

Open the kOS terminal and enter the following command:

```kOS
switch to 0.  // Switch to the flight center's document system
run uentry.  // Run UEntry
```

Use the Waypoint Manager mod to set and activate a waypoint, which should be located near the orbital plane. Then in the UEntry interface's `Target` section, set reasonable terminal altitude, velocity, and distance and bearing from the target point. The meaning in the figure below is: the reentry segment target is located at 280° bearing (10° west of north) 50 kilometers from the activated waypoint, altitude 20 kilometers, velocity 500m/s.

After setting, click `Update Target` to update the reentry segment target.

⚠**Note**: Pay attention to body rotation. If you have Principia installed, please use the body-fixed reference frame to view the trajectory.

<img src=../pictures/UEntry/waypointmanager.png width=50%>
<img src=../pictures/UEntry/target.png width=50%>

### Step 2. Calculate Aerodynamic Parameters

Click the `Open Aerodynamic Profile GUI` button in the UEntry interface to open the startup parameter settings interface

![](../pictures/UEntry/aerodynamic_profile.png)

#### 2-1. Set Reentry Attitude

You need to adjust `Pitch, Yaw, Roll` and click `Set Attitude`. The correct reentry attitude is: `Forward` points to the forward direction during reentry (when angle of attack is 0), `Up` points to the lift direction, `Right` points to the ship's starboard. The figure above shows two correct examples. Additionally, you need to ensure that when angle of attack is positive, lift points in the `Up` direction. If your ship doesn't meet this condition, you need to check `Reverse AOA` to reverse the angle of attack. For example, for the Apollo command module in the right figure, pitching down produces positive lift, so the angle of attack needs to be reversed.

#### 2-2. Set Angle of Attack Curve

UEntry assumes angle of attack is a function of velocity. It will interpolate between the $(Speed,AOA)$ coordinate points you input to find the angle of attack corresponding to current velocity. You need to enter a series of comma-separated numbers in `Speed Profile` and `AOA Profile`, corresponding one-to-one vertically.

1. How to obtain usable angle of attack?
    - For space shuttle: In SPH, open the FAR mod interface, set pitch to +1, simulate the pitch moment (Cm, yellow) curve over a certain angle of attack range. The intersection of this curve with the X-axis is the maximum usable angle of attack.
    - For capsules: You can use a similar method. You can also simulate the capsule's uncontrolled reentry in flight scene and observe the trim angle of attack.
2. ⚠**Note**: The sequences filled in `Speed Profile` and `AOA Profile` must be equal length.
3. ⚠**Note**: The sequence filled in `Speed Profile` must be monotonically increasing.
4. ⚠**Note**: Use English commas, not Chinese full-width commas.

#### 2-3. Calculate Aerodynamic Parameters

UEntry calculates aerodynamic parameters for sample points within a certain altitude and velocity range, using bilinear interpolation to obtain aerodynamic parameters during guidance operation. Set the altitude and velocity ranges below, as well as the number of grid points. More grid points mean more accurate data but greater computational overhead. Total grid points equal altitude grid points × velocity grid points.

After setting, click `Update Profiles` to update the angle of attack curve and calculate grid points. When the grid size is 64x64, this step takes about a few seconds to complete.

⚠**Note**: Can only calculate aerodynamic parameters for the **current spacecraft**, cannot predict aerodynamic parameters for future stages. For example, for the Apollo spacecraft, you need to separate the service module first before getting the command module's aerodynamic parameters. You can do this: save -> separate service module -> calculate aerodynamic parameters and save (see [this section](#step-4-saveload-parameters) for save method) -> load back to state before separation -> load previously calculated aerodynamic parameters.

⚠**Note**: You cannot calculate atmospheric aerodynamic parameters for a target body while in another body's sphere of influence. Please wait until the spacecraft enters the target body's SOI before calculating.

### Step 3. Plan Reentry Maneuver and Parameters

Accurate and safe reentry = reasonable reentry orbit + reasonable guidance parameters

Set appropriate guidance parameters in the Guidance Parameters section of the UEntry interface (the role of each guidance parameter is shown in the table below). If you think the current ship is not on a suitable reentry orbit, you can open your favorite planner to plan a maneuver node. The two buttons at the bottom of the UEntry interface can predict the endpoint position under the current maneuver node and parameter settings (green for predicted point, red for target point), and display them on the map. Try setting different maneuver nodes and guidance parameters until the green and red arrows roughly coincide and the info box shows appropriate status.

⚠**Note**: You cannot calculate landing position on the target body while in another body's sphere of influence. Please wait until the spacecraft enters the target body's SOI before planning.

⚠**Note**: UEntry's predictor is based on Keplerian orbit calculations. If you use Principia, gravitational perturbations from other bodies will cause deviations. You can select the `Display orbit patch` option in the Principia interface to view the deviation between Keplerian orbit and n-body gravity orbit, and wait until the deviation is small enough before planning.

⚠**Note**: UEntry's atmospheric trajectory predictor has an upper limit of 3600 seconds. If the vehicle still cannot complete deceleration after this time, the predictor will give a `TIMEOUT` result, which usually means the vehicle has insufficient deceleration and has bounced back to space. Try reducing flyby altitude, increasing `Initial Bank` `Final Bank` `Max Bank`, and check constraint parameters.

<img src=../pictures/UEntry/planner.png width=100%>

**Guidance Parameters Summary**

|Parameter|Description|
|--|--|
|Maneuver Node|The larger the path angle at entry interface, the higher the heat flux and g-load peaks, the shorter the range; too small path angle may cause the vehicle to bounce back to space|
|`Initial Bank`|i.e. $\sigma_i$, this value should be less than `Max Bank`. The larger its value, the higher the heat flux and g-load peaks, the shorter the range, and it also affects cross range maneuver capability. This value is optimal at 2/3 of `Max Bank`|
|`Final Bank`|i.e. $\sigma_f$, this value should be less than `Max Bank`. The larger its value, the higher the heat flux and g-load peaks, the shorter the range, and it also affects cross range maneuver capability. This value can be freely adjusted between 0 and `Max Bank`|
|`Max Bank`|Maximum allowed bank angle|
|`Heading Tol`|Maximum allowed heading error. When heading error exceeds this value, it triggers a bank reversal maneuver. If this value is too small, bank reversal maneuvers will be too frequent, affecting reentry accuracy; too large and heading error cannot be corrected in time. You can also click `Force Reversal` to manually trigger a bank reversal maneuver|
|`M.HeatFlux`|Peak heat flux boundary|
|`M.Load`|Peak g-load boundary|
|`M.DynP`|Peak dynamic pressure boundary|
|`Min Lift`|Minimum lift acceleration. When lift acceleration during reentry is below this value, only the basic strategy is enabled; when it exceeds this value, the guidance algorithm considers QEGC and physical boundary constraints|
|`QEGC Gain`|QEGC constraint strength. Appropriately increasing this value can prevent the vehicle from skipping at the atmospheric boundary, making the reentry trajectory smoother; but if this value is too large, it will reduce the guidance algorithm's degrees of freedom and narrow the landing range|
|`Constraint Gain`|Physical state constraint strength. Appropriately increasing this value can prevent the vehicle from exceeding predicted physical state boundaries; if this value is too large, it will reduce the guidance algorithm's degrees of freedom and narrow the landing range|
|`Lag T`|Physical state prediction time. When considering physical state constraints, the guidance algorithm predicts physical states after `Lag T` time. When your physical state changes rapidly, you can appropriately reduce this value|

### Step 4. Save/Load Parameters

After setup, you can save this set of parameters as a preset. Enter a custom preset name in the save/load section and click `Save` to save. Preset files are stored in the `<Game Root Directory>\Ships\Script\entry_presets` folder. You can share this file with others or install others' preset files. To load a preset, select the target preset in the load option and click `Load`.

I've also provided some preset files for typical vehicles. When setting your own parameters, you can modify based on templates:

- `shuttle`: Space shuttle LEO return guidance preset, model from benjee10's Shuttle Orbiter Construction Kit
- `Apollo`: Apollo command module return from Moon guidance preset, model from ROCapsules
- `Gemini`: Gemini capsule LEO return guidance preset, model from ROCapsules

⚠**Note**: Vehicle mass and aerodynamic shape have significant effects on reentry trajectory. If your vehicle state differs from the preset, this will cause considerable error.

<img src=../pictures/UEntry/presets.png width=50%>

### Step 5. Activate Reentry Guidance

Click `ACTIVATE GUIDANCE` to activate guidance control, which will start adjusting reentry attitude 60 seconds before entering the atmosphere. Due to errors in UEntry's orbit predictor, try to activate guidance control within 10 minutes before reentry.

The `Guidance State` section in the UEntry interface displays key state parameters. Most parameters don't need explanation; the key ones are:

- `Bank_i` i.e. $\sigma_i$, this value should smoothly transition from initial $\sigma_i$ to $\sigma_f$ over time. If it changes too quickly, it usually means aerodynamic parameters are inaccurate - please update aerodynamic parameters; or the flight control system has large errors - please adjust flight control parameters (see below)
- `AOA` Angle of attack. Outside parentheses is current actual angle of attack, inside parentheses is the angle of attack required by guidance command. If deviation is too large, please adjust flight control parameters (see below)
- `Bank` Bank angle. Outside parentheses is current actual bank angle, inside parentheses is the bank angle required by guidance command. If deviation is too large, please adjust flight control parameters (see below)

UEntry has built-in flight control (KCL Controller), but the same set of flight control parameters may not be able to handle both high altitude/high speed and low altitude/low speed segments. When your spacecraft control has the following problems, you can take corresponding solutions:

- Angle of attack error cannot be eliminated
    - If vehicle pitch control is near the limit and still cannot approach target angle of attack, this means the target angle of attack exceeds the spacecraft's design limits - please adjust the angle of attack curve
    - If the vehicle doesn't seem to be trying to pitch to approach target angle of attack, please increase `Pitch Kp` and `Pitch Ki`
- Vehicle control is oscillating
    - Please reduce `Kp` and `Ki` corresponding to Pitch, Yaw, or Roll, or increase `Kd`
    - Physical time acceleration can also cause control oscillation; the above solution is still valid
- Vehicle rolls too fast/slow
    - Please adjust `Upper` in `Rotational Rate Controller`, which indicates the maximum allowed rotation rate. `Upper = 5` means at most 5° per second

⚠**Note**: Other autopilots like SAS, MechJeb Smart A.S.S., Atmosphere Autopilot, etc. will compete with UEntry for control, causing the ship to shake violently or completely lose control. Please turn them off.

⚠**Note**: After the spacecraft's energy drops below the energy of the user-set terminal state, the UEntry program ends and releases control. If your spacecraft is not aerodynamically statically stable at low altitude, it may lose control - quickly turn on other autopilots to stabilize spacecraft attitude.

Tips: At high altitude, aerodynamic control surfaces don't provide enough torque, and the ship needs RCS to control attitude. But as altitude decreases, the required torque increases. Continuing to use RCS at this point causes serious fuel waste. You need to gradually reduce the strength of each RCS thruster, smoothly transitioning from RCS to aerodynamic control surface control.

Tips: Capsules have a natural trim angle of attack in the atmosphere. If your spacecraft tries to maintain a value outside the trim angle of attack, it will consume large amounts of RCS fuel. You can click the `Pitch Damper Only` button at the appropriate time, and the flight control system will no longer try to track the commanded angle of attack. At this point, the ship's pitch control only serves as a damper, consuming almost no fuel.

Tips: Click `EMERGENCY SUPPRESS` to temporarily disconnect kOS control of the spacecraft. When UEntry behaves strangely, you can use this function to manually take over spacecraft control.

![](../pictures/UEntry/kcl.png)
