#!/usr/bin/env python3
"""Verify the test runner rejects engine errors even when Godot exits zero.

Uses a temporary fake Godot executable; never starts Godot or edits game data.
"""

from pathlib import Path
import json
import os
import subprocess
import sys
import tempfile


def main() -> int:
    project = Path(__file__).resolve().parents[1]
    cases = [
        ("clean_output", "Godot test fixture PASS", 0, 0),
        ("runtime_error_exit_zero", "SCRIPT ERROR: Intentional self-test error", 0, 1),
        ("engine_error_exit_zero", "ERROR: Intentional self-test error", 0, 1),
        ("object_leak_exit_zero", "WARNING: ObjectDB instances leaked at exit", 0, 1),
        ("resource_leak_exit_zero", "WARNING: resources still in use at exit", 0, 1),
        ("rid_leak_exit_zero", 'WARNING: 1 RID of type "CanvasItem" was leaked.', 0, 1),
        ("rids_leak_exit_zero", 'WARNING: 2 RIDs of type "CanvasItem" were leaked.', 0, 1),
        ("nonzero_exit", "Intentional self-test failure", 7, 7),
    ]
    results = []
    with tempfile.TemporaryDirectory(prefix="paper-front-runner-selftest-") as work:
        temporary = Path(work)
        fake_godot = temporary / "godot"
        fake_godot.write_text(
            f"#!{sys.executable}\n"
            "from pathlib import Path\n"
            "import os\n"
            "with Path(os.environ['PAPER_FRONT_FAKE_COUNT']).open('a') as count:\n"
            "    count.write('call\\n')\n"
            "print(os.environ['PAPER_FRONT_FAKE_MESSAGE'])\n"
            "raise SystemExit(int(os.environ['PAPER_FRONT_FAKE_STATUS']))\n",
            encoding="utf-8",
        )
        fake_godot.chmod(0o700)
        for name, message, godot_status, expected in cases:
            count_file = temporary / f"{name}.count"
            environment = os.environ.copy()
            environment.update(
                PAPER_FRONT_GODOT=str(fake_godot),
                PAPER_FRONT_TEST_DATA=str(temporary / "data"),
                PAPER_FRONT_TEST_CONFIG=str(temporary / "config"),
                PAPER_FRONT_FAKE_MESSAGE=message,
                PAPER_FRONT_FAKE_STATUS=str(godot_status),
                PAPER_FRONT_FAKE_COUNT=str(count_file),
            )
            run = subprocess.run(
                ["sh", str(project / "tools" / "test.sh")],
                cwd=project,
                env=environment,
                capture_output=True,
                text=True,
                timeout=30,
            )
            calls = len(count_file.read_text(encoding="utf-8").splitlines())
            passed = run.returncode == expected and (calls > 1 if expected == 0 else calls == 1)
            results.append({"case": name, "exit_code": run.returncode, "expected": expected, "godot_calls": calls, "passed": passed})
            if not passed:
                print(run.stdout + run.stderr, file=sys.stderr)
    print(json.dumps({"checks": len(results), "passed": all(result["passed"] for result in results), "results": results}, indent=2))
    return 0 if all(result["passed"] for result in results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
