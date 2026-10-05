#!/usr/bin/env python3
"""Compose an original, calm low-register score for every selectable battlefield.

Deterministic CC0 mathematical synthesis. No samples, presets, recordings,
third-party melodies, network requests or music services are used.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import wave

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/audio/music"
SR = 22050
SEED = 73027
# Each original theme has its own harmony, contour, phrasing and tempo. All
# share a warm, spacious instrumental palette and avoid a bright upper lead.
THEMES = {
    "menu": dict(title="折纸灯下", bpm=76, bars=16, roots=[43, 40, 36, 38],
                 thirds=[4, 3, 4, 4], motif=[0, 4, 7, 4, 2, 0], offsets=[0, .8, 1.8, 2.6, 3.5, 4.6], tone="felt"),
    "battle": dict(title="桌面行军", bpm=78, bars=16, roots=[38, 41, 36, 43],
                   thirds=[3, 4, 4, 3], motif=[0, 3, 5, 7, 5, 3], offsets=[0, 1, 2.5, 3.5, 5, 6.2], tone="felt"),
    "battle_forest": dict(title="溪谷慢行", map_id="forest", bpm=76, bars=24, roots=[43, 40, 36, 38],
                          thirds=[4, 3, 4, 4], motif=[0, 4, 7, 9, 7, 4], offsets=[.2, 1.1, 2.4, 3.4, 5.1, 6.3], tone="wood"),
    "battle_desert": dict(title="砂岸微风", map_id="desert", bpm=72, bars=24, roots=[38, 41, 36, 43],
                          thirds=[3, 4, 4, 3], motif=[7, 3, 0, 2, 5, 3], offsets=[0, 1.4, 2.8, 4, 5.3, 6.4], tone="felt"),
    "battle_snow": dict(title="雪河缓流", map_id="snow", bpm=68, bars=24, roots=[40, 36, 43, 38],
                        thirds=[3, 4, 4, 4], motif=[7, 4, 2, 0, 4, 2], offsets=[.3, 1.8, 3, 4.2, 5.6, 6.7], tone="warm"),
    "battle_city": dict(title="纸城夜灯", map_id="city", bpm=80, bars=24, roots=[36, 43, 41, 38],
                        thirds=[4, 4, 4, 3], motif=[0, 7, 4, 2, 5, 4], offsets=[0, .9, 2, 3.3, 4.8, 6], tone="felt"),
    "battle_random_city": dict(title="街角新页", map_id="random_city", bpm=78, bars=24, roots=[41, 38, 43, 36],
                               thirds=[4, 3, 4, 4], motif=[4, 0, 5, 7, 2, 0], offsets=[.4, 1.5, 2.7, 4.1, 5.2, 6.5], tone="wood"),
    "battle_islands": dict(title="远海轻舟", map_id="islands", bpm=74, bars=24, roots=[38, 43, 40, 36],
                           thirds=[4, 4, 3, 4], motif=[0, 2, 7, 4, 9, 7], offsets=[0, 1.3, 2.6, 3.8, 5.2, 6.5], tone="wood"),
    "battle_campaign": dict(title="第一张蓝图", map_id="campaign", bpm=72, bars=16, roots=[36, 41, 43, 36],
                            thirds=[4, 4, 4, 4], motif=[0, 2, 4, 7, 4, 2], offsets=[0, 1.2, 2.5, 3.7, 5, 6.3], tone="felt"),
    "win": dict(title="归队灯火", bpm=80, bars=8, roots=[36, 41, 43, 36],
                thirds=[4, 4, 4, 4], motif=[0, 4, 7, 9, 7, 4], offsets=[0, 1, 2.1, 3.4, 4.7, 6], tone="felt"),
    "lose": dict(title="合上这一页", bpm=64, bars=8, roots=[40, 38, 36, 40],
                 thirds=[3, 3, 4, 3], motif=[7, 5, 3, 2, 0, 3], offsets=[.2, 1.5, 2.7, 4, 5.3, 6.5], tone="warm"),
    "draw": dict(title="等候下一页", bpm=70, bars=8, roots=[38, 36, 43, 38],
                 thirds=[3, 4, 4, 3], motif=[0, 5, 7, 5, 2, 0], offsets=[.2, 1.4, 2.8, 4, 5.3, 6.5], tone="felt"),
}


def hz(note: float) -> float:
    return 440.0 * 2.0 ** ((note - 69.0) / 12.0)


def voice(note: int, duration: float, kind: str) -> np.ndarray:
    t = np.arange(max(1, round(duration * SR))) / SR
    frequency = hz(note)
    # Minimum 45 ms attacks remove the old struck-tine sting. The entire
    # palette uses sine partials; no noise, metallic transients or high hats.
    if kind == "felt":
        x = (np.sin(2 * np.pi * frequency * t) * np.exp(-t * .85)
             + .055 * np.sin(2 * np.pi * frequency * 2.001 * t) * np.exp(-t * 1.8))
        attack, release = .065, .22
    elif kind == "wood":
        x = (np.sin(2 * np.pi * frequency * t) * np.exp(-t * 1.10)
             + .035 * np.sin(2 * np.pi * frequency * 2 * t) * np.exp(-t * 2.7))
        attack, release = .055, .20
    elif kind == "bass":
        x = np.sin(2 * np.pi * frequency * t) + .025 * np.sin(4 * np.pi * frequency * t)
        attack, release = .10, .42
    elif kind == "pulse":
        x = np.sin(2 * np.pi * frequency * t) * np.exp(-t * 4.0)
        attack, release = .045, .15
    else:
        phase = 2 * np.pi * frequency * t + .028 * np.sin(2 * np.pi * .65 * t)
        x = np.sin(phase) + .03 * np.sin(phase * 2)
        attack, release = .42, .65
    # Smooth cosine attack/release avoids corners in the amplitude envelope.
    onset = .5 - .5 * np.cos(np.pi * np.clip(t / attack, 0, 1))
    ending = .5 - .5 * np.cos(np.pi * np.clip((duration - t) / release, 0, 1))
    return x * onset * ending


def write_score(name: str, theme: dict) -> dict:
    beat = 60.0 / theme["bpm"]
    samples = round(theme["bars"] * 4 * beat * SR)
    score = np.zeros(samples, dtype=np.float64)
    event_count = 0
    lead_notes = []
    all_notes = []

    def add(at: float, note: int, beats: float, gain: float, kind: str) -> None:
        nonlocal event_count
        sound = voice(note, beats * beat, kind)
        start = round(at * beat * SR)
        indexes = (start + np.arange(len(sound))) % samples
        np.add.at(score, indexes, sound * gain)
        event_count += 1
        all_notes.append(note)

    for bar in range(theme["bars"]):
        chord = (bar // 2) % 4
        root = theme["roots"][chord]
        at = bar * 4
        section = (bar // 8) % 3
        # Broad low-register chords, held bass and widely spaced melody.
        # The middle section leaves deliberate musical breathing room.
        energy = .76 if section == 1 else 1.0
        add(at, root, 4.5, .042, "bass")
        for interval in [0, theme["thirds"][chord], 7]:
            add(at + .04 * interval, root + interval, 5.0, .025, "warm")
        if name not in ["lose", "battle_snow"]:
            for offset in [0, 2]:
                add(at + offset, root, .8, .012 * energy, "pulse")
        if bar % 2 == 0:
            for offset, interval in zip(theme["offsets"], theme["motif"]):
                # Keep every principal melody note between C3 and E4.
                note = min(64, root + 12 + interval)
                if section == 1 and name != "win": note -= 12
                lead_notes.append(note)
                add(at + offset, note, 2.2 if theme["tone"] == "warm" else 1.9,
                    .065 * energy, theme["tone"])
        if bar % 4 == 3:
            add(at + 2.2, root + 7, 2.4, .025, "felt")

    dry = score.copy()
    for delay, gain in [(.097, .08), (.193, .055), (.317, .035)]:
        score += np.roll(dry, round(delay * SR)) * gain
    # Circular, smooth low-pass is consistent with the seamless arrangement.
    spectrum = np.fft.rfft(score)
    frequencies = np.fft.rfftfreq(samples, 1 / SR)
    spectrum *= 1.0 / np.sqrt(1.0 + (frequencies / 1300.0) ** 8)
    score = np.fft.irfft(spectrum, n=samples)
    score -= np.mean(score)
    # Conservative -14.4 dBFS peak with consistent -26 dBFS nominal RMS.
    rms = np.sqrt(np.mean(score * score))
    score *= min(.19 / max(1e-12, np.max(np.abs(score))), .05 / max(rms, 1e-12))
    seam = round(.005 * SR)
    midpoint = (score[0] + score[-1]) * .5
    fade = .5 - .5 * np.cos(np.linspace(0, np.pi, seam))
    score[:seam] = midpoint * (1 - fade) + score[:seam] * fade
    score[-seam:] = score[-seam:] * (1 - fade) + midpoint * fade
    pcm = np.round(np.clip(score, -1, 1) * 32767).astype("<i2")
    path = OUT / f"{name}.wav"
    with wave.open(str(path), "wb") as output:
        output.setparams((1, 2, SR, 0, "NONE", "not compressed"))
        output.writeframes(pcm.tobytes())
    power = abs(np.fft.rfft(pcm.astype(float))) ** 2
    total_power = max(float(np.sum(power)), 1e-12)
    return {"scene": name, "title": theme["title"], "map_id": theme.get("map_id", ""),
            "path": f"res://assets/audio/music/{name}.wav", "bpm": theme["bpm"], "bars": theme["bars"],
            "frames": samples, "duration_s": round(samples / SR, 6), "events": event_count,
            "melody_midi_range": [min(lead_notes), max(lead_notes)],
            "melody_hz_range": [round(hz(min(lead_notes)), 3), round(hz(max(lead_notes)), 3)],
            "minimum_attack_ms": 45, "lowpass_hz": 1300,
            "peak_dbfs": round(20 * np.log10(np.max(np.abs(score))), 3),
            "rms_dbfs": round(20 * np.log10(np.sqrt(np.mean(score * score))), 3),
            "spectral_centroid_hz": round(float(np.sum(frequencies * power) / total_power), 3),
            "energy_above_4khz_percent": round(float(np.sum(power[frequencies >= 4000]) / total_power * 100), 6),
            "seam_delta_pcm": int(abs(int(pcm[0]) - int(pcm[-1]))),
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    tracks = [write_score(name, theme) for name, theme in THEMES.items()]
    manifest = {"version": 2, "license": "CC0-1.0", "origin": "project-authored mathematical synthesis",
                "generator": "tools/generate_demo_music.py", "generator_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                "seed": SEED, "format": "mono 22050 Hz signed 16-bit PCM WAV", "external_samples": False,
                "melody": "Original independent battlefield themes, spacious phrasing and low-register sine timbres",
                "map_tracks": {t["map_id"]: t["scene"] for t in tracks if t["map_id"]}, "tracks": tracks}
    (OUT / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"tracks": len(tracks), "seconds": sum(t["duration_s"] for t in tracks), "output": str(OUT)}))


if __name__ == "__main__":
    main()
