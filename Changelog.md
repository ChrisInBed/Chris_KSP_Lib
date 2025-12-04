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