# Falcon 9 Reusable First-Stage Tutorial

Switch to the [Chinese version](../%E4%B8%AD%E6%96%87/Falcon9.md).

## 1. What this program does

The Falcon 9 project is a pair of kOS programs for a two-stage rocket with a reusable first stage:

- `f9ascent.ks` provides a basic launch, programmed pitch-over, main-engine cutoff, stage separation, and upper-stage ignition.
- `f9recovery.ks` guides the separated booster through boostback, entry, aerodynamic correction, and landing.

Recovery uses FAR and the `kOS-LTR` addon to estimate where the booster will land. It repeatedly corrects the trajectory toward the landing site selected in the recovery boot file.

> [!IMPORTANT]
> The ascent guidance is deliberately **very simple open-loop guidance**. It is completely separate from the recovery guidance. You do **not** have to use it.
>
> Launch with MechJeb, PEGAS, another kOS program, or fly manually if you prefer. The recovery program only cares about the booster state after separation. However, **you are responsible for leaving the first stage with enough fuel, working engines, and a recoverable trajectory.** No landing program can recover a booster whose ascent used all of its propellant.

## 2. The complete flight in simple terms

![Protocol](../pictures/Falcon9/protocol.jpg)

1. The upper-stage kOS CPU loads the optional ascent boot file and waits for Action Group 10.
2. The booster kOS CPU loads the recovery boot file and waits for stage separation.
3. Press `0` to toggle Action Group 10 and start the included launch program, or launch with another guidance system.
4. After separation, the booster detects its new mass and starts recovery.
5. It performs a boostback burn toward the configured landing site.
6. It performs an entry burn and uses aerodynamic steering during descent.
7. It starts the landing burn, deploys the landing legs, and shuts the engines down at touchdown.

The ascent and recovery CPUs do not need to share one guidance program. Separation is the handoff between two independent jobs.

## 3. Before building the rocket

Install and verify:

- kOS
- Ferram Aerospace Research (FAR)
- Chris GNC Suite v1.0.0 or later
- one kOS CPU on the first stage and one on the upper stage

The example Falcon 9 craft will be provided in the repository's `/crafts` directory. Its engine layout is used in the following steps.

## 4. Assign the engine tags

The scripts find engines by checking whether an engine's kOS tag contains the configured text. This allows one engine to have several roles in a single combined label.

This repository includes an example Falcon 9 rocket, [Falcon9_RP1](../../crafts/Falcon9_RP1.craft), built entirely with parts from an RP-1 installation. You can use it as a reference while learning the program. Assign its nine first-stage engines as follows:

| Engines | Count | kOS tag |
|---|---:|---|
| Outer liftoff-only engines | 6 | `liftoff` |
| Boostback and entry engines | 2 | `liftoff_boostback_entry` |
| Center landing engine | 1 | `liftoff_boostback_entry_landing2` |

These labels produce the following engine groups:

- `liftoff` matches all nine engines;
- `boostback` matches the two intermediate engines and the center engine;
- `entry` matches the same three engines;
- `landing2` matches only the center engine.

The underscores are only separators for people reading the label. Matching is based on the contained words.

![kOS engine labels](../pictures/Falcon9/kOSlabels.png)

## 5. Configure the ascent boot file

Start from [`Script/boot/f9ascent.ks`](../../Script/boot/f9ascent.ks) and edit its `F9_ASCENT_PARAMS` lexicon for your vehicle. For the example engine layout, keep:

```ks
"liftoffEngineTag", "liftoff",
```

Check these vehicle-specific values:

- `mecoMass`: total vehicle mass at first-stage main-engine cutoff, including the upper stage and payload still attached;
- `targetHeading`: launch azimuth;
- `targetRoll`: commanded vehicle roll;
- `turnSpeed`: speed at which the programmed pitch-over begins;
- `pitchOmega`: pitch-down rate of the open-loop ascent.

