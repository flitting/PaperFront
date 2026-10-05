#!/usr/bin/env python3
"""Build Chinese unit speech and original aviation sound effects.

Regenerate: python -m pip install edge-tts; python tools/generate_unit_voices.py
Requires ffmpeg. Only the authored game dialogue is sent to Edge TTS. The
manifest identifies synthesized speech separately from original PCM effects.
Existing matching WAVs are reused; use --force to synthesize them again.
Use --units '*_ship_*' to add naval dialogue without rewriting other clips.
"""
from __future__ import annotations
import argparse
import asyncio
import fnmatch
import hashlib
import importlib.metadata
import json
import math
from pathlib import Path
import random
import shutil
import struct
import subprocess
import tempfile
import wave

ROOT = Path(__file__).resolve().parents[1]
SPEAKERS = {
    "kestrel": "zh-CN-YunxiNeural", "rivet": "zh-CN-YunyangNeural",
    "iron": "zh-CN-YunyangNeural", "sky": "zh-CN-YunxiNeural",
}
RATE = 22050


def write_wav(path: Path, samples: list[float]) -> None:
    peak = max(abs(x) for x in samples) or 1.0
    pcm = b"".join(struct.pack("<h", round(max(-1.0, min(1.0, x / peak * 0.62)) * 32767)) for x in samples)
    with wave.open(str(path), "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(pcm)


def aviation_effects() -> list[dict]:
    """Original deterministic oscillators/noise; no sampled or third-party audio."""
    folder = ROOT / "assets/audio"
    effects = []
    for name, duration in [("fire_air", .23), ("bomb_release", .55), ("rearm", .68), ("aircraft_loop", 2.0)]:
        samples = []
        rng = random.Random(731 + sum(map(ord, name)))
        for i in range(round(RATE * duration)):
            t = i / RATE
            if name == "aircraft_loop":
                # Integer cycles over two seconds give a seamless tonal loop.
                value = (math.sin(math.tau * 89 * t) + .4 * math.sin(math.tau * 178 * t)) * (.7 + .3 * math.sin(math.tau * 14 * t))
            elif name == "fire_air":
                value = (rng.uniform(-1, 1) * .65 + math.sin(math.tau * (1100 * t - 1000 * t*t))) * math.exp(-t * 20)
            elif name == "bomb_release":
                value = (math.sin(math.tau * (420 * t - 190 * t*t)) + .15 * rng.uniform(-1, 1)) * math.sin(math.pi * t / duration) * math.exp(-t * 2)
            else:
                envelope = math.sin(math.pi * t / duration) ** 2
                value = math.sin(math.tau * 520 * t) * envelope * (.45 + .45 * math.sin(math.tau * 7 * t))
            if name == "fire_air":
                edge = round(RATE * .003)
                value *= min(1.0, i / edge, (round(RATE * duration) - 1 - i) / edge)
            samples.append(value)
        path = folder / (name + ".wav")
        write_wav(path, samples)
        effects.append({"kind": name, "path": "res://" + path.relative_to(ROOT).as_posix(), "provenance": "Original deterministic PCM synthesis in tools/generate_unit_voices.py", "license": "CC0-1.0", "sample_rate": RATE})
    return effects


async def generate(force: bool, unit_patterns: list[str] | None = None) -> None:
    import edge_tts
    if not shutil.which("ffmpeg"):
        raise RuntimeError("ffmpeg is required to convert speech to PCM WAV")
    rules = json.loads((ROOT / "data/rules.json").read_text())
    destination = ROOT / "assets/audio/voices"
    destination.mkdir(parents=True, exist_ok=True)
    manifest_path = destination / "manifest.json"
    previous = json.loads(manifest_path.read_text()) if manifest_path.exists() else {}
    existing = {clip.get("key"): clip for clip in previous.get("clips", [])}
    # A partial regeneration retains every unrelated record, including its
    # original provenance/source hashes and any future manifest metadata.
    clips = dict(existing)
    lock = asyncio.Semaphore(4)
    async def synthesize(spec: str, action: str, index: int, text: str, faction: str) -> None:
        key = f"{spec}/{action}/{index}"
        path = destination / f"{spec}_{action}_{index+1:02d}.wav"
        speaker = SPEAKERS[faction]
        source_hash = hashlib.sha256((speaker + "\n" + text).encode()).hexdigest()
        cached = existing.get(key, {})
        if force or not path.exists() or cached.get("source_sha256") != source_hash:
            async with lock:
                with tempfile.TemporaryDirectory(prefix="paper-front-voice-") as temp:
                    mp3 = Path(temp) / "speech.mp3"
                    for attempt in range(3):
                        try:
                            await asyncio.wait_for(edge_tts.Communicate(text, speaker, rate="-4%", pitch="-2Hz").save(str(mp3)), timeout=45)
                            break
                        except Exception:
                            if attempt == 2: raise
                            await asyncio.sleep(1 + attempt)
                    converted = Path(temp) / "speech.wav"
                    subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", str(mp3), "-af", "highpass=f=70,loudnorm=I=-19:TP=-4:LRA=7", "-ar", str(RATE), "-ac", "1", "-c:a", "pcm_s16le", str(converted)], check=True)
                    shutil.copyfile(converted, path)
        with wave.open(str(path)) as wav:
            if wav.getframerate() != RATE or wav.getnchannels() != 1 or wav.getsampwidth() != 2:
                raise RuntimeError(f"Invalid PCM speech format: {path}")
            duration = round(wav.getnframes() / wav.getframerate(), 3)
        if duration <= .25:
            raise RuntimeError(f"Speech clip is too short: {path}")
        wav_hash = hashlib.sha256(path.read_bytes()).hexdigest()
        if cached.get("source_sha256") == source_hash and cached.get("sha256") == wav_hash and not force:
            clips[key] = cached
        else:
            clips[key] = {"key": key, "unit": spec, "action": action, "variant": index, "text": text, "path": "res://" + path.relative_to(ROOT).as_posix(), "duration": duration, "speaker": speaker, "source_sha256": source_hash, "sha256": wav_hash, "provenance": {"type": "synthesized_speech", "provider": "Microsoft Edge online text-to-speech", "client": "edge-tts", "client_version": importlib.metadata.version("edge-tts"), "authored_dialogue": "data/rules.json units voices", "human_recording": False}}
        print(f"VOICE {key} {duration:.2f}s", flush=True)
    jobs = []
    for spec, unit in rules["units"].items():
        if unit_patterns and not any(fnmatch.fnmatchcase(spec, pattern) for pattern in unit_patterns):
            continue
        for action, entries in unit.get("voices", {}).items():
            for index, text in enumerate(entries):
                jobs.append(synthesize(spec, action, index, text, unit["faction"]))
    if not jobs:
        raise RuntimeError("No authored units voices were found in data/rules.json")
    await asyncio.gather(*jobs)
    manifest = dict(previous)
    manifest.update({"version": 1, "language": "zh-CN", "format": "PCM signed 16-bit mono WAV", "sample_rate": RATE, "dialogue_source": "res://data/rules.json", "regenerate": "python tools/generate_unit_voices.py [--force] [--units UNIT_GLOB ...]", "speech_notice": "Synthetic Chinese speech; provider voices and service are not claimed as CC0 or original human recordings. No API key is required for this regeneration method.", "clips": sorted(clips.values(), key=lambda clip: clip["key"])})
    if "effects" not in manifest:
        manifest["effects"] = aviation_effects()
    temporary_manifest = manifest_path.with_suffix(".json.tmp")
    temporary_manifest.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    temporary_manifest.replace(manifest_path)
    print(f"COMPLETE {len(clips)} speech clips -> {manifest_path}", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--units", nargs="+", metavar="UNIT_GLOB", help="Regenerate only matching unit IDs; retain every other manifest record")
    args = parser.parse_args()
    asyncio.run(generate(args.force, args.units))
