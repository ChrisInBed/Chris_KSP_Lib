## Execute Maneuver Node

- `exe_node` executes Principia maneuver nodes, ignition starts from the node position and always follows the target burn vector
- `exe_pulse_node` executes stock maneuver nodes, ignition starts at `T/2` time before the node position

`exe_node` and `exe_pulse_node` are two high-precision maneuver node execution programs suitable for Principia or stock environments. Compared to other autopilot mods, these two scripts have more powerful capabilities:

- More precise ΔV execution. They don't use a timing method, but maintain an internal ΔV integrator to directly and accurately monitor the ΔV accumulated during the burn;
- Aligns to engine thrust direction rather than ship orientation, suitable for cases where engines are not mounted at the tail. Other autopilot mods, such as MechJeb2's node executor, default to thrust direction facing forward, which is not suitable for some spacecraft designs.

## Plan Orbit Circularization Maneuver

Executing `circularize` will plan an acceleration maneuver node at apoapsis to circularize the orbit. `circularize(1)` plans a deceleration maneuver at periapsis.
