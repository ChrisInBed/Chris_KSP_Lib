# Flight test instructions

1. Close KSP. Extract KSP-AtmosphereResearch.zip into your KSP GameData folder. It contains KSPAtmosphereResearch/KSP-AtmosphereResearch.dll and AtmosphereResearch.cfg. Do not copy the reference DLLs or build tools.
2. Start KSP and enter a flight. No special part or MechJeb window is required. A logger-started message appears. Logging follows the active loaded, unpacked vessel automatically.
3. Fly through the atmosphere normally. The default interval is 0.5 real seconds; in-game UT and warp rate are logged independently. Rails warp and packed vessels are skipped. The mod changes no flight controls.
4. Leave flight or close KSP. Collect the complete new folder under KSP/Logs/AtmosphereResearch/<session>/. It contains samples.csv, environment.txt and body configuration snapshots. Data is flushed after each sampling batch.
5. From the project folder run: python tools/analyze.py "<session>/samples.csv" --output "<session>/comparison". Multiple session CSVs can be supplied together. Send the complete session folders back for selecting the candidate.

The staged install directory is artifacts/GameData/KSPAtmosphereResearch. The ZIP is artifacts/KSP-AtmosphereResearch.zip. Extract its KSPAtmosphereResearch directory directly under GameData.

## Useful coverage

Start with your normal RSS/RO/FAR reentry or atmospheric flight, preferably over a changing local sun angle. Then compare flights or quicksave-derived runs at similar altitudes/speeds in daylight, near sunrise/sunset, and at night. Include northern and southern latitudes if practical. Seasonal coverage requires flights/save times at different orbital phases; the mod does not advance the game or rewrite the orbit for you.

Every 30 real seconds, probes sample the same altitude at longitude +90/+180, opposite latitude and both poles, plus -100 m, sea level and one metre below/at/above the atmosphere boundary. These hypothetical locations check spatial sensitivity and singularities. They are tagged probe, have empty live-reference columns, and are excluded from accuracy calculations. They do not prove agreement with flight at those locations.

## Reading the results

- Temperature: use reference_temperature_k (ambient). external_temperature_k includes shock heating and is not the ambient comparison reference.
- Density: reference_density_kg_m3 is the live vessel value. root_part_density_kg_m3 and min/max_part_density_kg_m3 reveal any part-to-part spread.
- reference_coherent=False: the captured vessel and FlightIntegrator disagree, the integrator is missing, or its altitude differs by more than one metre. These rows remain in the CSV but are excluded from summary accuracy metrics.
- status=unavailable/error/invalid: inspect detail and KSP.log. Unavailable means an optional mod/API is absent or has changed. Raw nonfinite results are kept. Do not accept a candidate because it reports few successful samples.
- summary.csv: errors per body/candidate, usable counts, signed bias, MAE, RMSE and maximum absolute errors, with relative density errors in percent. regimes.csv splits vehicle rows by solar angle, hemisphere and 10 km altitude bins.
- The default minimum reference density for ranking is 1e-8 kg/m^3. Override with --min-density if needed. Vacuum and probe rows are never ranked. Compare candidates with adequate coverage and similar usable counts.

All query APIs here use the current ephemeris. These flights validate current conditions, not future-UT prediction. The final AFS/LTR integration remains step 3.

To disable logging, set enabled=false in GameData/KSPAtmosphereResearch/AtmosphereResearch.cfg and restart KSP. To reduce probes, set includeProbes=false. To uninstall, close KSP and remove only GameData/KSPAtmosphereResearch; existing Logs/AtmosphereResearch files remain available.
