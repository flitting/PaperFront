#!/usr/bin/env python3
"""Focused contracts for outcome safety and paired experiment accounting."""
import copy
from contextlib import redirect_stdout
import io
import json
from pathlib import Path
import tempfile
import unittest

from run_balance_experiments import EXPERIMENT_SOURCES, aggregate, evaluate_win_rate_targets, main, paired_comparison, plan_cases, render_win_rate_report, summarize_snapshot


def snapshot(factions=("rivet", "kestrel"), winner=None):
    initial = [{"team": team, "faction": faction, "alive_units": 0,
                "building_total": 1, "buildings_by_spec": {faction + "_hq": 1}}
               for team, faction in enumerate(factions)]
    finished = winner is not None
    return {"schema": "paper_front.match_statistics", "teams": copy.deepcopy(initial),
            "map_mode": "symmetric", "history_complete": True,
            "telemetry_history_complete": True, "duration": 600,
            "result": ("win" if winner == 0 else "lose") if finished else "",
            "winner_teams_known": finished, "winner_teams": [winner] if finished else [],
            "metadata": {"initial_teams": initial, "rules_sha256": "semantic-hash",
                         "match_options": {"slots": [{"control": "ai", "ai_style": "balanced"}, {"control": "ai", "ai_style": "balanced"}]}},
            "headless": {"ai_enabled": True, "error": "", "stop_reason": "result" if finished else "duration_limit"},
            "events": [], "history": []}


class ExperimentContracts(unittest.TestCase):
    def test_logic_hash_closure_covers_gameplay_helpers_and_excludes_tools(self):
        self.assertTrue({"scripts/refinery_docking.gd", "scripts/rail_network.gd", "scripts/rules_loader.gd", "scripts/armor_combat.gd"}.issubset(EXPERIMENT_SOURCES))
        self.assertTrue(all(path.startswith("scripts/") and path.endswith(".gd") for path in EXPERIMENT_SOURCES))
    def test_full_pairs_and_mirrors_without_duplicate_mirrors(self):
        cases = plan_cases(["kestrel", "rivet", "iron", "sky"], ["balanced", "pressure", "armor"], "full", 1)
        self.assertEqual(len(cases), 48)
        self.assertEqual(sum(case["category"] == "mirror_control" for case in cases), 12)
        for case in cases:
            self.assertEqual(case["actual_factions"], case["requested_factions"][::-1] if case["starts"] == "swap" else case["requested_factions"])

    def test_filter_controls(self):
        cases = plan_cases(["kestrel", "rivet", "iron", "sky"], ["balanced"], "full", 1, [("iron", "sky")], "none")
        self.assertEqual(len(cases), 2)
        self.assertEqual({tuple(case["requested_factions"]) for case in cases}, {("iron", "sky")})

    def test_cross_style_plan_covers_108_cross_and_36_distinct_mirrors(self):
        factions = ["kestrel", "rivet", "iron", "sky"]
        styles = ["balanced", "pressure", "armor"]
        cases = plan_cases(factions, styles, "full", 1, style_pairing="cross")
        cross = [case for case in cases if case["category"] == "cross_faction"]
        mirror = [case for case in cases if case["category"] == "mirror_control"]
        self.assertEqual(len(cross), 108)
        self.assertEqual(len(mirror), 36)
        self.assertEqual(len({case["id"] for case in cases}), 144)
        for faction in factions:
            own = [case for case in mirror if case["requested_factions"][0] == faction]
            actual_policies = [tuple(case["styles"][::-1] if case["starts"] == "swap" else case["styles"]) for case in own]
            self.assertEqual(set(actual_policies), {(a, b) for a in styles for b in styles})
            self.assertEqual(len(actual_policies), 9)

    def test_matched_style_case_ids_remain_compatible(self):
        cases = plan_cases(["kestrel", "rivet"], ["balanced"], "full", 1)
        self.assertEqual([case["id"] for case in cases], ["kestrel_vs_rivet__balanced__default", "kestrel_vs_rivet__balanced__swap", "kestrel_vs_kestrel__balanced__default", "rivet_vs_rivet__balanced__default"])

    def test_matchup_selection_is_not_mutated_or_ignored_by_smoke(self):
        pairs = [("kestrel", "iron")]
        cases = plan_cases(["kestrel", "rivet", "iron", "sky"], ["balanced"], "smoke", 1, pairs, "all")
        self.assertEqual(pairs, [("kestrel", "iron")])
        cross = [case for case in cases if case["category"] == "cross_faction"]
        self.assertEqual(len(cross), 2)
        self.assertEqual(cross[0]["requested_factions"], ["kestrel", "iron"])

    def test_unfinished_is_never_awarded_a_winner(self):
        case = plan_cases(["kestrel", "rivet"], ["balanced"], "full", 1, controls="none")[1]
        result = summarize_snapshot(snapshot(), case)
        self.assertEqual(result["outcome"], "unfinished")
        self.assertEqual(result["winner_factions"], [])

    def test_swap_win_credited_to_actual_faction(self):
        case = plan_cases(["kestrel", "rivet"], ["balanced"], "full", 1, controls="none")[1]
        result = summarize_snapshot(snapshot(winner=0), case)
        self.assertEqual(result["winner_factions"], ["rivet"])
        self.assertEqual(result["outcome"], "decisive")
        totals = aggregate([{**case, **result, "wall_seconds": 2}])["groups"]["kestrel_vs_rivet__balanced"]
        self.assertEqual(totals["wins"], {"kestrel": 0, "rivet": 1})
        self.assertEqual(totals["losses"], {"kestrel": 1, "rivet": 0})

    def test_seeded_infrastructure_and_wrong_mapping_rejected(self):
        case = plan_cases(["kestrel", "rivet"], ["balanced"], "full", 1, controls="none")[0]
        data = snapshot()
        data["metadata"]["initial_teams"][0]["alive_units"] = 1
        result = summarize_snapshot(data, case)
        self.assertEqual(result["outcome"], "invalid")
        self.assertGreaterEqual(len(result["validation_issues"]), 2)

    def test_duration_limit_cannot_hide_fake_victory(self):
        case = plan_cases(["kestrel", "rivet"], ["balanced"], "full", 1, controls="none")[1]
        data = snapshot(winner=0)
        data["headless"]["stop_reason"] = "duration_limit"
        self.assertEqual(summarize_snapshot(data, case)["outcome"], "invalid")
        self.assertEqual(summarize_snapshot(data, case)["winner_factions"], [])

    def test_wrong_actual_policy_is_rejected(self):
        case = plan_cases(["kestrel", "rivet"], ["balanced"], "full", 1, controls="none")[1]
        data = snapshot(winner=0)
        data["metadata"]["match_options"]["slots"][0]["ai_style"] = "armor"
        result = summarize_snapshot(data, case)
        self.assertEqual(result["outcome"], "invalid")
        self.assertEqual(result["winner_factions"], [])

    def test_baseline_requires_unchanged_planner(self):
        manifest = {"configuration": {"difficulty": "normal", "duration": 600, "dt": .05},
                    "source_sha256": {"scripts/ai_controller.gd": "new-ai"},
                    "rules": {"file_sha256": "candidate-rules"}}
        previous = copy.deepcopy(manifest)
        previous["source_sha256"]["scripts/ai_controller.gd"] = "old-ai"
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            (path / "manifest.json").write_text(json.dumps(previous))
            (path / "results.json").write_text(json.dumps({"matches": []}))
            comparison = paired_comparison([], path, manifest)
        self.assertFalse(comparison["directly_comparable"])
        self.assertIn("source:scripts/ai_controller.gd", comparison["condition_differences"])

    def test_reaggregation_preserves_original_integrity_failure(self):
        manifest = {"executed_count": 0, "source_sha256": {}, "rules": {"file_sha256": "rules"}}
        original = {"integrity_error": "source changed during run", "source_sha256_end": {"ai": "changed"}}
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            (path / "matches").mkdir()
            (path / "manifest.json").write_text(json.dumps(manifest))
            (path / "results.json").write_text(json.dumps(original))
            with redirect_stdout(io.StringIO()):
                exit_code = main(["--analyze-only", "--output-dir", directory])
            refreshed = json.loads((path / "results.json").read_text())
        self.assertEqual(exit_code, 1)
        self.assertEqual(refreshed["integrity_error"], original["integrity_error"])
        self.assertEqual(refreshed["source_sha256_end"], original["source_sha256_end"])


