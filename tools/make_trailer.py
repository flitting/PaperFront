#!/usr/bin/env python3
"""Reproduce the 28-second English in-engine Paper Front showcase.

First render screenshots on a private display:
  python3 tools/make_trailer.py --render
Or animate existing artifacts/release_20261011/trailer/raw/ screenshots:
  python3 tools/make_trailer.py

Requirements: Godot 4.6.2, Xvfb (the offscreen tool can bootstrap it), ffmpeg,
ffprobe, Noto Sans. No external imagery, footage or music is downloaded.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / "artifacts/release_20261011/trailer"
MEDIA = ROOT / "media"
MUSIC = ROOT / "assets/audio/music/battle_city.wav"
FONT = Path("/usr/share/fonts/truetype/noto/NotoSans-Regular.ttf")
SHOTS = [
    ("battlefield", "A world cut from paper"),
    ("factions", "Four factions. Distinct war machines."),
    ("fleet", "Command land, sea and sky"),
    ("squads", "Lead your infantry squads"),
]


def run(args: list[str], label: str) -> None:
    print(label, flush=True)
    with (WORK / f"{label}.log").open("w") as log:
        result = subprocess.run(args, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
    if result.returncode:
        raise RuntimeError(f"{label} failed: {(WORK / f'{label}.log').read_text()[-6000:]}")


def text_filter(text: str, name: str, size: int, y: str | int,
                *, x: str | int = "(w-tw)/2", font: Path = FONT,
                color: str = "0xeee3cc") -> str:
    path = WORK / f"text-{name}.txt"
    path.write_text(text, encoding="utf-8")
    return (f"drawtext=fontfile='{font}':textfile='{path}':fontsize={size}:"
            f"fontcolor={color}:x={x}:y={y}:shadowcolor=black@0.35:shadowx=0:shadowy=2")


def encode(source: list[str], filters: list[str], output: Path, duration: int) -> None:
    run(["ffmpeg", "-y", "-hide_banner", "-loglevel", "error", *source,
         "-vf", ",".join(filters), "-an", "-t", str(duration),
         "-r", "30", "-c:v", "libx264", "-preset", "medium", "-crf", "20",
         "-pix_fmt", "yuv420p", "-threads", "4", "-movflags", "+faststart", str(output)], output.stem)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--render", action="store_true")
    args = parser.parse_args()
    WORK.mkdir(parents=True, exist_ok=True)
    MEDIA.mkdir(exist_ok=True)
    (MEDIA / ".gdignore").touch()
    if not FONT.is_file():
        raise RuntimeError(f"Install the Noto Sans font or adjust FONT: {FONT}")
    if args.render:
        run(["python3", "tools/run_offscreen_capture.py", "tools/capture_trailer.gd",
             "--size", "1920x1080", "--timeout", "360", "--bootstrap",
             "--report", "artifacts/release_20261011/trailer/stills_capture_report.json"], "recording")
    clips: list[Path] = []
    raw = WORK / "raw"
    capture = json.loads((raw / "capture_manifest.json").read_text())
    capture_report = json.loads((WORK / "stills_capture_report.json").read_text())
    assert capture_report["exit_code"] == 0, "Capture contains engine errors; inspect capture report."
    assert [shot["shot"] for shot in capture["shots"]] == [shot[0] for shot in SHOTS]
    assert [shot["map_size"] for shot in capture["shots"]] == [320, 192, 192, 192]
    first = raw / "battlefield/0000.png"
    if not first.is_file():
        raise RuntimeError("Missing footage. Run with --render first.")
    opening = WORK / "00-opening.mp4"
    intro_filters = [
        "scale=1280:720", "drawbox=color=0x241e18@0.56:t=fill",
        "drawbox=x=570:y=236:w=140:h=5:color=0xd8a356:t=fill",
        text_filter("PAPER FRONT", "intro-title", 82, 264),
        text_filter("A paper-crafted real-time strategy game", "intro-line", 26, 447),
        text_filter("IN-ENGINE SHOWCASE", "intro-note", 17, 653),
        "fade=t=in:st=0:d=0.5", "fade=t=out:st=2.65:d=0.35",
    ]
    encode(["-loop", "1", "-framerate", "30", "-i", str(first)], intro_filters, opening, 3)
    clips.append(opening)
    for index, (name, english) in enumerate(SHOTS, 1):
        source = raw / name / "0000.png"
        if not source.is_file():
            raise RuntimeError(f"Missing in-engine screenshot: {source}")
        clip = WORK / f"0{index}-{name}.mp4"
        # Keep all ship hulls and the barracks roof clear of caption bands.
        framing = []
        if name == "fleet":
            framing = ["pad=1280:800:0:0:color=0x241e18", "crop=1280:720:0:80"]
        elif name == "squads":
            framing = ["pad=1280:760:0:40:color=0x241e18", "crop=1280:720:0:0"]
        filters = [
            "scale=2560:1440", "zoompan=z='1.03+on*0.00035':x='iw/2-iw/zoom/2+12*sin(on/90)':y='ih/2-ih/zoom/2':d=150:s=1280x720:fps=30",
            *framing,
            "drawbox=x=0:y=0:w=iw:h=42:color=0x241e18@0.78:t=fill",
            "drawbox=x=0:y=606:w=iw:h=114:color=0x241e18@0.88:t=fill",
            text_filter("PAPER FRONT", name + "-brand", 17, 11, x=38),
            text_filter("IN-ENGINE SHOWCASE", name + "-label", 14, 14, x="w-tw-38"),
            "drawbox=x=39:y=626:w=4:h=65:color=0xd8a356:t=fill",
            text_filter(english, name + "-en", 32, 620, x=59),
            "fade=t=in:st=0:d=0.35", "fade=t=out:st=4.65:d=0.35",
        ]
        encode(["-i", str(source)], filters, clip, 5)
        clips.append(clip)
        if name in ("battlefield", "factions", "fleet"):
            run(["ffmpeg", "-y", "-hide_banner", "-loglevel", "error", "-i",
                 str(source), "-frames:v", "1", "-q:v", "2",
                 str(MEDIA / f"gameplay-{name}.jpg")], f"image-{name}")
    closing = WORK / "05-closing.mp4"
    end_filters = [
        "scale=1280:720", "drawbox=color=0x241e18@0.65:t=fill",
        text_filter("BUILD YOUR FRONT.", "end-title", 58, 137),
        text_filter("WINDOWS  /  LINUX", "end-platforms", 22, 309),
        text_filter("github.com/flitting/PaperFront", "end-url", 26, 356),
        text_filter("Thanks to Codex for its contributions", "end-codex", 23, 453),
        text_filter("Powered by Godot Engine", "end-godot", 23, 495),
        "fade=t=in:st=0:d=0.35", "fade=t=out:st=4.3:d=0.7",
    ]
    encode(["-loop", "1", "-framerate", "30", "-i", str(first)], end_filters, closing, 5)
    clips.append(closing)
    concat = WORK / "clips.txt"
    concat.write_text("".join(f"file '{path}'\n" for path in clips))
    output = MEDIA / "paper-front-trailer.mp4"
    run(["ffmpeg", "-y", "-hide_banner", "-loglevel", "error", "-f", "concat",
         "-safe", "0", "-i", str(concat), "-i", str(MUSIC), "-t", "28",
         "-map", "0:v", "-map", "1:a", "-c:v", "copy", "-c:a", "aac", "-b:a", "160k",
         "-ar", "48000", "-ac", "2",
         "-af", "loudnorm=I=-18:TP=-2:LRA=9,afade=t=in:st=0:d=1,afade=t=out:st=26:d=2",
         "-movflags", "+faststart", str(output)], "final-trailer")
    poster_filters = ["drawbox=color=0x241e18@0.42:t=fill",
                      text_filter("PAPER FRONT", "poster-title", 120, 371),
                      text_filter("A paper-crafted real-time strategy game", "poster-line", 36, 642),
                      text_filter("WATCH THE IN-ENGINE SHOWCASE", "poster-watch", 26, 960)]
    run(["ffmpeg", "-y", "-hide_banner", "-loglevel", "error", "-i", str(first),
         "-vf", ",".join(poster_filters), "-frames:v", "1", "-q:v", "2", str(MEDIA / "poster.jpg")], "poster")
    probe = json.loads(subprocess.check_output(["ffprobe", "-v", "error", "-show_streams",
                                                "-show_format", "-of", "json", str(output)]))
    (WORK / "ffprobe.json").write_text(json.dumps(probe, indent=2) + "\n")
    video = next(stream for stream in probe["streams"] if stream["codec_type"] == "video")
    audio = next(stream for stream in probe["streams"] if stream["codec_type"] == "audio")
    assert video["codec_name"] == "h264" and audio["codec_name"] == "aac"
    assert audio["sample_rate"] == "48000" and audio["channels"] == 2
    assert (video["width"], video["height"]) == (1280, 720)
    assert abs(float(probe["format"]["duration"]) - 28.0) < .1
    assert output.stat().st_size < 25 * 1024 * 1024
    provenance = {
        "title": "Paper Front — in-engine showcase",
        "language": "English",
        "duration_seconds": 28, "video": "1280×720, H.264, 30 fps", "audio": "AAC",
        "visual_origin": "Animated montage of actual in-engine screenshots. Camera motion is added in the edit. Faction, fleet and infantry details use authored deployments with current production PaperWorld and rules. No AI imagery; not a recorded player match.",
        "scenes": capture["shots"],
        "renderer": capture["renderer"],
        "capture_device": capture["device"],
        "credits": ["Thanks to Codex for its contributions", "Powered by Godot Engine"],
        "music": {"file": str(MUSIC.relative_to(ROOT)), "track_id": "battle_city",
                  "license": "CC0-1.0", "origin": "project-authored mathematical synthesis; no external samples",
                  "generator": "tools/generate_demo_music.py",
                  "manifest": "assets/audio/music/manifest.json",
                  "sha256": hashlib.sha256(MUSIC.read_bytes()).hexdigest()},
        "assets_notice": "assets/LICENSE.md and docs/demo_credits.md govern underlying game assets. This media does not relicense third-party assets.",
        "files": {path.name: {"bytes": path.stat().st_size, "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
                  for path in sorted(MEDIA.iterdir()) if path.suffix in (".jpg", ".mp4")},
    }
    (MEDIA / "provenance.json").write_text(json.dumps(provenance, indent=2, ensure_ascii=False) + "\n")
    shutil.copyfile(MEDIA / "provenance.json", WORK / "provenance.json")
    print(f"Verified {output}: {output.stat().st_size / 1024 / 1024:.2f} MiB, 28 seconds")


if __name__ == "__main__":
    main()
