#!/usr/bin/env python3
"""Independent numerical checks and plots for kOS-GFOLD CLI output."""
import argparse
import json
import math
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
from scipy.integrate import solve_ivp


def frame(scenario):
    ref = np.asarray(scenario["pitCenter"], dtype=float)
    omega = np.asarray(scenario["bodySpin"], dtype=float)
    up = ref / np.linalg.norm(ref)
    east = np.cross(omega, up)
    if np.linalg.norm(east) < 1e-10:
        seed = np.eye(3)[np.argmin(np.abs(up))]
        east = np.cross(seed, up)
    east /= np.linalg.norm(east)
    north = np.cross(up, east)
    north /= np.linalg.norm(north)
    return ref, np.vstack((east, up, north)), omega


def analyze(scenario, result):
    if not result.get("ok"):
        raise ValueError(f"planner did not solve: {result.get('status')}: {result.get('message')}")
    tr = result["trajectory"]
    t = np.asarray([q["time"] for q in tr], dtype=float)
    rb = np.asarray([q["position"] for q in tr], dtype=float)
    vb = np.asarray([q["velocity"] for q in tr], dtype=float)
    thrust = np.asarray([q["thrust"] for q in tr], dtype=float)
    mass = np.asarray([q["mass"] for q in tr], dtype=float)
    ref, rlb, omega = frame(scenario)
    local_p = (rlb @ (rb - ref).T).T
    local_v = (rlb @ vb.T).T
    local_t = (rlb @ thrust.T).T
    elapsed = t - result["epoch"]
    speed = np.linalg.norm(vb, axis=1)
    thrust_norm = np.linalg.norm(thrust, axis=1)
    tilt = np.degrees(np.arccos(np.clip(local_t[:, 1] / np.maximum(thrust_norm, 1e-15), -1, 1)))
    radial = np.linalg.norm(local_p[:, [0, 2]], axis=1)
    rs = scenario["pitRadius"] - scenario["wallBuffer"]
    entry = elapsed >= result["te"] - 1e-8 if scenario["pitDepth"] > 0 else np.zeros(len(t), dtype=bool)
    switch = elapsed >= scenario["engineSwitchTime"] - 1e-8
    min_thrust = np.where(switch, scenario["thrustMin2"], scenario["thrustMin1"])
    max_thrust = np.where(switch, scenario["thrustMax2"], scenario["thrustMax1"])
    speed_limit = np.where(entry, scenario["entryMaxSpeed"], scenario["descentMaxSpeed"])
    tilt_limit = np.where(entry, scenario["entryTilt"], scenario["descentTilt"])
    terminal = result["tf"] - elapsed <= scenario["terminalTiltWindow"] + 1e-8
    tilt_limit = np.where(terminal, np.minimum(tilt_limit, scenario["terminalTilt"]), tilt_limit)

    finite = bool(np.all(np.isfinite(np.concatenate((t, rb.ravel(), vb.ravel(), thrust.ravel(), mass)))))
    time_margin = float(np.min(np.diff(t))) if len(t) > 1 else math.inf
    mass_margin = float(np.min(mass[:-1] - mass[1:])) if len(mass) > 1 else math.inf
    thrust_lower_margin = float(np.min(thrust_norm - min_thrust))
    thrust_upper_margin = float(np.min(max_thrust - thrust_norm))
    speed_margin = float(np.min(speed_limit - speed))
    tilt_margin = float(np.min(tilt_limit - tilt))
    target = np.asarray(scenario["targetPosition"], dtype=float)
    target_v = np.asarray(scenario["targetVelocity"], dtype=float)
    terminal_position_error = float(np.linalg.norm(rb[-1] - target))
    terminal_velocity_error = float(np.linalg.norm(vb[-1] - target_v))
    geometry_margin = math.inf
    for i in range(len(t)):
        if entry[i]:
            geometry_margin = min(geometry_margin, rs - radial[i], local_p[i, 1] + scenario["pitDepth"], -local_p[i, 1])
        else:
            cone = local_p[i, 1] - math.tan(math.radians(scenario["descentGlideSlope"])) * (radial[i] - rs)
            geometry_margin = min(geometry_margin, local_p[i, 1], cone)

    # Independently integrate exact rotating-frame physics. The public schema has one
    # thrust at an event node, so intervals ending at a discontinuity are omitted.
    exact_pos_error, exact_vel_error, exact_intervals = 0.0, 0.0, 0
    mu = scenario["mu"]
    u = thrust / mass[:, None]
    event_times = [result["epoch"] + scenario["engineSwitchTime"]]
    if scenario["pitDepth"] > 0:
        event_times.append(result["epoch"] + result["te"])
    for i in range(len(t) - 1):
        if any(abs(t[i + 1] - e) < 1e-7 for e in event_times):
            continue
        dt = t[i + 1] - t[i]
        y0 = np.concatenate((rb[i], vb[i]))
        def rhs(tau, y):
            f = np.clip(tau / dt, 0.0, 1.0)
            acc_cmd = (1 - f) * u[i] + f * u[i + 1]
            r, vel = y[:3], y[3:]
            gravity = -mu * r / np.linalg.norm(r) ** 3
            acc = gravity - 2 * np.cross(omega, vel) - np.cross(omega, np.cross(omega, r)) + acc_cmd
            return np.concatenate((vel, acc))
        sol = solve_ivp(rhs, (0, dt), y0, rtol=2e-10, atol=1e-11, method="DOP853")
        exact_pos_error = max(exact_pos_error, float(np.linalg.norm(sol.y[:3, -1] - rb[i + 1])))
        exact_vel_error = max(exact_vel_error, float(np.linalg.norm(sol.y[3:, -1] - vb[i + 1])))
        exact_intervals += 1

    summary = {
        "ok": finite and time_margin > 0 and mass_margin >= -1e-7 and thrust_lower_margin >= -1e-3
              and thrust_upper_margin >= -1e-3 and speed_margin >= -1e-3 and tilt_margin >= -1e-3
              and geometry_margin >= -0.02 and terminal_position_error <= 0.02 and terminal_velocity_error <= 0.02,
        "finite": finite,
        "nodes": len(t),
        "solveTime": result["solveTime"],
        "searchEvaluations": result["searchEvaluations"],
        "margins": {
            "minimumTimeStep_s": time_margin,
            "minimumMassDecrease_t": mass_margin,
            "thrustLower_kN": thrust_lower_margin,
            "thrustUpper_kN": thrust_upper_margin,
            "speed_mps": speed_margin,
            "tilt_deg": tilt_margin,
            "geometry_m": geometry_margin,
        },
        "terminalPositionError_m": terminal_position_error,
        "terminalVelocityError_mps": terminal_velocity_error,
        "exactPropagation": {"checkedIntervals": exact_intervals, "maxPositionError_m": exact_pos_error, "maxVelocityError_mps": exact_vel_error},
    }
    arrays = dict(t=t, elapsed=elapsed, local_p=local_p, speed=speed, speed_limit=speed_limit,
                  mass=mass, thrust_norm=thrust_norm, min_thrust=min_thrust, max_thrust=max_thrust,
                  tilt=tilt, tilt_limit=tilt_limit, rs=rs)
    return summary, arrays


