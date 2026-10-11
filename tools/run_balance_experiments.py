#!/usr/bin/env python3
"""Run paired, reproducible HQ-only AI matches and summarize real telemetry.

Uses only the Python standard library. Every match gets its own unmodified game
export. Duration limits remain unfinished, never victories awarded on points.
"""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import csv
from datetime import datetime, timezone
import hashlib
import itertools
import json
import math
from pathlib import Path
import re
import statistics
import subprocess
import sys
import time

from headless_export_manifest import dependency_paths

ROOT = Path(__file__).resolve().parents[1]
FACTIONS = ("kestrel", "rivet", "iron", "sky")
STYLES = ("balanced", "pressure", "armor")
EXPERIMENT_SOURCES = tuple(path for path in dependency_paths() if path.endswith(".gd"))
VALID_OUTCOMES = ("decisive", "draw", "unfinished")
SUMMARY_FIELDS = (
    "funds_earned", "funds_spent", "money_remaining", "units_produced",
    "buildings_built", "units_lost", "buildings_lost", "units_killed",
    "buildings_destroyed", "units_lost_value", "buildings_lost_value",
    "enemy_units_destroyed_value", "enemy_buildings_destroyed_value",
    "army_value", "building_value", "peak_army_value", "infantry_produced",
    "damage_dealt", "low_power_seconds_sampled", "zero_funds_seconds_sampled",
)


def write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def file_sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def plan_cases(factions: list[str], styles: list[str], suite: str, seed: int,
               matchups: list[tuple[str, str]] | None = None, controls: str = "all",
               style_pairing: str = "matched") -> list[dict]:
    pairs = [] if controls == "only" else (list(matchups) if matchups is not None else list(itertools.combinations(factions, 2)))
    if controls != "none": pairs += [(x, x) for x in factions]
    if suite == "smoke" and matchups is None:
        pairs = ([] if controls == "only" else [(factions[0], factions[1]), (factions[-2], factions[-1])])
        if controls != "none": pairs += [(factions[0], factions[0])]
        pairs = list(dict.fromkeys(pairs))
    cases = []
    style_pairs = [(style, style) for style in styles] if style_pairing == "matched" else list(itertools.product(styles, repeat=2))
    for style_a, style_b in style_pairs:
        for a, b in pairs:
            if a == b and style_a != style_b and styles.index(style_a) > styles.index(style_b):
                continue
            # Reversing identical factions with identical policies reproduces
            # exactly the same mirror; one control already exposes slot bias.
            for starts in (("default",) if a == b and style_a == style_b else ("default", "swap")):
                label = style_a if style_a == style_b else f"{style_a}_vs_{style_b}"
                cases.append({
                    "id": f"{a}_vs_{b}__{label}__{starts}",
                    "category": "mirror_control" if a == b else "cross_faction",
                    "requested_factions": [a, b], "styles": [style_a, style_b],
                    "starts": starts, "seed": seed,
                    "actual_factions": [b, a] if starts == "swap" else [a, b],
                })
    return cases


def style_label(styles: list[str]) -> str:
    return styles[0] if len(set(styles)) == 1 else "_vs_".join(styles)


def milestone_times(snapshot: dict, team: int) -> dict:
    times: dict[str, float] = {}
    unit_catalog = snapshot.get("metadata", {}).get("rules_snapshot", {}).get("units", {})
    building_catalog = snapshot.get("metadata", {}).get("rules_snapshot", {}).get("buildings", {})
    for event in snapshot.get("events", []):
        if int(event.get("team", -1)) != team:
            continue
        kind, spec, at = event.get("kind"), event.get("spec", ""), float(event["time"])
        if kind == "produce":
            role = unit_catalog.get(spec, {}).get("role", spec.split("_", 1)[-1])
            times.setdefault("first_unit", at)
            times.setdefault(f"first_{role}", at)
        elif kind == "deploy":
            role = building_catalog.get(spec, {}).get("role", spec.split("_", 1)[-1])
            times.setdefault(f"first_{role}_building", at)
        elif kind == "death":
            times.setdefault("first_loss", at)
    for sample in snapshot.get("history", []):
        row = next((r for r in sample.get("teams", []) if int(r.get("team", -1)) == team), {})
        if float(row.get("funds_earned", 0)) > 0:
            times.setdefault("first_income_sampled", float(sample["time"]))
        if float(row.get("damage_dealt", 0)) > 0:
            times.setdefault("first_damage_sampled", float(sample["time"]))
    return times


def planner_observations(snapshot: dict, row: dict) -> dict:
    team = int(row["team"])
    states = snapshot.get("headless", {}).get("ai_state", [])
    state = states[team] if team < len(states) else {}
    last_income = None
    prior_income = 0.0
    for sample in snapshot.get("history", []):
        own = next((r for r in sample.get("teams", []) if int(r.get("team", -1)) == team), {})
        income = float(own.get("funds_earned", 0))
        if income > prior_income:
            last_income = float(sample["time"])
        prior_income = income
    catalog = snapshot.get("metadata", {}).get("rules_snapshot", {}).get("units", {})
    combat_produced = sum(count for spec, count in row.get("units_produced_by_spec", {}).items()
                          if catalog.get(spec, {}).get("weapon"))
    return {"planner_version": state.get("planner_version"),
            "decisions": state.get("decisions"), "attack_waves": state.get("attack_waves"),
            "production_orders": state.get("production_orders"),
            "combat_units_produced": combat_produced,
            "last_income_sampled": last_income,
            "seconds_since_last_income_sampled": float(snapshot["duration"]) - last_income if last_income is not None else None,
            "combat_damage_observed": float(row.get("damage_dealt", 0)) > 0,
            **{key: state.get(key, 0) for key in (
                "miner_recovery_checks", "miner_recovery_orders", "miner_wait_seconds",
                "miner_wait_peak", "traffic_yield_orders", "rail_repair_orders",
                "rail_junction_upgrades", "miner_safety_retreats", "miner_safety_resumes",
                "attack_recovery_orders", "emergency_defenders")},
            "interpretation": "Observations for planner eligibility review; absent attacks/income can also follow enemy pressure and do not establish a balance cause."}


