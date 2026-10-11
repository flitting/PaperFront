#!/usr/bin/env python3
"""Run isolated long AI economy observations and documented loss recovery.

The passive enemy HQ has extended HP, solely to retain the observation window.
These fixtures never enter the ordinary 1v1 balance win-rate denominator.
"""
from concurrent.futures import ThreadPoolExecutor, as_completed
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time

from headless_export_manifest import ROOT, dependency_paths


def hashes():
    return {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest()
            for p in dependency_paths() + ["data/rules.json", "tools/ai_reliability_soak.gd"]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--duration", type=float, default=900)
    parser.add_argument("--dt", type=float, default=1/30)
    parser.add_argument("--workers", type=int, choices=range(1, 9), default=4)
    parser.add_argument("--wall-timeout", type=float, default=600)
    parser.add_argument("--factions", default="kestrel,rivet,iron,sky")
    parser.add_argument("--faults", choices=("all", "none"), default="all")
    args = parser.parse_args()
    factions = args.factions.split(",")
    if len(set(factions)) != len(factions) or any(f not in ("kestrel", "rivet", "iron", "sky") for f in factions):
        parser.error("Expected unique supported factions")
    if args.duration < 600 or not .001 <= args.dt <= .1:
        parser.error("Expected duration >=600, dt .001..0.1")
    output = args.output_dir.resolve()
    if output.exists() and any(output.iterdir()):
        parser.error("Output directory must be new or empty")
    output.mkdir(parents=True, exist_ok=True)
    before = hashes()
    cases = [{"faction": f, "side": side, "fault": "none"} for f in factions for side in (0, 1)]
    if args.faults == "all":
        for f in factions:
            cases.append({"faction": f, "side": 0, "fault": "refinery_loss"})
            if f != "rivet": cases.append({"faction": f, "side": 0, "fault": "miner_loss"})
        if "iron" in factions: cases.append({"faction": "iron", "side": 0, "fault": "rail_break"})
    manifest = {"schema": "paper_front.ai_reliability_suite", "configuration": vars(args) | {"output_dir": str(output)},
                "source_sha256": before, "cases": cases,
                "exclusion": "Passive enemy extended-HP HQ and documented loss injection; excluded from balance win rates."}
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")

    def run(case):
        name = f"{case['faction']}__side{case['side']}__{case['fault']}"
        prefix = output / name
        command = [os.environ.get("PAPER_FRONT_GODOT", "godot"), "--headless", "--audio-driver", "Dummy", "--path", str(ROOT),
                   "--script", "res://tools/ai_reliability_soak.gd", "--", "--faction", case["faction"], "--side", str(case["side"]),
                   "--fault", case["fault"], "--duration", str(args.duration), "--dt", str(args.dt), "--output", str(prefix)]
        started = time.monotonic()
        row = dict(case, id=name, command=command)
        try:
            result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=args.wall_timeout)
            log = result.stdout + result.stderr
            row["exit_code"] = result.returncode
            row["runtime_errors"] = re.findall(r"^.*(?:SCRIPT ERROR:|ERROR:|Parse Error:).*$", log, re.M)
            report = json.loads(Path(str(prefix) + "_reliability.json").read_text())
            row.update({key: report[key] for key in ("checks_passed", "failures", "income", "duration", "max_no_movement_or_cargo_progress_seconds_by_miner")})
            row["fault_applied"] = report["fault"]
            row["checks_passed"] = row["checks_passed"] and result.returncode == 0 and not row["runtime_errors"]
            if case["fault"] != "none" and report["fault"].get("not_applicable"):
                row["checks_passed"] = False
                row["failures"].append("Requested recovery fault could not be applied")
        except (OSError, ValueError, subprocess.TimeoutExpired) as exc:
            row.update(checks_passed=False, failures=[str(exc)])
            log = str(exc)
        prefix.with_suffix(".log").write_text(log)
        row["wall_seconds"] = round(time.monotonic() - started, 3)
        return row

    rows = []
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        pending = [pool.submit(run, c) for c in cases]
        for future in as_completed(pending):
            row = future.result()
            rows.append(row)
            print(f"[{len(rows)}/{len(cases)}] {row['id']}: {'PASS' if row['checks_passed'] else 'FAIL'} income={row.get('income', 0):.0f}", flush=True)
    after = hashes()
    result = {"schema": "paper_front.ai_reliability_suite_results", "cases": sorted(rows, key=lambda r: r["id"]),
              "passed": sum(r["checks_passed"] for r in rows), "total": len(cases),
              "source_sha256_end": after, "source_unchanged": before == after}
    (output / "results.json").write_text(json.dumps(result, indent=2) + "\n")
    return 0 if result["passed"] == result["total"] and result["source_unchanged"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
