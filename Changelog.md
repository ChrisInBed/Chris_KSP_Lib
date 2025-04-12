# Changelog

## 2025/04/11 v0.1

- pegland
- exe_node, exe_pulse_node
- circularize

## 2025/04/12 v0.2

- Corrected the error of PEG burn time prediction formula in the original technical document, using a more accurate approximation for landing.
- Optimized the final landing phase. The script now supports landing with limited-throttle or non-throttleable engines; supports engine restarts; supports multi-stage rocket landings. However, engines with limited throttling (minimum throttle above 65%) or no throttling cannot guarantee landing precision. The higher the thrust-to-weight ratio in the final phase, the less safe the landing.