This file is only a convenient example ascent. It does not target an orbit and it does not optimize fuel. If you already use a capable ascent autopilot, skip this boot file and let that system fly the ascent. [PEGAS](https://github.com/Noiredd/PEGAS) provides PEG-based ascent guidance and supports reserving first-stage propellant for reusable launch vehicles.

## 6. Configure the recovery boot file

Start from [`Script/boot/f9recovery.ks`](../../Script/boot/f9recovery.ks) and edit its `F9_PARAMS` lexicon.

For the example engine layout, use:

```ks
"boostbackEngineTag", "boostback",
"entryEngineTag", "entry",
"landingDecEngineTag", "landing2",
"landingEngineTag", "landing2",
```

Here the center engine is both the landing deceleration engine and the final landing engine. Other vehicles may use a larger engine group for initial deceleration and a smaller group for the final landing.

Set `boostBackMass` slightly above the expected mass of the separated booster, but below the mass of the attached launch vehicle. Recovery waits until the first-stage vessel mass falls below this value.

### Select a landing site

Choose exactly one source with `landingSiteUse`:

**Fixed longitude and latitude:**

```ks
"landingSiteUse", "geo",
"landingSiteGeo", LIST(longitude, latitude),
```

**Named waypoint:**

```ks
"landingSiteUse", "waypoint",
"landingSiteWaypoint", "VAB",
```

**Named vessel, such as a drone ship:**

```ks
"landingSiteUse", "vessel",
"landingSiteVessel", "drone",
```

Names must match exactly. Use `altitudeOffset` if the desired touchdown point is above or below the waypoint or vessel reference position.

For a first test flight, keep the remaining prediction, aerodynamic, and landing values from the provided example boot file. They are vehicle-specific and may need later flight testing, but they do not need an equation-by-equation setup.

## 7. Install the boot files on the two CPUs

In the editor:

1. Select `f9recovery.ks` as the boot file for the **first-stage** kOS CPU.
2. Select `f9ascent.ks` as the boot file for the **upper-stage** kOS CPU if you want to use the included ascent.
3. Check the staging order for main-engine start, launch release, stage separation, and upper-stage ignition.
4. Confirm that the landing target already exists if you selected a waypoint or vessel.
5. Confirm that the first stage has enough propellant and engine ignitions for boostback, entry, and landing.

The recovery boot file begins running before launch, but it will wait for the configured post-separation mass before commanding the booster.

## 8. Launch the example rocket

1. Install the example craft, [Falcon9_RP1](../../crafts/Falcon9_RP1.craft).
2. Put the rocket on the launch pad.
3. The upper-stage terminal should display `Activate AG10 to enable launch.`
4. Press keyboard `0`. In KSP this toggles Action Group 10 and starts the included launch sequence.
5. Watch the staging and confirm that the booster recovery display becomes active after separation.
6. After upper-stage ignition, the ascent script asks for another Action Group 10 change. Press `0` again to release its steering and throttle locks, then continue the upper-stage flight with your preferred guidance.
7. A vessel outside the physics loading range is no longer actively controlled, so switch back to the first stage quickly while it is recovering. Alternatively, use FMRS to fly the upper stage and booster separately.

If you are using MechJeb, PEGAS, or manual ascent, do not run the included ascent boot file. Launch and separate normally; the first-stage recovery CPU will still perform its own sequence.

> [!WARNING]
> Recovery independence does not mean recovery is physically unlimited. Your ascent must leave enough first-stage propellant, avoid an impossible downrange error, and separate while the booster can still restart its engines. **Fuel reserve is the responsibility of the ascent plan and the player.**

## 9. Quick troubleshooting

- **The launch does not start:** verify that the upper-stage CPU uses `f9ascent.ks`, then press `0` to activate Action Group 10.
- **An engine group is missing:** check spelling and capitalization inside the combined engine tags.
- **Recovery never starts:** verify the booster CPU boot file and make sure the separated booster mass is below `boostBackMass`.
- **The target is unavailable:** check `landingSiteUse` and the exact waypoint or vessel name.
- **The booster runs out of fuel:** change the ascent profile, MECO point, payload, or recovery plan so that the first stage retains a realistic reserve.
