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