def plots(arrays, output):
    output.mkdir(parents=True, exist_ok=True)
    p = arrays["local_p"]
    fig = plt.figure(figsize=(8, 6))
    ax = fig.add_subplot(111, projection="3d")
    ax.plot(p[:, 0], p[:, 2], p[:, 1], marker="o", label="trajectory")
    ax.scatter([0], [0], [p[-1, 1]], marker="*", s=100, label="target")
    ax.set(xlabel="east (m)", ylabel="north (m)", zlabel="up (m)")
    ax.legend(); fig.tight_layout(); fig.savefig(output / "trajectory.png", dpi=150); plt.close(fig)
    e = arrays["elapsed"]
    fig, axes = plt.subplots(4, 1, figsize=(9, 11), sharex=True)
    axes[0].plot(e, arrays["speed"], label="speed"); axes[0].plot(e, arrays["speed_limit"], "--", label="limit"); axes[0].set_ylabel("m/s"); axes[0].legend()
    axes[1].plot(e, arrays["mass"]); axes[1].set_ylabel("mass (t)")
    axes[2].plot(e, arrays["thrust_norm"], label="thrust"); axes[2].plot(e, arrays["min_thrust"], "--"); axes[2].plot(e, arrays["max_thrust"], "--"); axes[2].set_ylabel("thrust (kN)")
    axes[3].plot(e, arrays["tilt"], label="tilt"); axes[3].plot(e, arrays["tilt_limit"], "--", label="limit"); axes[3].set_ylabel("degrees"); axes[3].set_xlabel("elapsed time (s)")
    fig.tight_layout(); fig.savefig(output / "constraints.png", dpi=150); plt.close(fig)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--scenario", required=True, type=Path)
    ap.add_argument("--result", required=True, type=Path)
    ap.add_argument("--output-dir", required=True, type=Path)
    args = ap.parse_args()
    scenario = json.loads(args.scenario.read_text(encoding="utf-8"))
    result = json.loads(args.result.read_text(encoding="utf-8"))
    summary, arrays = analyze(scenario, result)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    (args.output_dir / "summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    plots(arrays, args.output_dir)
    print(json.dumps(summary, indent=2))
    raise SystemExit(0 if summary["ok"] else 2)


if __name__ == "__main__":
    main()
