# Chris_KSP_Lib

kOS scripts for KSP stock or RSS/RO environments.

Video: [[KSP/RSS/RO]PEGLand: 你也许能找到的最方便的定点着陆脚本](https://www.bilibili.com/video/BV1wDd2YDEf1)

## MOD List

- KSP-1.12.5
- kOS: Scriptable Autopilot System-1.4.0.0
- Trajectories-v2.4.5.3 (For pegland)
- WaypointManager (Recommended for pegland)

## PEG Landing

`pegland` is the highlight of this script package, adapted from the PEG launch guidance algorithm developed by NASA in the 1960s for the Surveyor project. It achieves fuel-optimal pinpoint landing in a vacuum environment with an error margin within 100 m.

```kOS
run pegland.  // Default mode
run pegland(1).  // Emergency mode, lands immediately
```

Requirements for using this program:

1. Ensure the spacecraft meets landing requirements: sufficient Δv, final phase $TWR_{min} < 1$.

2. Proper initial orbit and landing point, with the landing point approximately below the periapsis.

3. Set the landing target in the Trajectories mod window. It is highly recommended to use it with WaypointManager:
   1. Create a waypoint on the map using WaypointManager and set navigation to this waypoint.

      ![](./pictures/waypointmanager.png)

   2. Use the active waypoint as the landing target in Trajectories.

      ![](./pictures/trajectories.png)

`pegland` in default mode has three phases:

1. Estimation of ignition position: Iteratively calculates ignition position, time, and initial control parameters.

   ![](./pictures/waitingphase.png)

   ```
   Time to ignition: Countdown to ignition
   T: Estimated landing burn time
   dv: Estimated landing burn Δv
   dtheta: Distance from ignition start position to target position (angle in central body polar coordinates)
   A, B: Pitch control parameters
   ```

2. Powered descent: Automatically adjusts attitude 60s before ignition, performs ullage maneuver and ignition 2s before ignition. Control parameters are iteratively updated during the burn. The throttle remains above the engine's minimum throttle, preventing engine shutdown.

   ![](./pictures/brakingphase.png)

   ```
   Iter: Number of calculation iterations
   T: Estimated remaining burn time
   dv: Estimated remaining burn Δv
   A: Pitch control parameter
   thro: Throttle
   E: Landing position error (angle in central body polar coordinates), positive value indicates landing point is over the target
   ```

3. Final Landing: Adjusts attitude upwards at about 200m above the target point, cancels horizontal velocity, and lands. This phase introduces the main landing error as it does not aim for the target point. A more refined final landing guidance algorithm will be added in future updates.

If the user changes the landing point during descent, the landing program can be interrupted and rerun in emergency mode. The program will then ignite and descend immediately without waiting for gliding to the ignition position.

## Executing Maneuver Nodes

`exe_node` and `exe_pulse_node` are two high-precision maneuver node execution programs for the Principia environment. Maneuver nodes planned in Principia consider the burn process, taking into account changes in burn direction and position, as well as celestial gravitational influences during long maneuvers. Additionally, the thrust of RO engines is not constant, making burn time inaccurate for calculating Δv. `exe_node` and `exe_pulse_node` do not use timing methods; instead, they maintain a Δv integrator to precisely monitor the accumulated Δv during the burn.

- `exe_node` executes Principia maneuver nodes, starting ignition from the node position, always following the burn vector.
- `exe_pulse_node` executes stock maneuver nodes, starting ignition at `T/2` before the node position.

## Planning Orbital Circularization Maneuvers

Running `circularize` will plan an acceleration maneuver node at the apoapsis to circularize the orbit. `circularize(1)` plans a deceleration maneuver at the periapsis.
