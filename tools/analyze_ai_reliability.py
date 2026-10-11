#!/usr/bin/env python3
"""Audit actual per-miner cash deliveries without changing source reports.

Movement, cargo oscillation and another miner's income do not establish a
delivery. Miner lifetimes come from produce/death events; cash credits come
from the reliability fixture's explicit delivery observations.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
from typing import Any

EPS = 1e-6
RAIL_POSITION_TOLERANCE = .001


def number(value: Any, label: str, errors: list[str]) -> float | None:
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        errors.append(f"{label}: expected a finite number")
        return None
    return float(value)


def entity_id(value: Any, label: str, errors: list[str]) -> int | None:
    parsed = number(value, label, errors)
    if parsed is None:
        return None
    if parsed <= 0 or not parsed.is_integer():
        errors.append(f"{label}: expected a positive integer entity id")
        return None
    return int(parsed)


def position(value: Any) -> tuple[float, float] | None:
    if not isinstance(value, list) or len(value) != 2:
        return None
    if any(isinstance(v, bool) or not isinstance(v, (int, float)) or not math.isfinite(v) for v in value):
        return None
    return float(value[0]), float(value[1])


def is_miner(spec: str, catalog: dict) -> bool:
    return spec.endswith("_harvester") or catalog.get(spec, {}).get("art") == "harvester"


def audit_case(report: dict, telemetry: dict, case: dict, max_gap: float = 180) -> dict:
    errors: list[str] = []
    violations: list[str] = []
    side = int(case.get("side", report.get("options", {}).get("side", 0)))
    faction = str(case.get("faction", report.get("options", {}).get("faction", "")))
    fault_kind = str(case.get("fault", report.get("options", {}).get("fault", "none")))
    duration = number(report.get("duration"), "report duration", errors)
    telemetry_duration = number(telemetry.get("duration"), "telemetry duration", errors)
    duration = 0.0 if duration is None else duration
    if telemetry_duration is not None and abs(duration - telemetry_duration) > .001:
        errors.append("reliability and telemetry durations differ")
    if telemetry.get("schema") != "paper_front.match_statistics":
        errors.append("unexpected telemetry schema")
    if not telemetry.get("history_complete") or not telemetry.get("telemetry_history_complete"):
        errors.append("telemetry history is incomplete")
    options = report.get("options", {})
    if str(options.get("faction", faction)) != faction or int(options.get("side", side)) != side:
        errors.append("report faction/side differs from scheduled case")
    if str(options.get("fault", fault_kind)) != fault_kind:
        errors.append("report fault differs from scheduled case")
    events = telemetry.get("events", [])
    if not isinstance(events, list):
        errors.append("telemetry events must be an array")
        events = []
    units = telemetry.get("metadata", {}).get("rules_snapshot", {}).get("units", {})
    buildings = telemetry.get("metadata", {}).get("rules_snapshot", {}).get("buildings", {})
    births: dict[int, dict] = {}
    deaths: dict[int, float] = {}
    for event in events:
        if not isinstance(event, dict) or event.get("team") != side:
            continue
        kind = event.get("kind")
        spec = str(event.get("spec", ""))
        if kind == "produce" and is_miner(spec, units):
            ident = entity_id(event.get("id"), "miner produce id", errors)
            at = number(event.get("time"), "miner produce time", errors)
            if ident is None or at is None:
                continue
            if ident in births:
                errors.append(f"miner {ident}: duplicate produce event")
                continue
            if at < -EPS or at > duration + EPS:
                errors.append(f"miner {ident}: birth outside observation window")
                continue
            births[ident] = {"id": ident, "spec": spec, "born_at": at}
        elif kind == "death":
            ident = entity_id(event.get("id"), "death id", errors)
            at = number(event.get("time"), "death time", errors)
            if ident is not None and at is not None:
                deaths[ident] = min(at, deaths.get(ident, math.inf))
    if not births and faction != "rivet":
        errors.append("no own miner produce events in a mobile-mining faction's observation")
    credits: dict[int, list[dict]] = {ident: [] for ident in births}
    seen: set[tuple[int, float, float]] = set()
    deliveries = report.get("deliveries", [])
    if not isinstance(deliveries, list):
        errors.append("report deliveries must be an array")
        deliveries = []
    for delivery in deliveries:
        if not isinstance(delivery, dict):
            errors.append("delivery must be an object")
            continue
        ident = entity_id(delivery.get("id"), "delivery id", errors)
        at = number(delivery.get("time"), "delivery time", errors)
        amount = number(delivery.get("amount"), "delivery cash amount", errors)
        if ident is None or at is None or amount is None:
            continue
        if amount <= 0:
            errors.append(f"miner {ident}: delivery has no positive cash credit")
            continue
        if ident not in births:
            errors.append(f"delivery for miner {ident} has no own produce event")
            continue
        end = min(duration, deaths.get(ident, duration))
        if at < births[ident]["born_at"] - EPS or at > end + EPS:
            errors.append(f"miner {ident}: cash delivery lies outside its lifetime")
            continue
        key = (ident, at, amount)
        if key in seen:
            errors.append(f"miner {ident}: duplicate cash-delivery observation")
            continue
        seen.add(key)
        credits[ident].append({"id": ident, "time": at, "amount": amount})
    miners: list[dict] = []
    for ident, birth in sorted(births.items()):
        start = birth["born_at"]
        died = deaths.get(ident)
        if died is not None and (died < start - EPS or died > duration + EPS):
            errors.append(f"miner {ident}: death outside its recorded lifetime")
        end = max(start, min(duration, died if died is not None else duration))
        paid = sorted(credits[ident], key=lambda item: item["time"])
        times = [item["time"] for item in paid]
        boundaries = [start] + times + [end]
        intervals = [max(0.0, b - a) for a, b in zip(boundaries, boundaries[1:])]
        gap = max(intervals, default=0.0)
        passed = gap <= max_gap + EPS
        status = "passed"
        if not passed:
            status = "overdue_cash_delivery"
            violations.append(f"miner {ident}: no actual delivery for {gap:.3f}s (limit {max_gap:g}s)")
        elif not paid:
            status = "died_before_first_delivery_deadline" if died is not None else "new_miner_grace"
        elif died is not None:
            status = "passed_lifetime_ended_by_death"
        miners.append({**birth, "died_at": died, "observation_ends_at": end,
                       "alive_at_end": died is None, "delivery_count": len(paid),
                       "cash_delivered": sum(item["amount"] for item in paid),
                       "first_delivery_at": times[0] if times else None,
                       "first_delivery_wait_seconds": times[0] - start if times else None,
                       "delivery_intervals_seconds": [b - a for a, b in zip(times, times[1:])],
                       "last_delivery_at": times[-1] if times else None,
                       "last_delivery_to_lifetime_end_seconds": end - times[-1] if times else None,
                       "never_delivered_observation_seconds": end - start if not paid else None,
                       "max_no_delivery_seconds": gap, "passed": passed, "status": status})

    fault = report.get("fault", {})
    fault_audit: dict = {"kind": fault_kind, "scope": "none", "passed": True}
    fault_error_start = len(errors)
    if fault_kind != "none":
        fault_audit["scope"] = "single_entity_loss_tolerance"
        if not isinstance(fault, dict) or fault.get("not_applicable") or not fault.get("id"):
            errors.append("requested fault was not applied to a recorded entity")
            fault = {}
        if fault:
            ident = entity_id(fault.get("id"), "fault id", errors)
            fault_at = number(fault.get("time"), "fault time", errors)
            fault_audit.update(entity_id=ident, at=fault_at, position=fault.get("pos"), spec=fault.get("spec"))
            if ident is not None and ident not in deaths:
                errors.append("injected entity loss has no corresponding own death event")
            elif ident is not None and fault_at is not None and abs(deaths[ident] - fault_at) > .101:
                errors.append("injected entity death time does not match the fault time")
        if fault_kind == "rail_break":
            fault_audit["scope"] = "recorded_track_cell_reconstruction_and_subsequent_cash_delivery"
            target = position(fault.get("pos"))
            at = fault.get("time")
            replacements = []
            if target is None or not isinstance(at, (int, float)) or not math.isfinite(at):
                errors.append("rail fault has no finite location/time")
            else:
                for event in events:
                    if not isinstance(event, dict) or event.get("team") != side or event.get("kind") not in ("build", "deploy"):
                        continue
                    spec = str(event.get("spec", ""))
                    if buildings.get(spec, {}).get("role") not in ("rail", "rail_junction") and not spec.endswith(("_rail", "_rail_junction")):
                        continue
                    point = position(event.get("position", event.get("pos")))
                    when = event.get("time")
                    if point is None or not isinstance(when, (int, float)) or not math.isfinite(when):
                        continue
                    if when < at - EPS or when > duration + EPS or event.get("id") == fault.get("id"):
                        continue
                    if math.dist(point, target) <= RAIL_POSITION_TOLERANCE:
                        replacement_id = entity_id(event.get("id"), "rail reconstruction id", errors)
                        if replacement_id is not None:
                            replacements.append({"time": when, "kind": event["kind"], "id": replacement_id, "spec": spec, "position": list(point)})
            replacements.sort(key=lambda row: (row["time"], row["kind"]))
            deployed = [row for row in replacements if row["kind"] == "deploy"]
            rebuilt_at = (deployed or replacements)[0]["time"] if replacements else None
            subsequent = [credit for items in credits.values() for credit in items
                          if rebuilt_at is not None and credit["time"] > rebuilt_at + EPS]
            subsequent.sort(key=lambda row: row["time"])
            fault_audit.update(replacement_events=replacements, rebuilt_at=rebuilt_at,
                               first_delivery_after_rebuild=subsequent[0] if subsequent else None,
                               causal_scope="Position reconstruction plus later cash credit; delivery observations do not record route usage.")
            if not replacements:
                violations.append("injected rail position was never rebuilt after the fault")
            elif not subsequent:
                violations.append("no actual miner cash delivery after rail reconstruction")
            fault_audit["passed"] = bool(replacements and subsequent)
        else:
            fault_audit["interpretation"] = "Loss of one entity while other economy infrastructure may survive; does not prove reconstruction of the final income chain."
        if len(errors) > fault_error_start:
            fault_audit["passed"] = False
    upstream_passed = report.get("checks_passed") is True and case.get("checks_passed", True) is True
    upstream_failures = [] if upstream_passed else list(dict.fromkeys(
        report.get("failures", []) + case.get("failures", []) + case.get("runtime_errors", [])))
    if not upstream_passed and not upstream_failures:
        upstream_failures.append("original fixture/process checks did not pass")
    errors = list(dict.fromkeys(errors))
    return {"id": case.get("id", f"{faction}__side{side}__{fault_kind}"),
            "faction": faction, "side": side, "duration": duration,
            "upstream_checks_passed": upstream_passed,
            "upstream_failures": upstream_failures,
            "delivery_checks_passed": not errors and not violations,
            "checks_passed": upstream_passed and not errors and not violations,
            "errors": errors, "violations": violations, "miners": miners,
            "miner_delivery_audit_applicable": bool(births), "fault_audit": fault_audit,
            "max_no_delivery_seconds": max((row["max_no_delivery_seconds"] for row in miners), default=0),
            "cash_delivery_count": sum(row["delivery_count"] for row in miners)}


def read_json(path: Path) -> dict:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"{path}: expected JSON object")
    return value


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def case_id(case: dict) -> str:
    return case.get("id", f"{case['faction']}__side{case['side']}__{case['fault']}")


def analyze_batch(batch: Path, max_gap: float = 180) -> dict:
    manifest_path, results_path = batch / "manifest.json", batch / "results.json"
    manifest, results = read_json(manifest_path), read_json(results_path)
    originals = results.get("cases", [])
    if not isinstance(originals, list) or any(not isinstance(row, dict) for row in originals):
        raise ValueError("results.cases must be an array of objects")
    rows = {case_id(row): row for row in originals}
    errors = []
    if len(rows) != len(originals):
        errors.append("duplicate batch result case ids")
    planned = manifest.get("cases", originals)
    if not isinstance(planned, list) or any(not isinstance(row, dict) for row in planned):
        raise ValueError("manifest.cases must be an array of objects")
    source_before, source_end = manifest.get("source_sha256"), results.get("source_sha256_end")
    identity_valid = results.get("source_unchanged") is True and isinstance(source_before, dict) and bool(source_before) and source_before == source_end
    if not identity_valid:
        errors.append("original batch does not verify unchanged source identity")
    audited = []
    for scheduled in planned:
        ident = case_id(scheduled)
        row = rows.get(ident)
        if row is None:
            audited.append({**scheduled, "id": ident, "checks_passed": False, "errors": ["scheduled case has no result"], "violations": [], "miners": []})
            continue
        report_path = batch / f"{ident}_reliability.json"
        telemetry_path = batch / f"{ident}.json"
        try:
            report = read_json(report_path)
            if not telemetry_path.exists():
                telemetry_path = Path(report.get("export", {}).get("paths", {}).get("json", ""))
            telemetry = read_json(telemetry_path)
            audit = audit_case(report, telemetry, row, max_gap)
            audit["input_files"] = {"reliability": {"path": str(report_path), "sha256": sha(report_path)},
                                    "telemetry": {"path": str(telemetry_path), "sha256": sha(telemetry_path)}}
        except (OSError, ValueError, TypeError, KeyError) as exc:
            audit = {**row, "id": ident, "checks_passed": False, "errors": [f"Cannot audit case: {exc}"], "violations": [], "miners": []}
        audited.append(audit)
    unplanned = sorted(set(rows) - {case_id(case) for case in planned})
    if unplanned:
        errors.append("unplanned case results: " + ", ".join(unplanned))
    passed = sum(row["checks_passed"] for row in audited)
    return {"schema": "paper_front.ai_delivery_audit", "schema_version": 1,
            "audit_tool_sha256": sha(Path(__file__)),
            "batch_directory": str(batch), "max_no_delivery_seconds": max_gap,
            "source_identity": {"declared_unchanged": results.get("source_unchanged"),
                                "verified": identity_valid, "source_sha256": source_before,
                                "source_sha256_end": source_end},
            "input_files": {"manifest": {"path": str(manifest_path), "sha256": sha(manifest_path)},
                            "results": {"path": str(results_path), "sha256": sha(results_path)}},
            "errors": errors, "cases": audited, "passed": passed, "total": len(audited),
            "checks_passed": not errors and passed == len(audited) and bool(audited),
            "method": ["Produce/death events define each miner's observed lifetime; a dead miner is not aged to the end of the run.",
                       "Only positive cash-credit deliveries count. The first wait, each inter-delivery gap and the live tail must all remain within the stated limit.",
                       "A newly produced miner with less than one full deadline of observation is reported as grace, not a failure.",
                       "Rail-break recovery requires a new build/deploy event at the injected location and a later actual miner cash delivery. This is temporal evidence, not a full route trace.",
                       "Miner/refinery loss cases test single-entity loss tolerance while other income paths may survive.",
                       "Rivet uses drills and has no miner-delivery timeline; its original economy checks are retained, without claiming a per-drill cash audit.",
                       "Original reports and their source-identity outcome are preserved; this independent audit cannot turn an upstream failure into a pass."]}


def render_markdown(audit: dict) -> str:
    lines = ["# AI 矿车实际交付审计", "", f"每车最大无现金交付间隔：{audit['max_no_delivery_seconds']:g} 游戏秒。",
             f"源码身份验证：{'通过' if audit['source_identity']['verified'] else '未通过'}。条件通过：{audit['passed']}/{audit['total']}。", "",
             "以 produce/death 事件界定每辆矿车的生存区间，检查首次交付、相邻交付及末次交付至死亡/终点的间隔。移动、振荡及其他矿车收入不能替代本车交付。新矿车和提前死亡车辆只按实际存活窗口检查。", "",
             "矿厂/矿车故障为单体损失容忍；其他经济链可能仍在工作。断轨检查指定坐标的重建事件和其后的真实交付，现有数据不提供矿车完整路线，不能据此证明交付必然经过该轨道。", "",
             "| 条件 | 结果 | 矿车数 | 最大无交付秒数 | 交付次数 |", "|---|---|---:|---:|---:|"]
    for row in audit["cases"]:
        lines.append(f"| {row['id']} | {'通过' if row['checks_passed'] else '失败'} | {len(row['miners'])} | {row.get('max_no_delivery_seconds', 0):.2f} | {row.get('cash_delivery_count', 0)} |")
    failures = [(row["id"], message) for row in audit["cases"] for message in row.get("errors", []) + row.get("violations", []) + row.get("upstream_failures", [])]
    if audit["errors"] or failures:
        lines += ["", "## 待处理问题", ""]
        lines += [f"- {message}" for message in audit["errors"]]
        lines += [f"- {ident}: {message}" for ident, message in failures]
    lines += ["", "重锤使用钻机，没有矿车交付时间线；该阵营保留上游经济检查结果，没有逐钻机现金审计。", "", "全部矿车的出生、死亡、首末交付时间和每段交付间隔保留在 delivery_audit.json。原始可靠性与统计文件没有改写。", ""]
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--batch-dir", required=True, type=Path)
    parser.add_argument("--output-dir", type=Path)
    parser.add_argument("--max-no-delivery", type=float, default=180)
    args = parser.parse_args(argv)
    if not math.isfinite(args.max_no_delivery) or args.max_no_delivery <= 0:
        parser.error("--max-no-delivery must be finite and positive")
    batch = args.batch_dir.resolve()
    try:
        audit = analyze_batch(batch, args.max_no_delivery)
    except (OSError, ValueError, TypeError, KeyError) as exc:
        print(f"Delivery audit could not read the completed batch: {exc}")
        return 2
    output = (args.output_dir or batch).resolve()
    output.mkdir(parents=True, exist_ok=True)
    (output / "delivery_audit.json").write_text(json.dumps(audit, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (output / "delivery_audit.md").write_text(render_markdown(audit), encoding="utf-8")
    print(f"DELIVERY_AUDIT {audit['passed']}/{audit['total']} source_verified={audit['source_identity']['verified']} output={output}")
    return 0 if audit["checks_passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