def validate_snapshot(snapshot: dict, case: dict) -> list[str]:
    issues = []
    rows = sorted(snapshot.get("teams", []), key=lambda x: int(x.get("team", -1)))
    if snapshot.get("schema") != "paper_front.match_statistics" or len(rows) != 2:
        return ["missing valid two-team match export"]
    if [r.get("faction") for r in rows] != case["actual_factions"]:
        issues.append("actual faction/team mapping does not match paired-start plan")
    if snapshot.get("map_mode") != "symmetric":
        issues.append("unexpected map")
    if not snapshot.get("history_complete") or not snapshot.get("telemetry_history_complete"):
        issues.append("incomplete telemetry history")
    headless = snapshot.get("headless", {})
    if not headless.get("ai_enabled"):
        issues.append("AI was not enabled")
    if headless.get("error"):
        issues.append(f"simulation error: {headless['error']}")
    slots = snapshot.get("metadata", {}).get("match_options", {}).get("slots", [])
    if len(slots) != 2 or any(slot.get("control") != "ai" for slot in slots):
        issues.append("both team slots must be controlled by AI")
    expected_styles = case["styles"][::-1] if case["starts"] == "swap" else case["styles"]
    if [slot.get("ai_style") for slot in slots] != expected_styles:
        issues.append("actual AI slot styles do not match experiment plan")
    initial = snapshot.get("metadata", {}).get("initial_teams", [])
    if len(initial) != 2:
        issues.append("missing initial HQ-only observations")
    else:
        for row in initial:
            if row.get("alive_units") != 0 or row.get("building_total") != 1:
                issues.append("initial forces were not HQ-only")
            if row.get("buildings_by_spec") != {f"{row.get('faction')}_hq": 1}:
                issues.append("unexpected starting infrastructure")
    if not snapshot.get("metadata", {}).get("rules_sha256"):
        issues.append("missing exported rules hash")
    stop = headless.get("stop_reason")
    if stop not in ("result", "duration_limit"):
        issues.append(f"unexpected stop_reason: {stop}")
    if stop == "duration_limit" and snapshot.get("result"):
        issues.append("duration limit must not invent a result")
    winners = snapshot.get("winner_teams", [])
    if stop == "duration_limit" and (winners or snapshot.get("winner_teams_known")):
        issues.append("unfinished match must not declare a winner")
    if stop == "result" and (not snapshot.get("result") or not snapshot.get("winner_teams_known")):
        issues.append("finished result is missing authoritative winner metadata")
    if stop == "result" and snapshot.get("result") in ("win", "lose") and winners != ([0] if snapshot["result"] == "win" else [1]):
        issues.append("winner metadata conflicts with authoritative result")
    return sorted(set(issues))


def summarize_snapshot(snapshot: dict, case: dict) -> dict:
    issues = validate_snapshot(snapshot, case)
    winner_teams = [int(x) for x in snapshot.get("winner_teams", [])] if not issues else []
    teams = []
    for row in snapshot.get("teams", []):
        team = int(row["team"])
        teams.append({"team": team, "faction": row["faction"],
                      "metrics": {key: row.get(key, 0) for key in SUMMARY_FIELDS},
                      "milestones_seconds": milestone_times(snapshot, team),
                      "produced_by_spec": row.get("units_produced_by_spec", {}),
                      "built_by_spec": row.get("buildings_built_by_spec", {}),
                      "lost_by_spec": row.get("units_lost_by_spec", {}),
                      "planner_observations": planner_observations(snapshot, row),
                      "won": team in winner_teams})
    stop = snapshot.get("headless", {}).get("stop_reason")
    outcome = "invalid" if issues else ("unfinished" if stop == "duration_limit" else ("draw" if snapshot.get("result") == "draw" else "decisive"))
    return {"outcome": outcome, "validation_issues": issues,
            "stop_reason": stop, "result": snapshot.get("result", ""),
            "winner_teams": winner_teams,
            "winner_factions": [row["faction"] for row in teams if row["won"]],
            "duration_game_seconds": snapshot.get("duration"),
            "rules_sha256_exported": snapshot.get("metadata", {}).get("rules_sha256"),
            "map_metadata": {key: value for key, value in snapshot.get("metadata", {}).items()
                             if key in ("map_mode", "map_seed", "map_width", "map_height", "map_starts", "symmetry", "symmetry_mode", "profile", "design_version")},
            "eligibility_observations": {
                "teams_without_damage": [row["team"] for row in teams if not row["planner_observations"]["combat_damage_observed"]],
                "teams_without_attack_waves": [row["team"] for row in teams if row["planner_observations"]["attack_waves"] == 0],
                "teams_without_combat_production": [row["team"] for row in teams if row["planner_observations"]["combat_units_produced"] == 0]},
            "teams": teams}


