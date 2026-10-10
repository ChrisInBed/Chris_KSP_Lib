"""Compare actual flight rows; never rank probes, vacuum, or stale reference rows."""
import argparse
import csv
import math
from collections import defaultdict
from pathlib import Path


def number(row, key):
    try:
        value = float(row.get(key, ""))
        return value if math.isfinite(value) else None
    except (ValueError, TypeError):
        return None


def usable(row, min_density):
    return (row.get("record_kind") == "vehicle"
            and row.get("reference_coherent", "").lower() == "true"
            and row.get("in_atmosphere", "").lower() == "true"
            and row.get("status") == "ok"
            and number(row, "reference_density_kg_m3") is not None
            and number(row, "reference_density_kg_m3") >= min_density
            and number(row, "reference_temperature_k") is not None
            and number(row, "reference_temperature_k") > 0
            and number(row, "reference_pressure_pa") is not None
            and number(row, "reference_pressure_pa") > 0
            and all(number(row, key) is not None for key in
                    ("density_kg_m3", "temperature_k", "pressure_pa")))


def statistics(rows, min_density):
    selected = [row for row in rows if usable(row, min_density)]
    result = {"rows": len(rows), "usable_rows": len(selected),
              "error_rows": sum(row.get("status") == "error" for row in rows),
              "invalid_rows": sum(row.get("status") == "invalid" for row in rows),
              "unavailable_rows": sum(row.get("status") == "unavailable" for row in rows),
              "incoherent_vehicle_rows": sum(row.get("record_kind") == "vehicle" and
                                            row.get("reference_coherent", "").lower() != "true" for row in rows)}
    metrics = [("pressure_pa", "reference_pressure_pa", "pressure_pa"),
               ("temperature_k", "reference_temperature_k", "temperature_k"),
               ("density_kg_m3", "reference_density_kg_m3", "density_kg_m3")]
    for candidate, reference, label in metrics:
        errors = [number(row, candidate) - number(row, reference) for row in selected]
        result[label + "_bias"] = sum(errors) / len(errors) if errors else None
        result[label + "_mae"] = sum(abs(e) for e in errors) / len(errors) if errors else None
        result[label + "_rmse"] = math.sqrt(sum(e * e for e in errors) / len(errors)) if errors else None
        result[label + "_max_abs"] = max(map(abs, errors)) if errors else None
    relative = [(number(row, "density_kg_m3") / number(row, "reference_density_kg_m3") - 1) * 100 for row in selected]
    result["density_relative_mae_percent"] = sum(map(abs, relative)) / len(relative) if relative else None
    result["density_relative_max_abs_percent"] = max(map(abs, relative)) if relative else None
    return result


def write_report(path, groups, min_density, group_names):
    records = [dict(zip(group_names, key), **statistics(rows, min_density)) for key, rows in sorted(groups.items())]
    if not records:
        return
    with path.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(records[0]))
        writer.writeheader()
        writer.writerows(records)
    return records


def compare(paths, output_dir, min_density=1e-8):
    if not math.isfinite(min_density) or min_density <= 0:
        raise ValueError("min_density must be finite and positive")
    groups, regimes = defaultdict(list), defaultdict(list)
    for path in paths:
        with Path(path).open(newline="", encoding="utf-8-sig") as stream:
            reader = csv.DictReader(stream)
            required = {"schema_version", "candidate", "record_kind", "body", "reference_coherent"}
            if not required.issubset(reader.fieldnames or []):
                raise ValueError(str(path) + ": not an atmosphere research CSV")
            for row in reader:
                if row["schema_version"] != "1":
                    raise ValueError(str(path) + ": unsupported schema version")
                groups[(row["body"], row["candidate"])].append(row)
                if row["record_kind"] == "vehicle":
                    sun, latitude, altitude = (number(row, key) for key in ("sun_height_deg", "latitude_deg", "altitude_m"))
                    sun_bin = "unknown" if sun is None else "night" if sun < 0 else "low_sun" if sun < 30 else "high_sun"
                    lat_bin = "unknown" if latitude is None else "south" if latitude < -1 else "north" if latitude > 1 else "equator"
                    alt_bin = "unknown" if altitude is None else str(math.floor(altitude / 10000) * 10) + "_to_" + str((math.floor(altitude / 10000) + 1) * 10) + "_km"
                    regimes[(row["body"], row["candidate"], sun_bin, lat_bin, alt_bin)].append(row)
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    summary = write_report(output_dir / "summary.csv", groups, min_density, ["body", "candidate"])
    write_report(output_dir / "regimes.csv", regimes, min_density, ["body", "candidate", "sun_regime", "latitude_regime", "altitude_regime"])
    for row in summary or []:
        mae = row["density_relative_mae_percent"]
        print(row["body"], row["candidate"], "usable=" + str(row["usable_rows"]),
              "density MAE=" + ("n/a" if mae is None else format(mae, ".6g") + "%"),
              "errors=" + str(row["error_rows"]), "invalid=" + str(row["invalid_rows"]))
    print("Reports:", output_dir.resolve())
    return summary or []


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("csv", nargs="+", type=Path, help="samples.csv files from one or more flights")
    parser.add_argument("--output", type=Path, default=Path("comparison"))
    parser.add_argument("--min-density", type=float, default=1e-8)
    args = parser.parse_args()
    compare(args.csv, args.output, args.min_density)