class WinRateTargetContracts(unittest.TestCase):
    def fixture(self, styles=("balanced",), factions=("kestrel", "rivet"), controls="none"):
        cases = plan_cases(list(factions), list(styles), "full", 1, controls=controls)
        manifest = {"cases": cases, "configuration": {"factions": list(factions), "styles": list(styles), "seed": 1}}
        return cases, manifest

    def record(self, case, outcome, winner=None):
        return {**case, "outcome": outcome, "winner_factions": [winner] if winner else []}

    def test_entirely_unfinished_has_no_decisive_rate_or_success(self):
        cases, manifest = self.fixture()
        records = [self.record(case, "unfinished") for case in cases]
        result = evaluate_win_rate_targets(records, manifest, min_decisive=1)
        row = result["overall"]["kestrel"]
        self.assertIsNone(row["decisive_win_rate"])
        self.assertEqual((row["wins"], row["losses"], row["draws"]), (0, 0, 0))
        self.assertEqual((row["all_scheduled_win_rate_lower_bound"], row["all_scheduled_win_rate_upper_bound"]), (0, 1))
        self.assertFalse(result["overall_target_met"])

    def test_high_finished_subset_rate_does_not_hide_unfinished_cases(self):
        cases, manifest = self.fixture(styles=("balanced", "pressure", "armor"))
        records = [self.record(case, "decisive", "kestrel") if index == 0 else self.record(case, "unfinished") for index, case in enumerate(cases)]
        result = evaluate_win_rate_targets(records, manifest, min_decisive=1)
        row = result["overall"]["kestrel"]
        self.assertEqual(row["decisive_win_rate"], 1)
        self.assertAlmostEqual(row["completion_rate"], 1 / 6)
        self.assertAlmostEqual(row["wins_per_all_scheduled"], 1 / 6)
        self.assertIn("completion_below_threshold", row["target_reasons"])
        self.assertFalse(result["overall_target_met"])

    def test_failures_and_missing_results_are_unknown_separately(self):
        cases, manifest = self.fixture(styles=("balanced", "pressure"))
        records = [self.record(cases[0], "decisive", "kestrel"), self.record(cases[1], "decisive", "rivet"), self.record(cases[2], "invalid")]
        row = evaluate_win_rate_targets(records, manifest, min_decisive=1)["overall"]["kestrel"]
        self.assertEqual((row["wins"], row["losses"], row["failed"], row["missing"]), (1, 1, 1, 1))
        self.assertEqual(row["decisive_win_rate"], .5)
        self.assertEqual((row["all_scheduled_win_rate_lower_bound"], row["all_scheduled_win_rate_upper_bound"]), (.25, .75))
        self.assertEqual(row["draws"], 0)
        self.assertFalse(row["target_met"])

    def test_true_draws_complete_but_do_not_award_wins(self):
        cases, manifest = self.fixture(styles=("balanced", "pressure"))
        records = [self.record(cases[0], "decisive", "kestrel"), self.record(cases[1], "decisive", "rivet"), *[self.record(case, "draw") for case in cases[2:]]]
        result = evaluate_win_rate_targets(records, manifest, min_decisive=2)
        row = result["overall"]["kestrel"]
        self.assertEqual((row["wins"], row["losses"], row["draws"]), (1, 1, 2))
        self.assertEqual(row["decisive_win_rate"], .5)
        self.assertEqual(row["completion_rate"], 1)
        self.assertEqual(row["wins_per_all_scheduled"], .25)
        self.assertFalse(row["all_scheduled_lower_bound_meets_target"])
        self.assertTrue(result["overall_target_met"])

    def test_complete_balanced_round_robin_meets_overall_and_matchup_goals(self):
        cases, manifest = self.fixture(styles=("balanced", "pressure", "armor"), factions=("kestrel", "rivet", "iron", "sky"))
        records = [self.record(case, "decisive", case["actual_factions"][0]) for case in cases]
        result = evaluate_win_rate_targets(records, manifest)
        self.assertTrue(result["preferred_target_met"])
        for row in result["overall"].values(): self.assertEqual(row["decisive_win_rate"], .5)
        for group in result["matchups"].values():
            for row in group["by_faction"].values(): self.assertEqual(row["decisive"], 6)

    def test_mirrors_do_not_inflate_faction_win_rate_or_count(self):
        cases, manifest = self.fixture(controls="all")
        records = [self.record(case, "decisive", case["actual_factions"][0]) for case in cases]
        result = evaluate_win_rate_targets(records, manifest, min_decisive=2)
        self.assertEqual(result["excluded_mirror_controls"], 2)
        self.assertEqual(result["overall"]["kestrel"]["scheduled"], 2)
        self.assertEqual(result["overall"]["kestrel"]["wins"], 1)
        self.assertTrue(result["overall_target_met"])

    def test_targeted_or_truncated_schedule_cannot_claim_full_round_robin_goal(self):
        cases, manifest = self.fixture(styles=("balanced",), factions=("kestrel", "rivet", "iron", "sky"))
        manifest["cases"] = cases[:2]
        records = [self.record(case, "decisive", case["actual_factions"][0]) for case in cases[:2]]
        result = evaluate_win_rate_targets(records, manifest, min_decisive=1)
        self.assertFalse(result["coverage"]["full_round_robin"])
        self.assertFalse(result["overall_target_met"])
        self.assertEqual(result["overall"]["iron"]["scheduled"], 0)

    def test_all_draws_and_integrity_failure_cannot_pass(self):
        cases, manifest = self.fixture()
        records = [self.record(case, "draw") for case in cases]
        result = evaluate_win_rate_targets(records, manifest, min_decisive=1)
        self.assertEqual(result["overall"]["kestrel"]["completion_rate"], 1)
        self.assertIsNone(result["overall"]["kestrel"]["decisive_win_rate"])
        self.assertFalse(result["overall_target_met"])
        decisive = [self.record(case, "decisive", case["actual_factions"][0]) for case in cases]
        self.assertFalse(evaluate_win_rate_targets(decisive, manifest, min_decisive=1, integrity_error="AI changed")["overall_target_met"])

    def test_optional_report_renders_defined_and_undefined_rates(self):
        cases, manifest = self.fixture()
        assessment = evaluate_win_rate_targets([self.record(cases[0], "unfinished")], manifest)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            render_win_rate_report(path, assessment)
            self.assertIn("未定义", (path / "win_rates.md").read_text())
            self.assertIn("decisive_win_rate", (path / "win_rates.csv").read_text())


if __name__ == "__main__":
    unittest.main()