def execute_case(case: dict, manifest: dict, output: Path, timeout: float) -> dict:
    prefix = output / "matches" / case["id"]
    runner = manifest["configuration"]["runner"]
    command = [runner]
    if not runner.endswith(".sh"):
        command += ["--headless", "--audio-driver", "Dummy", "--"]
    config = manifest["configuration"]
    command += ["--map", "symmetric", "--seed", str(case["seed"]),
                "--factions", ",".join(case["requested_factions"]), "--ai", "both",
                "--difficulty", config["difficulty"], "--starts", case["starts"],
                "--ai-styles", ",".join(case["styles"]),
                "--duration", str(config["duration"]), "--dt", str(config["dt"]),
                "--rules", manifest["rules"]["frozen_path"], "--output", str(prefix)]
    record = {**case, "command": command, "report_json": str(prefix) + ".json"}
    began = time.monotonic()
    try:
        process = subprocess.run(command, cwd=ROOT, text=True, encoding="utf-8", errors="replace",
                                 capture_output=True, timeout=timeout, check=False)
        record["exit_code"] = process.returncode
        stdout, stderr = process.stdout, process.stderr
    except subprocess.TimeoutExpired as exc:
        # subprocess.run kills and reaps the direct runner. The shell launcher
        # uses exec, so there is no surviving game subprocess.
        record.update(outcome="wall_timeout", exit_code=None,
                      validation_issues=["process exceeded wall-clock timeout; no winner assigned"])
        stdout = exc.stdout or ""
        stderr = exc.stderr or ""
        if isinstance(stdout, bytes): stdout = stdout.decode("utf-8", "replace")
        if isinstance(stderr, bytes): stderr = stderr.decode("utf-8", "replace")
    except OSError as exc:
        record.update(outcome="process_error", exit_code=None, validation_issues=[str(exc)])
        stdout, stderr = "", str(exc)
    record["wall_seconds"] = round(time.monotonic() - began, 3)
    prefix.with_suffix(".stdout.log").write_text(stdout, encoding="utf-8")
    prefix.with_suffix(".stderr.log").write_text(stderr, encoding="utf-8")
    if "outcome" not in record:
        try:
            snapshot = json.loads(prefix.with_suffix(".json").read_text(encoding="utf-8"))
            record.update(summarize_snapshot(snapshot, case))
            expected_rules = json.loads(Path(manifest["rules"]["frozen_path"]).read_text(encoding="utf-8"))
            if snapshot.get("metadata", {}).get("rules_snapshot") != expected_rules:
                record["outcome"] = "invalid"
                record.setdefault("validation_issues", []).append("actual exported rules differ from frozen experiment rules")
        except (OSError, ValueError, KeyError, TypeError) as exc:
            record.update(outcome="invalid", validation_issues=[f"cannot analyze report: {exc}"])
        if record["exit_code"] != 0:
            record["outcome"] = "process_error"
            record.setdefault("validation_issues", []).append(f"runner exit code {record['exit_code']}")
        runtime_errors = [line for line in (stdout + "\n" + stderr).splitlines()
                          if re.search(r"(?:SCRIPT ERROR:|\bERROR:|Parse Error:|Error loading script)", line)]
        if runtime_errors:
            record["outcome"] = "invalid"
            record["runtime_errors"] = runtime_errors[:30]
            record.setdefault("validation_issues", []).append("Godot reported runtime or script errors; partial export excluded")
    if record.get("outcome") not in VALID_OUTCOMES:
        record["winner_teams"] = []
        record["winner_factions"] = []
        for row in record.get("teams", []): row["won"] = False
    write_json(prefix.with_suffix(".run.json"), record)
    return record


def aggregate(records: list[dict]) -> dict:
    groups = {}
    for record in records:
        a, b = record["requested_factions"]
        label = style_label(record["styles"])
        key = f"{a}_vs_{b}__{label}"
        group = groups.setdefault(key, {"factions": [a, b], "style": label, "styles": record["styles"],
                                       "category": record["category"], "matches": 0,
                                       "decisive": 0, "draw": 0, "unfinished": 0,
                                       "wall_timeout": 0, "invalid": 0, "process_error": 0,
                                       "failures": 0, "wins": {a: 0, b: 0}, "losses": {a: 0, b: 0},
                                       "team_slot_wins": {"0": 0, "1": 0}, "team_rows": []})
        group["matches"] += 1
        outcome = record.get("outcome", "invalid")
        if outcome in ("decisive", "draw", "unfinished"):
            group[outcome] += 1
        else:
            group["failures"] += 1
            if outcome in ("wall_timeout", "invalid", "process_error"): group[outcome] += 1
        if outcome == "decisive":
            for faction in record.get("winner_factions", []): group["wins"][faction] += 1
            for team in record.get("winner_teams", []): group["team_slot_wins"][str(team)] += 1
            for row in record.get("teams", []):
                if not row["won"]: group["losses"][row["faction"]] += 1
        if outcome in ("decisive", "draw", "unfinished"):
            for row in record.get("teams", []):
                group["team_rows"].append({"faction": row["faction"], **row["metrics"],
                                          **row["milestones_seconds"],
                                          "duration_game_seconds": record["duration_game_seconds"],
                                          "wall_seconds": record["wall_seconds"],
                                          **{f"ai_{key}": value for key, value in row.get("planner_observations", {}).items()
                                             if isinstance(value, (float, int)) and not isinstance(value, bool)}})
    for group in groups.values():
        rows = group.pop("team_rows")
        group["mean_by_faction"] = {}
        for faction in dict.fromkeys(group["factions"]):
            own = [row for row in rows if row["faction"] == faction]
            fields = sorted(set().union(*(row.keys() for row in own))) if own else []
            group["mean_by_faction"][faction] = {
                key: statistics.fmean(float(row[key]) for row in own if key in row)
                for key in fields if key != "faction"}
        group["mirror_note"] = "Identical faction and policy: inspect team_slot_wins; faction wins/losses have no matchup interpretation." if group["category"] == "mirror_control" else ""
    return {"groups": groups,
            "counts": {outcome: sum(r.get("outcome") == outcome for r in records)
                       for outcome in ("decisive", "draw", "unfinished", "wall_timeout", "invalid", "process_error")},
            "exported_rules_hashes": sorted({r["rules_sha256_exported"] for r in records if r.get("rules_sha256_exported")}),
            "eligibility_observation_counts": {
                "matches_without_damage_on_both_teams": sum(len(r.get("eligibility_observations", {}).get("teams_without_damage", [])) == 2 for r in records),
                "matches_with_any_team_without_attack_waves": sum(bool(r.get("eligibility_observations", {}).get("teams_without_attack_waves")) for r in records),
                "matches_with_any_team_without_combat_production": sum(bool(r.get("eligibility_observations", {}).get("teams_without_combat_production")) for r in records)}}


