#!/usr/bin/env python3
"""Cash-delivery and lifecycle contracts for the independent soak auditor."""
from contextlib import redirect_stdout
import io
import json
from pathlib import Path
import tempfile
import unittest

from analyze_ai_reliability import audit_case, main


def fixture(births=((1, 0),), deliveries=None, deaths=(), duration=600, fault="none"):
    deliveries = deliveries if deliveries is not None else [(1, t) for t in (100, 200, 300, 400, 500, 600)]
    case = {"id": f"iron__side0__{fault}", "faction": "iron", "side": 0, "fault": fault, "checks_passed": True}
    report = {"checks_passed": True, "duration": duration,
              "options": {"faction": "iron", "side": 0, "fault": fault}, "fault": {},
              "deliveries": [{"id": ident, "time": at, "amount": 500} for ident, at in deliveries]}
    telemetry = {"schema": "paper_front.match_statistics", "duration": duration,
                 "history_complete": True, "telemetry_history_complete": True,
                 "metadata": {"rules_snapshot": {"units": {"iron_harvester": {"art": "harvester"}},
                                                 "buildings": {"iron_rail": {"role": "rail"}}}},
                 "events": [{"kind": "produce", "id": ident, "time": at, "team": 0, "spec": "iron_harvester"} for ident, at in births]
                           + [{"kind": "death", "id": ident, "time": at, "team": 0, "spec": "iron_harvester"} for ident, at in deaths]}
    return case, report, telemetry


def rail_fixture():
    case, report, telemetry = fixture(fault="rail_break", deliveries=[(1, t) for t in (100, 200, 350, 450, 550, 600)])
    report["fault"] = {"id": 10, "time": 300, "spec": "iron_rail", "pos": [5.5, 5.5]}
    telemetry["events"].append({"kind": "death", "id": 10, "time": 300, "team": 0, "spec": "iron_rail"})
    return case, report, telemetry


class DeliveryAuditContracts(unittest.TestCase):
    def test_other_miners_income_cannot_hide_a_miner_that_never_delivers(self):
        case, report, telemetry = fixture(births=((1, 0), (2, 0)), deliveries=[(2, t) for t in (100, 200, 300, 400, 500, 600)])
        audit = audit_case(report, telemetry, case)
        self.assertFalse(audit["delivery_checks_passed"])
        self.assertEqual(audit["miners"][0]["max_no_delivery_seconds"], 600)
        self.assertTrue(audit["miners"][1]["passed"])

    def test_new_miner_gets_only_its_observed_lifetime_grace(self):
        case, report, telemetry = fixture(births=((1, 0), (2, 550)))
        audit = audit_case(report, telemetry, case)
        self.assertTrue(audit["checks_passed"])
        self.assertEqual(audit["miners"][1]["status"], "new_miner_grace")
        self.assertEqual(audit["miners"][1]["max_no_delivery_seconds"], 50)

    def test_death_ends_the_delivery_window_instead_of_aging_to_run_end(self):
        case, report, telemetry = fixture(deliveries=[(1, 80)], deaths=((1, 160),))
        audit = audit_case(report, telemetry, case)
        self.assertTrue(audit["checks_passed"])
        self.assertEqual(audit["miners"][0]["max_no_delivery_seconds"], 80)
        self.assertEqual(audit["miners"][0]["observation_ends_at"], 160)

    def test_dying_does_not_erase_a_prior_overdue_delivery(self):
        case, report, telemetry = fixture(deliveries=[], deaths=((1, 300),))
        audit = audit_case(report, telemetry, case)
        self.assertFalse(audit["checks_passed"])
        self.assertEqual(audit["miners"][0]["max_no_delivery_seconds"], 300)

    def test_actual_delivery_gaps_and_live_tail_both_count(self):
        case, report, telemetry = fixture(deliveries=[(1, 100), (1, 300), (1, 500)], duration=600)
        audit = audit_case(report, telemetry, case)
        self.assertFalse(audit["checks_passed"])
        self.assertEqual(audit["miners"][0]["delivery_intervals_seconds"], [200, 200])
        self.assertEqual(audit["miners"][0]["last_delivery_to_lifetime_end_seconds"], 100)
        report["deliveries"] = [{"id": 1, "time": t, "amount": 500} for t in (100, 200)]
        self.assertEqual(audit_case(report, telemetry, case)["miners"][0]["max_no_delivery_seconds"], 400)

    def test_rail_needs_new_construction_at_the_injected_location(self):
        case, report, telemetry = rail_fixture()
        telemetry["events"] += [
            {"kind": "deploy", "id": 11, "time": 200, "team": 0, "spec": "iron_rail", "position": [5.5, 5.5]},
            {"kind": "deploy", "id": 12, "time": 320, "team": 0, "spec": "iron_rail", "position": [5.5, 7.5]},
        ]
        self.assertFalse(audit_case(report, telemetry, case)["checks_passed"])
        telemetry["events"].append({"kind": "deploy", "id": 13, "time": 321, "team": 0, "spec": "iron_rail", "position": [5.5, 5.5]})
        audit = audit_case(report, telemetry, case)
        self.assertTrue(audit["checks_passed"])
        self.assertEqual(audit["fault_audit"]["first_delivery_after_rebuild"]["time"], 350)

    def test_rebuilt_rail_without_subsequent_real_credit_fails(self):
        case, report, telemetry = rail_fixture()
        report["duration"] = telemetry["duration"] = 400
        report["deliveries"] = [{"id": 1, "time": t, "amount": 500} for t in (100, 200, 300)]
        telemetry["events"].append({"kind": "deploy", "id": 11, "time": 321, "team": 0, "spec": "iron_rail", "position": [5.5, 5.5]})
        audit = audit_case(report, telemetry, case)
        self.assertTrue(audit["miners"][0]["passed"])
        self.assertFalse(audit["fault_audit"]["passed"])
        self.assertFalse(audit["checks_passed"])

    def test_independent_outputs_preserve_original_identity_failure_and_reports(self):
        case, report, telemetry = fixture()
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            files = {"manifest.json": {"cases": [case], "source_sha256": {"ai": "before"}},
                     "results.json": {"cases": [case], "source_unchanged": False, "source_sha256_end": {"ai": "after"}},
                     case["id"] + "_reliability.json": report, case["id"] + ".json": telemetry}
            for name, data in files.items():
                (folder / name).write_text(json.dumps(data))
            before = {name: (folder / name).read_bytes() for name in files}
            with redirect_stdout(io.StringIO()):
                self.assertEqual(main(["--batch-dir", directory]), 1)
            audit = json.loads((folder / "delivery_audit.json").read_text())
            self.assertFalse(audit["source_identity"]["verified"])
            self.assertFalse(audit["source_identity"]["declared_unchanged"])
            self.assertEqual(before, {name: (folder / name).read_bytes() for name in files})
            self.assertTrue((folder / "delivery_audit.md").exists())


if __name__ == "__main__":
    unittest.main()
