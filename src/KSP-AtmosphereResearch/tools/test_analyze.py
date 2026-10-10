import csv
import math
import tempfile
import unittest
from pathlib import Path
from analyze import statistics, usable, compare


def flight(**changes):
    row = dict(schema_version="1", record_kind="vehicle", reference_coherent="True", in_atmosphere="True",
               status="ok", body="Earth", candidate="stock_thermal_now", sun_height_deg="45", latitude_deg="30", altitude_m="20000",
               reference_pressure_pa="100", pressure_pa="110", reference_temperature_k="250", temperature_k="255",
               reference_density_kg_m3="0.1", density_kg_m3="0.12")
    row.update(changes)
    return row


class ComparisonTests(unittest.TestCase):
    def test_error_units_and_recomputed_relative_error(self):
        result = statistics([flight(), flight(pressure_pa="90", temperature_k="245", density_kg_m3="0.08")], 1e-8)
        self.assertEqual(result["usable_rows"], 2)
        self.assertAlmostEqual(result["pressure_pa_bias"], 0)
        self.assertAlmostEqual(result["pressure_pa_rmse"], 10)
        self.assertAlmostEqual(result["temperature_k_mae"], 5)
        self.assertAlmostEqual(result["density_relative_mae_percent"], 20)

    def test_probes_vacuum_stale_nonfinite_and_missing_are_excluded(self):
        for changes in [dict(record_kind="probe"), dict(in_atmosphere="False"), dict(reference_coherent="False"),
                        dict(status="error"), dict(density_kg_m3="NaN"), dict(temperature_k="Infinity"),
                        dict(reference_density_kg_m3="0"), dict(reference_temperature_k="0"), dict(pressure_pa="")]:
            self.assertFalse(usable(flight(**changes), 1e-8))
        result = statistics([flight(status="invalid"), flight(status="unavailable")], 1e-8)
        self.assertEqual(result["usable_rows"], 0)
        self.assertIsNone(result["density_relative_mae_percent"])
        self.assertEqual(result["invalid_rows"], 1)

    def test_csv_round_trip_and_regimes(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "samples.csv"
            row = flight(body='Earth, "RSS"')
            with path.open("w", newline="", encoding="utf-8") as stream:
                writer = csv.DictWriter(stream, fieldnames=list(row))
                writer.writeheader()
                writer.writerow(row)
            results = compare([path], Path(directory) / "comparison")
            self.assertEqual(results[0]["body"], row["body"])
            self.assertTrue((Path(directory) / "comparison" / "regimes.csv").exists())

    def test_invalid_threshold_is_rejected(self):
        for value in (0, -1, math.nan):
            with self.assertRaises(ValueError):
                compare([], Path("unused"), value)


if __name__ == "__main__":
    unittest.main()
