#!/usr/bin/env python3
"""Render review screenshots on a private X server, never the user's desktop.

Godot4.6 headless uses Dummy rendering even with a Vulkan flag, so it cannot
produce viewport pixels. This launcher gives Vulkan a private Xlib surface.
The optional --bootstrap downloads/extracts Xvfb into /tmp without installing
system packages. No visible-desktop fallback is permitted.
"""
from __future__ import annotations
import argparse
import json
import os
from pathlib import Path
import select
import shutil
import signal
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
RUNTIME = Path(tempfile.gettempdir()) / "paper-rts-offscreen"

def xvfb_binary(bootstrap: bool) -> Path:
    found = shutil.which("Xvfb")
    if found:
        return Path(found)
    executable = RUNTIME / "runtime/usr/bin/Xvfb"
    if executable.exists():
        return executable
    if not bootstrap:
        raise SystemExit("Offscreen Xvfb is unavailable. Run with --bootstrap; no desktop capture window was launched.")
    packages = RUNTIME / "packages"
    packages.mkdir(parents=True, exist_ok=True)
    subprocess.run(["apt-get", "download", "xvfb"], cwd=packages, check=True)
    package = next(packages.glob("xvfb_*.deb"))
    subprocess.run(["dpkg-deb", "-x", str(package), str(RUNTIME / "runtime")], check=True)
    return executable

def stop(process):
    if process is None or process.poll() is not None:
        return
    process.terminate()
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill(); process.wait(timeout=5)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("script", help="Project-relative or res:// Godot capture script")
    parser.add_argument("--method", choices=["gl_compatibility", "mobile", "forward_plus"], default="forward_plus")
    parser.add_argument("--size", default="1440x900")
    parser.add_argument("--timeout", type=float, default=180)
    parser.add_argument("--bootstrap", action="store_true")
    parser.add_argument("--report", default="artifacts/rts_revision_20261007/offscreen_capture_report.json")
    args = parser.parse_args()
    executable = xvfb_binary(args.bootstrap)
    # A dynamically assigned private display avoids touching the desktop's
    # DISPLAY, Xauthority, windows, window manager or process groups.
    read_fd, write_fd = os.pipe()
    server = None; game = None; code = 1
    began = time.monotonic()
    report = {"desktop_display":os.environ.get("DISPLAY", ""), "script":args.script, "method":args.method,
              "scope":"Graphics captured through a private virtual X server; no visible desktop window or desktop-window interaction.",
              "visible_desktop_fallback":False}
    with tempfile.TemporaryDirectory(prefix="paper-rts-offscreen-log-") as temporary:
        log_path = Path(temporary) / "xvfb.log"
        try:
            with log_path.open("wb") as log:
                server = subprocess.Popen([str(executable), "-displayfd", str(write_fd), "-screen", "0", args.size+"x24",
                    "-nolisten", "tcp", "-noreset", "-ac"], pass_fds=(write_fd,), stdin=subprocess.DEVNULL,
                    stdout=subprocess.DEVNULL, stderr=log)
            os.close(write_fd); write_fd = -1
            ready, _, _ = select.select([read_fd], [], [], 15)
            if not ready:
                raise RuntimeError("Private X server failed to start: "+log_path.read_text(errors="replace"))
            number = os.read(read_fd, 128).decode().strip()
            if not number.isdigit():
                raise RuntimeError("Private X server did not return a display number")
            environment = os.environ.copy()
            environment["DISPLAY"] = ":" + number
            environment.pop("WAYLAND_DISPLAY", None)
            environment.pop("XAUTHORITY", None)
            environment["PAPER_FRONT_CAPTURE_OFFSCREEN"] = "1"
            driver = "opengl3" if args.method == "gl_compatibility" else "vulkan"
            script = args.script if args.script.startswith("res://") else "res://"+args.script
            command = [os.environ.get("PAPER_FRONT_GODOT", "godot"), "--display-driver", "x11",
                "--rendering-method", args.method, "--rendering-driver", driver, "--audio-driver", "Dummy",
                "--path", str(ROOT), "--script", script]
            game = subprocess.Popen(command, cwd=ROOT, env=environment, stdin=subprocess.DEVNULL,
                                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            report.update({"private_display":environment["DISPLAY"],"private_xvfb_pid":server.pid,"capture_pid":game.pid})
            print("OFFSCREEN_CAPTURE_STARTED "+json.dumps(report), flush=True)
            output, _ = game.communicate(timeout=args.timeout)
            print(output, end="", flush=True)
            code = game.returncode
            if any(marker in output for marker in ["SCRIPT ERROR:", "ERROR:", "ObjectDB instances leaked", "resources still in use", "leaked at exit"]):
                code = 1
            report["engine_output"] = output
            software = "llvmpipe" in output.lower() or "lavapipe" in output.lower()
            report["software_renderer"] = software
            report["hardware_gpu_claim"] = False if software else None
        except KeyboardInterrupt:
            code = 130; report["interrupted"] = True
        except (RuntimeError, subprocess.TimeoutExpired) as exc:
            report["error"] = str(exc); print("OFFSCREEN_CAPTURE_FAILED "+str(exc), flush=True)
        finally:
            stop(game); stop(server)
            os.close(read_fd)
            if write_fd >= 0: os.close(write_fd)
            report.update({"exit_code":code,"wall_seconds":round(time.monotonic()-began,3),
                           "private_processes_stopped":(game is None or game.poll() is not None) and (server is None or server.poll() is not None)})
            path = ROOT / args.report
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(json.dumps(report, ensure_ascii=False, indent=2)+"\n")
            print("OFFSCREEN_CAPTURE_FINISHED "+json.dumps({k:v for k,v in report.items() if k != "engine_output"}), flush=True)
    return code

if __name__ == "__main__":
    def interrupted(_signal, _frame):
        raise KeyboardInterrupt
    signal.signal(signal.SIGTERM, interrupted)
    raise SystemExit(main())
