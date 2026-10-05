#!/usr/bin/env python3
"""Capture frozen RTS gameplay/G0 views through the real Godot renderer."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys

SOURCE_PATHS = (
    "project.godot", "scripts/main.gd", "scripts/miniature_lens.gd",
    "scripts/golden_visual.gd", "scripts/golden_landscape_capture.gd",
    "scripts/paper_world.gd", "scripts/volume_models.gd", "scripts/landscape.gd",
    "scripts/map_data.gd", "scripts/paper_hud.gd", "scripts/minimap.gd", "data/rules.json",
)
OPTIONAL_SOURCE_PATHS = ("assets/textures/pigment_noise.png", "assets/models/pine_0.res", "assets/models/pine_1.res", "assets/models/pine_2.res", "scripts/bridge_craft.gd", "scripts/scenery_scale.gd", "scripts/pine_model.gd", "scripts/cliff_craft.gd", "scripts/paper_audio.gd", "scripts/paper_ui.gd", "scripts/contextual_props.gd", "scripts/foreground_grove.gd", "scripts/north_context.gd")
VIEWS = ("gameplay", "g0", "gameplay_hq", "gameplay_factory", "gameplay_barracks", "gameplay_empty")


def state_view(state):
    return state.get("view", "g0" if state.get("scene") == "G0" else state.get("scene"))


def read_baselines(path):
    if path is None:
        return {}
    candidates = sorted(path.glob("*.json"), key=lambda p: p.stat().st_mtime) if path.is_dir() else [path]
    result = {}
    for candidate in candidates:
        state = json.loads(candidate.read_text())
        view = state_view(state)
        # Performance reports can carry a view name but are not capture states.
        # A mixed artifact directory must never select one as a visual baseline.
        capture_fields = ("fixture_hash", "viewport", "tick", "simulation_time", "visual_time", "selection", "camera")
        if view in VIEWS and all(field in state for field in capture_fields):
            result[view] = (candidate.resolve(), state)
    if not result:
        raise ValueError(f"No gameplay/G0 capture metadata in baseline: {path}")
    return result


def validate_capture(output, metadata, view, expected_hashes, baseline, allow_lighting_change, allow_ui_change=False, allow_scene_change=False, allow_props_change=False):
    if not output.is_file() or not metadata.is_file():
        raise ValueError("No fresh PNG/metadata")
    with output.open("rb") as stream:
        header = stream.read(24)
    if len(header) != 24 or header[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("Invalid PNG header")
    dimensions = struct.unpack(">II", header[16:24])
    state = json.loads(metadata.read_text())
    if dimensions != (1920, 1080) or state.get("viewport") != [1920, 1080]:
        raise ValueError("Capture has an unexpected pixel size")
    if state_view(state) != view or state.get("visual_time") != 0 or state.get("warmup_frames") != 8:
        raise ValueError("Capture was not taken at the frozen eight-draw frame")
    if state.get("tick") != 135 or state.get("simulation_time") != 4.5 \
            or not re.fullmatch(r"[a-f0-9]{64}", state.get("fixture_hash", "")):
        raise ValueError("Frozen fixture/time metadata is invalid")
    if state.get("renderer") != "forward_plus":
        raise ValueError("Capture did not use the real Forward+ renderer")
    layout = state.get("layout", {})
    dock_width = layout.get("dock_width")
    pixels = layout.get("battlefield_pixels")
    if not isinstance(dock_width, (int, float)) or dock_width < 0 \
            or not isinstance(pixels, list) or len(pixels) != 2:
        raise ValueError("Battlefield/client layout metadata is invalid")
    expected_width = 1920 - round(dock_width * 1.2)
    if not 0 < expected_width <= 1920 or pixels != [expected_width, 1080]:
        raise ValueError("Battlefield pixels do not match the real window/dock layout")
    probe = state.get("image_check", {})
    if probe.get("region") != "battlefield" or probe.get("sample_count", 0) < 1000 \
            or probe.get("unique_colors", 0) < 32 or probe.get("luminance_range", 0) < 0.1:
        raise ValueError("Rendered battlefield is blank or lacks valid image variation")
    hashes = state.get("source_hashes", {})
    if any(not re.fullmatch(r"[a-f0-9]{64}", value) for value in hashes.values()):
        raise ValueError("Malformed runtime source hash")
    if expected_hashes and any(hashes.get(key) != value for key, value in expected_hashes.items()):
        raise ValueError("Runtime source hashes do not match the source loaded by this command")
    ui = state.get("ui", {})
    if ui.get("menu_visible") or ui.get("debug_visible") or ui.get("placing"):
        raise ValueError("Capture UI is not in its fixed comparison state")
    if view.startswith("gameplay") and (ui.get("dev_mode") or not ui.get("is_started")):
        raise ValueError("Gameplay capture did not use the normal gameplay HUD")
    compared = []
    if baseline:
        old = baseline[1]
        compared = ["fixture_hash", "tick", "simulation_time", "visual_time", "viewport", "selection", "camera"]
        if allow_scene_change or allow_props_change:
            compared.remove("fixture_hash")
            invariants = ["non_map_state_hash"]
            if not allow_scene_change:
                invariants.append("map_state_hash")
            if not allow_props_change:
                invariants.append("prop_batches_hash")
            for key in invariants:
                if not re.fullmatch(r"[a-f0-9]{64}", old.get(key, "")):
                    raise ValueError("Scene baseline lacks invariant hashes; capture the unchanged scene first")
                compared.append(key)
        if not allow_ui_change:
            compared += [key for key in ("layout", "ui") if key in old]
        if not allow_lighting_change:
            compared += [key for key in ("lighting", "render_settings", "photography") if key in old]
        differences = [key for key in compared if old.get(key) != state.get(key)]
        if old.get("render_settings", {}).get("render_scale", 1.0) != state.get("render_settings", {}).get("render_scale"):
            differences.append("render_scale")
        if differences:
            raise ValueError(f"Comparison conditions changed: {', '.join(differences)}")
    return state, compared


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--name", required=True, help="Unique iteration name, e.g. v13_baseline")
    parser.add_argument("--views", default="g0", help="Comma-separated views: " + ",".join(VIEWS) + " (default: legacy g0)")
    parser.add_argument("--output-dir", type=Path, help="Version directory; default preserves artifacts/visual_iteration/g0")
    parser.add_argument("--baseline", type=Path, help="Previous version directory or single capture JSON; compare matching views")
    parser.add_argument("--fixture", type=Path, help="Explicit frozen scene manifest; omit to keep the established G0")
    parser.add_argument("--allow-scene-change", action="store_true", help="Terrain round: allow map changes but require identical non-map state and resolved props, camera, time, UI and lighting")
    parser.add_argument("--allow-props-change", action="store_true", help="Scenery round: allow resolved props to change but require identical map, entities, camera, UI, time and lighting")
    parser.add_argument("--executable", type=Path, help="Development Linux executable; omit to load source with Godot")
    parser.add_argument("--prepare-assets", action="store_true", help="Source artwork round: import changed SVG/resources before launching the real renderer")
    parser.add_argument("--hold", action="store_true", help="Keep the last view open for manual diagnosis; Esc finishes")
    parser.add_argument("--allow-lighting-change", action="store_true", help="Allow lighting/photography changes, keeping fixture, camera, scale and UI fixed")
    parser.add_argument("--allow-ui-change", action="store_true", help="Allow layout/UI changes, keeping fixture, camera, lighting, selection, resolution, time and scale fixed")
    parser.add_argument("--replace", action="store_true", help="Explicitly replace this named capture")
    args = parser.parse_args()
    if args.prepare_assets and args.executable is not None:
        parser.error("--prepare-assets is for source captures; exported resources are already built")
    if not re.fullmatch(r"[a-zA-Z0-9_-]+", args.name):
        parser.error("--name may contain letters, numbers, underscores and hyphens only")
    views = [view.strip().lower() for view in args.views.split(",") if view.strip()]
    if not views or len(set(views)) != len(views) or any(view not in VIEWS for view in views):
        parser.error("--views must contain unique names from: " + ",".join(VIEWS))
    root = Path(__file__).resolve().parents[1]
    fixture = args.fixture.expanduser().resolve() if args.fixture else None
    if fixture and not fixture.is_file():
        parser.error(f"--fixture does not exist: {fixture}")
    try:
        expected_fixture_hash = json.loads(fixture.read_text()).get("fixture_hash") if fixture else None
    except (OSError, ValueError) as error:
        parser.error(f"Cannot read requested fixture: {error}")
    if fixture and not re.fullmatch(r"[a-f0-9]{64}", str(expected_fixture_hash)):
        parser.error("Requested fixture lacks its checked-in identity hash")
    if (args.allow_scene_change or args.allow_props_change) and (fixture is None or args.baseline is None):
        parser.error("Scene/props comparisons require an explicit --fixture and --baseline")
    folder = (args.output_dir or root / "artifacts/visual_iteration/g0").expanduser().resolve()
    folder.mkdir(parents=True, exist_ok=True)
    paths = {}
    for view in views:
        stem = args.name if views == ["g0"] else f"{args.name}_{view}"
        output = folder / f"{stem}.png"
        paths[view] = (output, output.with_suffix(".json"))
    log = folder / f"{args.name}.log"
    run_path = folder / f"{args.name}.run.json"
    existing = [path for pair in paths.values() for path in pair] + [log, run_path]
    if any(path.exists() for path in existing) and not args.replace:
        parser.error("Capture already exists; use another name/version directory to preserve previous images")
    try:
        baselines = read_baselines(args.baseline)
    except (OSError, ValueError) as error:
        parser.error(str(error))
    if (args.allow_scene_change or args.allow_props_change) and any(view not in baselines for view in views):
        parser.error("Scene/props comparison needs a baseline for every requested view")
    expected_hashes = {}
    if args.executable is not None:
        executable = args.executable.expanduser().resolve()
        if not executable.is_file() or not os.access(executable, os.X_OK):
            parser.error(f"--executable is not an executable file: {executable}")
        command = [str(executable)]
        build_hash = hashlib.sha256(executable.read_bytes()).hexdigest()
    else:
        godot = shutil.which("godot")
        if not godot:
            parser.error("Godot executable is unavailable")
        command = [godot, "--path", str(root)]
        build_hash = None
        expected_hashes = {f"res://{path}": hashlib.sha256((root / path).read_bytes()).hexdigest() for path in SOURCE_PATHS}
        expected_hashes.update({f"res://{path}": hashlib.sha256((root / path).read_bytes()).hexdigest()
                                for path in OPTIONAL_SOURCE_PATHS if (root / path).is_file()})
        rules = json.loads((root / "data/rules.json").read_text())
        sprite_paths = {"res://assets/cards/contours.json"}
        for spec in rules["units"].values():
            if spec["art"] in ("rifle", "anti", "engineer", "demolition"):
                sprite_paths.update(spec["animations"].values())
        expected_hashes.update({path: hashlib.sha256((root / path.removeprefix("res://")).read_bytes()).hexdigest()
                                for path in sorted(sprite_paths)})
    for pair in paths.values():
        for path in pair:
            path.unlink(missing_ok=True)
    command += ["--windowed", "--resolution", "1920x1080", "--position", "32,32", "--", "--golden-visual", "--golden-label", args.name]
    if fixture:
        command += ["--golden-fixture", str(fixture)]
    if len(views) == 1:
        command += ["--golden-view", views[0], "--golden-capture", str(paths[views[0]][0])]
    else:
        command += ["--golden-views", ",".join(views), "--golden-capture-dir", str(folder)]
    if args.hold:
        command.append("--golden-hold")
    run = {
        "status": "running", "started_at_utc": datetime.now(timezone.utc).isoformat(),
        "command": command, "cwd": str(root), "views": views, "log": str(log),
        "source_hashes": expected_hashes, "executable_sha256": build_hash,
        "allow_lighting_change": args.allow_lighting_change,
        "allow_ui_change": args.allow_ui_change,
        "allow_scene_change": args.allow_scene_change, "fixture_override": str(fixture) if fixture else None,
        "allow_props_change": args.allow_props_change,
        "expected_fixture_hash": expected_fixture_hash,
        "preparation": {"status": "pending", "command": [godot, "--headless", "--path", str(root), "--import"],
                        "log": str(folder / f"{args.name}.import.log")} if args.prepare_assets else None,
        "outputs": {}, "errors": [],
    }
    run_path.write_text(json.dumps(run, indent=2) + "\n")
    try:
        if args.prepare_assets:
            prepare = run["preparation"]
            with Path(prepare["log"]).open("w") as stream:
                imported = subprocess.run(prepare["command"], cwd=root, stdout=stream, stderr=subprocess.STDOUT, timeout=90)
            prepare["returncode"] = imported.returncode
            prepare["status"] = "failed" if imported.returncode or re.search(r"^(?:SCRIPT )?ERROR:", Path(prepare["log"]).read_text(), re.MULTILINE) else "success"
            if prepare["status"] != "success":
                raise ValueError(f"Resource import failed; inspect {prepare['log']}")
        with log.open("w") as stream:
            result = subprocess.run(command, cwd=root, stdout=stream, stderr=subprocess.STDOUT, timeout=90)
        run["returncode"] = result.returncode
        text = log.read_text()
        if result.returncode or re.search(r"^(?:SCRIPT )?ERROR:", text, re.MULTILINE):
            raise ValueError(f"Godot failed with exit code {result.returncode}; inspect {log}")
        if "GOLDEN_READY " not in text:
            raise ValueError(f"Game did not enter the capture scene; inspect {log}")
        for view, (output, metadata) in paths.items():
            try:
                if f"GOLDEN_CAPTURE {output} code=0" not in text:
                    raise ValueError("Renderer did not report a successful capture")
                state, compared = validate_capture(output, metadata, view, expected_hashes, baselines.get(view), args.allow_lighting_change, args.allow_ui_change, args.allow_scene_change, args.allow_props_change)
                if expected_fixture_hash and state.get("fixture_hash") != expected_fixture_hash:
                    raise ValueError("Game did not load the explicitly requested frozen scene")
                run["outputs"][view] = {
                    "status": "success", "png": str(output), "metadata": str(metadata),
                    "sha256": hashlib.sha256(output.read_bytes()).hexdigest(),
                    "fixture_hash": state["fixture_hash"], "scene_role": state.get("scene_role"),
                    "baseline": str(baselines[view][0]) if view in baselines else None,
                    "compared_fields": compared, "image_check": state["image_check"],
                    "source_hashes_available": bool(state.get("source_hashes")),
                }
                print(f"SUCCESS {view}: {output}")
            except (OSError, ValueError, KeyError, struct.error) as error:
                run["outputs"][view] = {"status": "failed", "png": str(output), "metadata": str(metadata), "error": str(error)}
                run["errors"].append(f"{view}: {error}")
                print(f"FAILED {view}: {output}: {error}", file=sys.stderr)
    except (subprocess.TimeoutExpired, OSError, ValueError) as error:
        run["errors"].append(str(error))
        print(f"FAILED: {error}", file=sys.stderr)
    for view, (output, metadata) in paths.items():
        if view not in run["outputs"]:
            run["outputs"][view] = {
                "status": "failed", "png": str(output), "metadata": str(metadata),
                "error": "Capture did not complete; inspect the run log",
            }
            print(f"FAILED {view}: {output}", file=sys.stderr)
    run["status"] = "failed" if run["errors"] else "success"
    run["finished_at_utc"] = datetime.now(timezone.utc).isoformat()
    run_path.write_text(json.dumps(run, indent=2) + "\n")
    print(f"{run['status'].upper()} run: {run_path}; log: {log}")
    if run["status"] == "success":
        print("Frozen real-render capture verified; open the PNGs for visual acceptance.")
    return 1 if run["errors"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