def evaluate_win_rate_targets(records: list[dict], manifest: dict, target: float = .35,
                              min_completion: float = 1.0, min_decisive: int = 6,
                              integrity_error: str | None = None) -> dict:
    """Assess a finite schedule; unfinished observations are never draws/losses.

    W/(W+L) is a conditional rate over authoritative decisive results. Bounds
    W/N .. (W+unresolved)/N use every scheduled cross-faction case. They are
    assignment bounds, not statistical confidence intervals or probabilities.
    """
    config = manifest.get("configuration", {})
    scheduled = manifest.get("cases", [])
    factions = config.get("factions") or list(dict.fromkeys(
        faction for case in scheduled for faction in case["requested_factions"]))
    by_id = {}
    for record in records: by_id.setdefault(record["id"], []).append(record)
    scheduled_ids = {case["id"] for case in scheduled}
    extra_ids = sorted(set(by_id) - scheduled_ids)
    counters = ("scheduled", "wins", "losses", "draws", "unfinished", "failed", "missing")
    overall = {faction: dict.fromkeys(counters, 0) for faction in factions}
    matchups = {}
    mirror_count = 0
    for case in scheduled:
        a, b = case["requested_factions"]
        if a == b:
            mirror_count += 1
            continue
        pair = sorted((a, b), key=lambda faction: FACTIONS.index(faction))
        key = "_vs_".join(pair)
        group = matchups.setdefault(key, {"factions": pair, "by_faction": {
            faction: dict.fromkeys(counters, 0) for faction in pair}})
        found = by_id.get(case["id"], [])
        record = found[0] if len(found) == 1 else None
        outcome = "missing" if not found else (record.get("outcome") if record else "failed")
        if record and any(record.get(field) != case.get(field) for field in ("requested_factions", "styles", "starts", "seed")):
            outcome = "failed"
        winner = None
        if outcome == "decisive":
            winners = record.get("winner_factions", [])
            if len(winners) != 1 or winners[0] not in pair:
                outcome = "failed"
            else:
                winner = winners[0]
        for faction in pair:
            for row in (overall[faction], group["by_faction"][faction]):
                row["scheduled"] += 1
                if outcome == "decisive": row["wins" if winner == faction else "losses"] += 1
                elif outcome in ("draw", "unfinished", "missing"): row[{"draw": "draws"}.get(outcome, outcome)] += 1
                else: row["failed"] += 1

    def assess(row: dict) -> dict:
        n = row["scheduled"]
        decisive = row["wins"] + row["losses"]
        finished = decisive + row["draws"]
        unresolved = row["unfinished"] + row["failed"] + row["missing"]
        rate = row["wins"] / decisive if decisive else None
        completion = finished / n if n else None
        lower = row["wins"] / n if n else None
        upper = (row["wins"] + unresolved) / n if n else None
        reasons = []
        if not n: reasons.append("not_scheduled")
        if not decisive: reasons.append("no_decisive_results")
        if decisive < min_decisive: reasons.append("too_few_decisive_results")
        if completion is None or completion + 1e-12 < min_completion: reasons.append("completion_below_threshold")
        if rate is not None and rate + 1e-12 < target: reasons.append("win_rate_below_target")
        return {**row, "decisive": decisive, "finished": finished, "unresolved": unresolved,
                "decisive_win_rate": rate, "completion_rate": completion,
                "minimum_wins_at_observed_decisive_count": math.ceil(target * decisive - 1e-12) if decisive else None,
                "wins_per_all_scheduled": lower,
                "all_scheduled_win_rate_lower_bound": lower,
                "all_scheduled_win_rate_upper_bound": upper,
                "all_scheduled_lower_bound_meets_target": lower is not None and lower + 1e-12 >= target,
                "target_met": not reasons, "target_reasons": reasons}

    overall = {faction: assess(row) for faction, row in overall.items()}
    for group in matchups.values():
        group["by_faction"] = {faction: assess(row) for faction, row in group["by_faction"].items()}
        group["both_factions_target_met"] = all(row["target_met"] for row in group["by_faction"].values())
    expected_pairs = {"_vs_".join(pair) for pair in itertools.combinations(sorted(factions, key=FACTIONS.index), 2)}
    missing_pairs = sorted(expected_pairs - set(matchups))
    # A truncated or targeted subset may satisfy its own observed rows, but it
    # cannot establish a target for the full selected-faction round robin.
    styles = config.get("styles") or list(dict.fromkeys(style for case in scheduled for style in case["styles"]))
    expected_cases = plan_cases(factions, styles, "full", int(config.get("seed", 1)), controls="none",
                               style_pairing=config.get("style_pairing", "matched")) if len(factions) >= 2 and styles else []
    def condition_key(case: dict) -> tuple:
        actual_factions = case["requested_factions"][::-1] if case["starts"] == "swap" else case["requested_factions"]
        actual_styles = case["styles"][::-1] if case["starts"] == "swap" else case["styles"]
        return tuple(zip(actual_factions, actual_styles)), case.get("seed", config.get("seed", 1))
    scheduled_conditions = {condition_key(case) for case in scheduled if case["requested_factions"][0] != case["requested_factions"][1]}
    missing_conditions = sorted(case["id"] for case in expected_cases if condition_key(case) not in scheduled_conditions)
    coverage_ok = bool(expected_cases) and not missing_pairs and not missing_conditions
    duplicate_ids = sorted(case_id for case_id, values in by_id.items() if len(values) > 1)
    integrity_ok = not integrity_error and not duplicate_ids and not extra_ids
    overall_met = bool(overall) and all(row["target_met"] for row in overall.values())
    matchup_met = bool(matchups) and all(group["both_factions_target_met"] for group in matchups.values())
    return {"schema": "paper_front.win_rate_targets", "schema_version": 1,
            "target_win_rate": target, "minimum_completion_rate": min_completion,
            "minimum_decisive_games_per_row": min_decisive,
            "rate_definition": "authoritative decisive wins / (wins + losses); genuine draws are reported separately",
            "bounds_definition": "wins / scheduled .. (wins + unfinished + failed + missing) / scheduled; independent assignment bounds, not confidence intervals",
            "scope": "selected-faction cross-faction round robin across the configured policy schedule; mirror controls excluded",
            "overall": overall, "matchups": matchups,
            "excluded_mirror_controls": mirror_count,
            "coverage": {"full_round_robin": coverage_ok, "missing_matchups": missing_pairs,
                         "missing_condition_ids": missing_conditions,
                         "omitted_planned_cases": len(manifest.get("omitted_case_ids", []))},
            "integrity": {"ok": integrity_ok, "experiment_error": integrity_error,
                          "duplicate_result_ids": duplicate_ids, "unplanned_result_ids": extra_ids},
            "observed_schedule_overall_target_met": overall_met,
            "observed_schedule_all_matchups_target_met": matchup_met,
            "overall_target_met": overall_met and coverage_ok and integrity_ok,
            "all_matchups_target_met": matchup_met and coverage_ok and integrity_ok,
            "preferred_target_met": overall_met and matchup_met and coverage_ok and integrity_ok,
            "limitations": ["Deterministic policy/side conditions are not independent random trials; no population-win-rate or significance claim.",
                            "A high W/(W+L) among the finished subset does not establish success unless completion and minimum-decisive thresholds also pass.",
                            "Real draws do not earn half a win; inspect their count and W/all even when the decisive rate passes.",
                            "Each faction's upper bound is marginal; opponents cannot simultaneously win the same unresolved match."]}


