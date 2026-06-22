# Changelog

## 2025/04/11 v0.1

- pegland
- exe_node, exe_pulse_node
- circularize

## 2025/04/12 v0.2

- Corrected the error of PEG burn time prediction formula in the original technical document, using a more accurate approximation for landing.
- Optimized the final landing phase. The script now supports landing with limited-throttle or non-throttleable engines; supports engine restarts; supports multi-stage rocket landings. However, engines with limited throttling (minimum throttle above 65%) or no throttling cannot guarantee landing precision. The higher the thrust-to-weight ratio in the final phase, the less safe the landing.

## 2025/04/15 v0.3

- Reconstruct code hierarchy
- Added quadratic guidance
- Added special version `peglandprec` for Apollo LM landing

## 2025/04/29 v0.4

- Optimized iteration efficiency in PEG guidance
- Optimized throttle control in PEG guidance
- Optimized efficiency in quadratic landing guidance
- Add landing target adjustment function, make it easy for landing with limited-throttling engines

## 2025/05/06 v0.5

- Optimized terminal landing guidance
- Optimized landing target adjustment function and landing error display

## 2025/05/24 v0.6

- Optimized landing attitude and guidance target in `peglandprec`

## 2025/06/10 v0.7

- Add GUI interaction for PEGLand, enabling visual adjustment of landing site
- Replace the PEG algorithm with space shuttle launch guidance to allow for large off-axis landings
- Modify the PEG algorithm to account for celestial body rotation, permitting landings on rapidly rotating bodies
- Optimize the secondary guidance phase and final landing control

## 2025/11/12 v0.8

- Add analysis of initial landing orbit
- Add slope prediction of the target landing site, and automatically search for flat place to land
- Add Emergency Suppress function
- Add guidance divergence check, so that the program can correctly exit if the iterative calculation diverged

## 2025/11/27 v0.8.1

- Optimize GUI interaction logic
- Add function: search engine by label
- Fixed bug: cannot modify engine thrust

## 2025/11/28 v0.8.2

- Optimize final phase landing strategy to adopt a 2-stage constant thrust approach, achieving fuel optimal. This 
  version is feasible in non-targeted landing senario when the height or speed is large.

## 2025/12/19 v0.8.3

- Optimized flight control, aligning engine thrust vector rather than ship facing to maneuver direction. Influenced
  scripts:
  - `exe_node.ks`
  - `exe_pulse_node.ks`
  - `pegland.ks`

## 2026/01/19 v0.8.4

- Fixed bug in PEGLand terminal phases

## 2026/01/28 v0.9

Major version update

- Added GPLv3 license
- Added high-performace calculation backend `AFS`
- Added `UEntry`
- Reformed documentations

## 2026/03/02 v0.9.1

- Fixed some bugs in UEntry GUI
- Added correction mechanism to aerodynamic coefficient calculation. It allows the user to correct prediction error in aerodynamic profile generation.

## 2026/04/06 v0.9.2

- Add localization ability (EN-US and ZH-CN for now)
- Improve orbit analysis equations in PEGLand
- Eliminate dead loop in PEGLand initialization

## 2026/04/06 v0.9.3

- Fixed Bug: Removed Burst Compiler code in `kOS-AFS`, to avoid FARc causing Unity Burst failure. [issue](https://github.com/KSPModdingLibs/KSPBurst/issues/14)

## 2026/04/18 v0.9.4

- Added trajectory shaping function in PEGLand
- Improved descent phase target settings, added `Quit Time` parameter
- Fixed Bug: When press the emergency suppress button in UEntry, the flight control cannot be suppressed.
- Fixed Bug: Minor error in reference frame transformation in PEGLand

## 2026/04/26 v0.9.5

- PEGLand Orbit Analysis takes maneuver node into account
- PEGLand descent phase ignition point consider engine spool-up time
- Fixed some problems in GUI

## 2026/05/07 v0.9.6

- Improve Isp calculation for hybrid engine configuration

## 2026/05/08 v0.9.7

- PEGLand
  - Autodetection for hovering ability and whether to add approch phase
  - Improve final phase, using trinomial approximation for thrust integrals
  - Add "use impact point as target" function, ease suborbital landing

## 2026/05/09 v0.9.8

- PEGLand: Fixed issue: sometimes you cannot manually move target landing site left/right/forward/backward
- PEGLand: Update bounding box while staging to ensure landing safety

## 2026/06/06 v0.9.9

- PEGLand: Fixed issue: Inaccurate coordinate system in approach phase. Now approach phase works well for large lander designs
- UEntry: Fixed issue: stop trying to track reference trajectory in last minute
- UEntry: Add 2 example reentry configurations for Space Shuttle (Space Shuttle Systems) and X-20