def render_win_rate_report(output: Path, assessment: dict) -> None:
    def pct(value: float | None) -> str:
        return "未定义" if value is None else f"{value:.1%}"
    target = pct(assessment["target_win_rate"])
    lines = ["# 有限实验计划的胜率目标", "",
             f"主目标：每阵营真实终局 W/(W+L) ≥ {target}。完成率门槛 {pct(assessment['minimum_completion_rate'])}，每行至少 {assessment['minimum_decisive_games_per_row']} 个真实分胜负结果。", "",
             f"总体目标验证：{'通过' if assessment['overall_target_met'] else '未通过验证'}；逐对阵双方目标：{'通过' if assessment['all_matchups_target_met'] else '未通过验证'}。", "",
             "镜像对照不计入阵营胜率。真实平局单列；未结束、运行失败、缺失结果都不计为平局，也不计入 W/(W+L)。", "",
             "W/all 与上下界包含全部已安排的跨阵营条件；上界把所有未知结果都赋给该阵营，属于赋值边界，并非置信区间。不同阵营不能同时取各自的上界。", "",
             "| 范围 | 阵营 | W / L / 真平局 | 未完 / 失败 / 缺失 | W/(W+L) | 完成率 | W/all | all 上下界 | 行目标 |", "|---|---|---|---|---:|---:|---:|---|---|"]
    csv_rows = []
    def append(scope: str, faction: str, row: dict) -> None:
        status = "通过" if row["target_met"] else ", ".join(row["target_reasons"])
        lines.append(f"| {scope} | {faction} | {row['wins']} / {row['losses']} / {row['draws']} | {row['unfinished']} / {row['failed']} / {row['missing']} | {pct(row['decisive_win_rate'])} | {pct(row['completion_rate'])} | {pct(row['wins_per_all_scheduled'])} | {pct(row['all_scheduled_win_rate_lower_bound'])}–{pct(row['all_scheduled_win_rate_upper_bound'])} | {status} |")
        csv_rows.append({"scope": scope, "faction": faction, **{key: value for key, value in row.items() if key != "target_reasons"}, "target_reasons": ";".join(row["target_reasons"])})
    for faction, row in assessment["overall"].items(): append("总体", faction, row)
    for key, group in assessment["matchups"].items():
        for faction, row in group["by_faction"].items(): append(key, faction, row)
    if not assessment["coverage"]["full_round_robin"]:
        lines += ["", "实验安排未覆盖所选阵营与策略的完整循环赛，不能据子集宣布总体目标通过。缺少对阵：" + (", ".join(assessment["coverage"]["missing_matchups"]) or "无，但有策略/出生条件未安排") + "。"]
    if not assessment["integrity"]["ok"]:
        lines += ["", "实验完整性未通过：" + json.dumps(assessment["integrity"], ensure_ascii=False) + "。"]
    lines += ["", "这些是固定地图、策略和出生条件的确定性结果，不是独立随机样本，也不表示总体胜率的统计显著性。"]
    (output / "win_rates.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    with (output / "win_rates.csv").open("w", encoding="utf-8", newline="") as stream:
        if csv_rows:
            writer = csv.DictWriter(stream, fieldnames=list(csv_rows[0]))
            writer.writeheader()
            writer.writerows(csv_rows)


def paired_comparison(records: list[dict], baseline_dir: Path, manifest: dict) -> dict:
    previous = json.loads((baseline_dir / "results.json").read_text(encoding="utf-8"))
    previous_manifest = json.loads((baseline_dir / "manifest.json").read_text(encoding="utf-8"))
    conditions = ("difficulty", "duration", "dt")
    differences = [name for name in conditions if manifest["configuration"][name] != previous_manifest["configuration"][name]]
    comparison_sources = {name for value in (manifest, previous_manifest) for name in value.get("source_sha256", {}) if name.startswith("scripts/") and name.endswith(".gd")}
    for name in sorted(comparison_sources):
        if manifest["source_sha256"].get(name) != previous_manifest["source_sha256"].get(name):
            differences.append("source:" + name)
    if not previous.get("complete"):
        differences.append("baseline_incomplete")
    if previous.get("integrity_error"):
        differences.append("baseline_integrity_error")
    old = {record["id"]: record for record in previous["matches"]}
    pairs = []
    for current in records:
        before = old.get(current["id"])
        if not before or any(current.get(key) != before.get(key) for key in ("seed", "starts", "styles", "requested_factions")):
            continue
        before_teams = {row["team"]: row for row in before.get("teams", [])}
        deltas = []
        both_valid = current.get("outcome") in VALID_OUTCOMES and before.get("outcome") in VALID_OUTCOMES
        for row in current.get("teams", []) if both_valid else []:
            prior = before_teams.get(row["team"])
            if prior and prior["faction"] == row["faction"]:
                deltas.append({"team": row["team"], "faction": row["faction"],
                               "metrics_delta_candidate_minus_baseline": {
                                   key: float(row["metrics"].get(key, 0)) - float(prior["metrics"].get(key, 0)) for key in SUMMARY_FIELDS},
                               "milestone_delta_seconds": {
                                   key: float(value) - float(prior["milestones_seconds"][key])
                                   for key, value in row["milestones_seconds"].items() if key in prior["milestones_seconds"]}})
        pairs.append({"id": current["id"], "baseline_outcome": before.get("outcome"),
                      "candidate_outcome": current.get("outcome"),
                      "baseline_winners": before.get("winner_factions", []) if before.get("outcome") == "decisive" else [],
                      "candidate_winners": current.get("winner_factions", []) if current.get("outcome") == "decisive" else [],
                      "baseline_duration": before.get("duration_game_seconds"),
                      "candidate_duration": current.get("duration_game_seconds"), "team_deltas": deltas})
    return {"baseline_directory": str(baseline_dir), "condition_differences": differences,
            "directly_comparable": not differences, "paired_cases": pairs,
            "baseline_rules_sha256": previous_manifest["rules"]["file_sha256"],
            "candidate_rules_sha256": manifest["rules"]["file_sha256"],
            "limitations": "Deterministic paired scenarios are regression evidence, not independent random trials or a population win-rate estimate."}


def render_report(output: Path, manifest: dict, results: dict) -> None:
    lines = ["# AI 1v1 平衡实验", "",
             f"规则文件 SHA256：`{manifest['rules']['file_sha256']}`。每局原始 JSON/CSV 位于 `matches/`。", "",
             "正常对局从双方 HQ 与标准初始资金开始，全部生产、建造和命令通过游戏逻辑执行。", "",
             "地图固定、种子固定；交换阵营及其策略的出生槽位控制地理与处理顺序影响。三种策略是不同实验条件。确定性重复不增加独立样本量；本报告不计算统计显著性。", "",
             "`unfinished` 是游戏时间上限，`wall_timeout` 是进程时间上限，两者均不判胜。以下经济均值包含未结束对局，因此需结合时长与逐局曲线解释。", "",
             "| 对阵 | 策略 | 完成胜负 | 游戏上限未结束 | 进程超时 | 失败 | 阵营胜 / 负 | 槽位 0 / 1 胜场 |", "|---|---|---:|---:|---:|---:|---|---|"]
    if results.get("integrity_error"):
        lines[2:2] = ["实验完整性检查失败：" + results["integrity_error"] + "。此运行不用于直接数值因果比较。", ""]
    if results.get("analysis_tool_changed_during_run"):
        lines[2:2] = ["运行期间分析工具源码发生变化，游戏逻辑校验单独保留；工具起止身份见 JSON，必要时重新汇总原始导出。", ""]
    for group in results["aggregate"]["groups"].values():
        wins = ", ".join(f"{key}: {value}/{group['losses'][key]}" for key, value in group["wins"].items())
        slots = group["team_slot_wins"]
        lines.append(f"| {' / '.join(group['factions'])} | {group['style']} | {group['decisive']}（平局 {group['draw']}） | {group['unfinished']} | {group['wall_timeout']} | {group['failures']} | {wins} | {slots['0']} / {slots['1']} |")
    lines += ["", "## 经济、生产与损失", "",
              "| 对阵 / 策略 | 阵营 | 收入均值 | 单位生产 | 单位损失价值 | 峰值军队价值 | 首收入秒 | 首坦克秒 |", "|---|---|---:|---:|---:|---:|---:|---:|"]
    def fmt(value: object) -> str:
        return "—" if value is None else f"{float(value):.1f}"
    for key, group in results["aggregate"]["groups"].items():
        for faction, row in group["mean_by_faction"].items():
            lines.append(f"| {key} | {faction} | " + " | ".join(fmt(row.get(field)) for field in ("funds_earned", "units_produced", "units_lost_value", "peak_army_value", "first_income_sampled", "first_tank")) + " |")
    lines += ["", "## AI 执行与实验适用性", "",
              "无进攻或收入中断需要检查 AI，也可能由敌方压制导致，以下观测本身不建立数值因果关系。数值实验前应结合镜像对照确认采集、出兵与交战正常。", "",
              "| 对阵 / 策略 | 阵营 | 决策次数 | 进攻波次 | 战斗单位生产 | 距末次收入秒 | 首伤害秒 |", "|---|---|---:|---:|---:|---:|---:|"]
    for key, group in results["aggregate"]["groups"].items():
        for faction, row in group["mean_by_faction"].items():
            lines.append(f"| {key} | {faction} | " + " | ".join(fmt(row.get(field)) for field in ("ai_decisions", "ai_attack_waves", "ai_combat_units_produced", "ai_seconds_since_last_income_sampled", "first_damage_sampled")) + " |")
    observed = results["aggregate"]["eligibility_observation_counts"]
    lines += ["", f"双方都未观测到伤害：{observed['matches_without_damage_on_both_teams']} 局；至少一方无进攻波次：{observed['matches_with_any_team_without_attack_waves']} 局；至少一方没有生产战斗单位：{observed['matches_with_any_team_without_combat_production']} 局。"]
    comparison = results.get("comparison")
    if comparison:
        lines += ["", "## 基线与候选规则", "",
                  f"配对条件一致：{'是' if comparison['directly_comparable'] else '否'}；共匹配 {len(comparison['paired_cases'])} 个实验条件。", "",
                  "| 条件 | 基线 | 候选 | 基线胜方 | 候选胜方 |", "|---|---|---|---|---|"]
        for pair in comparison["paired_cases"]:
            lines.append(f"| {pair['id']} | {pair['baseline_outcome']} | {pair['candidate_outcome']} | {', '.join(pair['baseline_winners']) or '—'} | {', '.join(pair['candidate_winners']) or '—'} |")
        lines += ["", "候选减去基线的经济、生产与损失差值（完整配对差值见 JSON；时长不同会影响这些累计值）：", "",
                  "| 条件 | 阵营 / 槽位 | 收入差 | 生产单位差 | 损失价值差 | 首坦克秒差 |", "|---|---|---:|---:|---:|---:|"]
        for pair in comparison["paired_cases"]:
            for row in pair["team_deltas"]:
                delta = row["metrics_delta_candidate_minus_baseline"]
                lines.append(f"| {pair['id']} | {row['faction']} / {row['team']} | {fmt(delta['funds_earned'])} | {fmt(delta['units_produced'])} | {fmt(delta['units_lost_value'])} | {fmt(row['milestone_delta_seconds'].get('first_tank'))} |")
        if comparison["condition_differences"]:
            lines += ["", "不可直接比较的配置：" + ", ".join(comparison["condition_differences"]) + "。"]
    failures = [r for r in results["matches"] if r.get("outcome") in ("invalid", "wall_timeout", "process_error")]
    if failures:
        lines += ["", "## 运行错误", ""]
        lines += [f"- {row['id']}: {'; '.join(row.get('validation_issues', []))}" for row in failures]
    (output / "report.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    fields = ["match", "category", "style", "starts", "outcome", "duration_game_seconds", "wall_seconds", "team", "faction", "won", *SUMMARY_FIELDS]
    with (output / "team_summary.csv").open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        for record in results["matches"]:
            for team in record.get("teams", []):
                writer.writerow({"match": record["id"], "category": record["category"],
                                 "style": style_label(record["styles"]), "starts": record["starts"],
                                 "outcome": record["outcome"], "duration_game_seconds": record.get("duration_game_seconds"),
                                 "wall_seconds": record.get("wall_seconds"), "team": team["team"],
                                 "faction": team["faction"], "won": team["won"], **team["metrics"]})


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", "--outputdir", required=True, type=Path)
    parser.add_argument("--rules", type=Path, default=ROOT / "data/rules.json")
    parser.add_argument("--runner", type=Path, default=ROOT / "tools/run_headless.sh")
    parser.add_argument("--suite", choices=("full", "smoke"), default="full")
    parser.add_argument("--factions", default=",".join(FACTIONS))
    parser.add_argument("--styles", default=",".join(STYLES))
    parser.add_argument("--style-pairing", choices=("matched", "cross"), default="matched",
                        help="matched uses identical policies; cross pairs every selected policy across factions.")
    parser.add_argument("--difficulty", choices=("easy", "normal", "hard"), default="normal")
    parser.add_argument("--duration", type=float, default=600)
    parser.add_argument("--dt", type=float, default=.05)
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--workers", type=int, choices=range(1, 9), default=4)
    parser.add_argument("--wall-timeout", type=float, default=300)
    parser.add_argument("--max-matches", type=int, help="Bound a diagnostic subset; manifest records the omitted cases.")
    parser.add_argument("--matchups", help="Cross-faction subset, e.g. kestrel:rivet,iron:sky (mirrors controlled separately).")
    parser.add_argument("--controls", choices=("all", "none", "only"), default="all")
    parser.add_argument("--baseline", type=Path, help="Compare matching cases to a prior experiment directory.")
    parser.add_argument("--analyze-only", action="store_true", help="Rebuild aggregate/report from existing per-match run files.")
    parser.add_argument("--target-win-rate", type=float, default=.35,
                        help="Minimum authoritative decisive W/(W+L) for each faction; default 0.35.")
    parser.add_argument("--min-completion-rate", type=float, default=1.0,
                        help="Required true-terminal fraction of all scheduled cases; default 1.0.")
    parser.add_argument("--min-decisive-games", type=int, default=6,
                        help="Minimum real wins+losses per overall/matchup row before target verification.")
    parser.add_argument("--win-rate-report", action="store_true",
                        help="Also write win_rates.md and win_rates.csv; JSON always contains target assessment.")
    args = parser.parse_args(argv)
    if not 0 <= args.target_win_rate <= 1 or not 0 < args.min_completion_rate <= 1 or args.min_decisive_games < 1:
        parser.error("invalid target win rate, completion threshold or minimum decisive games")
    output = args.output_dir.resolve()
    persisted = {}
    if args.analyze_only:
        manifest = json.loads((output / "manifest.json").read_text(encoding="utf-8"))
        records = [json.loads(path.read_text(encoding="utf-8")) for path in sorted((output / "matches").glob("*.run.json"))]
        if (output / "results.json").exists():
            persisted = json.loads((output / "results.json").read_text(encoding="utf-8"))
    else:
        factions, styles = args.factions.split(","), args.styles.split(",")
        if len(factions) < 2 or len(set(factions)) != len(factions) or any(x not in FACTIONS for x in factions):
            parser.error("--factions requires two to four different supported faction IDs")
        if not styles or len(styles) != len(set(styles)) or any(x not in STYLES for x in styles):
            parser.error("--styles must contain different supported planner styles")
        if not 0 < args.duration <= 86400 or not .001 <= args.dt <= .1 or args.wall_timeout <= 0:
            parser.error("invalid duration, dt or wall-timeout")
        if args.max_matches is not None and args.max_matches < 1:
            parser.error("--max-matches must be positive")
        if (output / "manifest.json").exists():
            parser.error("experiment directory already exists; use a new directory or --analyze-only")
        rules_bytes = args.rules.resolve().read_bytes()
        json.loads(rules_bytes)  # Reject malformed input before starting workers.
        (output / "matches").mkdir(parents=True, exist_ok=True)
        frozen_rules = output / "rules.json"
        frozen_rules.write_bytes(rules_bytes)
        matchups = None
        if args.matchups:
            matchups = []
            for matchup in args.matchups.split(","):
                pair = matchup.split(":")
                if len(pair) != 2 or pair[0] == pair[1] or any(x not in factions for x in pair):
                    parser.error("--matchups requires selected different factions separated by ':'")
                as_tuple = (pair[0], pair[1])
                if as_tuple in matchups or (pair[1], pair[0]) in matchups:
                    parser.error("--matchups must not repeat a pair")
                matchups.append(as_tuple)
        planned = plan_cases(factions, styles, args.suite, args.seed, matchups, args.controls, args.style_pairing)
        selected = planned[:args.max_matches] if args.max_matches else planned
        provenance = {}
        for relative in (*EXPERIMENT_SOURCES, "tools/run_balance_experiments.py"):
            if (ROOT / relative).exists(): provenance[relative] = file_sha(ROOT / relative)
        manifest = {"schema": "paper_front.balance_experiment", "schema_version": 1,
                    "created_utc": datetime.now(timezone.utc).isoformat(),
                    "configuration": {"suite": args.suite, "factions": factions, "styles": styles,
                                      "difficulty": args.difficulty, "duration": args.duration,
                                      "dt": args.dt, "seed": args.seed, "workers": args.workers,
                                      "wall_timeout": args.wall_timeout, "runner": str(args.runner.resolve()),
                                      "matchups": matchups, "controls": args.controls},
                    "rules": {"source_path": str(args.rules.resolve()), "frozen_path": str(frozen_rules),
                              "file_sha256": hashlib.sha256(rules_bytes).hexdigest()},
                    "source_sha256": provenance, "runner_sha256": file_sha(args.runner.resolve()),
                    "source_provenance_note": "Workspace source hashes describe source-runner inputs; an executable runner's embedded source requires its build provenance.",
                    "planned_count": len(planned),
                    "executed_count": len(selected), "omitted_case_ids": [x["id"] for x in planned[len(selected):]],
                    "decisions": {"initial_forces": "normal HQ-only game setup; no debug spawning or seeded infrastructure",
                                  "map": "fixed symmetric layout; seed changes alone are not treated as independent geography samples",
                                  "paired_starts": "swap reverses faction and style slot order on the fixed map",
                                  "styles": "same-policy matched conditions" if args.style_pairing == "matched" else "all ordered cross-faction policy pairs; same-faction controls deduplicate equivalent policy/side permutations",
                                  "outcome": "only authoritative game result counts as victory; time limits remain unfinished",
                                  "replication": "no deterministic repeat padding; no significance or population win-rate claims"},
                    "cases": selected}
        manifest["configuration"]["style_pairing"] = args.style_pairing
        manifest["analysis_configuration"] = {"target_win_rate": args.target_win_rate,
                                               "minimum_completion_rate": args.min_completion_rate,
                                               "minimum_decisive_games": args.min_decisive_games}
        write_json(output / "manifest.json", manifest)
        records = []
        print(f"Running {len(selected)} matches ({args.workers} workers), reports: {output}", flush=True)
        with ThreadPoolExecutor(max_workers=args.workers) as pool:
            futures = {pool.submit(execute_case, case, manifest, output, args.wall_timeout): case for case in selected}
            for future in as_completed(futures):
                record = future.result()
                records.append(record)
                print(f"[{len(records)}/{len(selected)}] {record['id']}: {record['outcome']} ({record['wall_seconds']:.1f}s wall)", flush=True)
                # Retain recoverable progress even if the caller interrupts later.
                write_json(output / "progress.json", {"completed": len(records), "matches": records})
        order = {case["id"]: i for i, case in enumerate(selected)}
        records.sort(key=lambda x: order[x["id"]])
    results = {"schema": "paper_front.balance_experiment_results", "schema_version": 1,
               "matches": records, "aggregate": aggregate(records)}
    expected = manifest["executed_count"]
    results["complete"] = len(records) == expected
    results["source_sha256_end"] = (persisted.get("source_sha256_end", {}) if args.analyze_only else
                                    {name: file_sha(ROOT / name) for name in manifest["source_sha256"] if (ROOT / name).exists()})
    if persisted.get("integrity_error"):
        results["integrity_error"] = persisted["integrity_error"]
    game_sources = {name for name in manifest["source_sha256"] if name.startswith("scripts/") and name.endswith(".gd")}
    if not args.analyze_only and any(results["source_sha256_end"].get(name) != manifest["source_sha256"].get(name) for name in game_sources):
        results["integrity_error"] = "source files changed while experiment was running"
    if not args.analyze_only and results["source_sha256_end"].get("tools/run_balance_experiments.py") != manifest["source_sha256"].get("tools/run_balance_experiments.py"):
        results["analysis_tool_changed_during_run"] = True
    if persisted.get("analysis_tool_changed_during_run"):
        results["analysis_tool_changed_during_run"] = True
    if len(results["aggregate"]["exported_rules_hashes"]) > 1:
        results["integrity_error"] = results.get("integrity_error", "") + "; match exports used different rules snapshots"
    if args.baseline:
        results["comparison"] = paired_comparison(records, args.baseline.resolve(), manifest)
        if results.get("integrity_error"):
            results["comparison"]["condition_differences"].append("candidate_integrity_error")
            results["comparison"]["directly_comparable"] = False
    results["win_rate_targets"] = evaluate_win_rate_targets(records, manifest, args.target_win_rate,
                                                           args.min_completion_rate, args.min_decisive_games,
                                                           results.get("integrity_error"))
    write_json(output / "results.json", results)
    render_report(output, manifest, results)
    if args.win_rate_report:
        render_win_rate_report(output, results["win_rate_targets"])
    failures = sum(results["aggregate"]["counts"][key] for key in ("wall_timeout", "invalid", "process_error"))
    print(json.dumps({"complete": results["complete"], "counts": results["aggregate"]["counts"],
                      "overall_win_rate_target_met": results["win_rate_targets"]["overall_target_met"],
                      "all_matchups_target_met": results["win_rate_targets"]["all_matchups_target_met"],
                      "report": str(output / "report.md")}), flush=True)
    return 1 if failures or not results["complete"] or results.get("integrity_error") else 0


if __name__ == "__main__":
    sys.exit(main())
