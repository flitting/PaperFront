#!/usr/bin/env python3
"""PCM, provenance and coverage checks for the independent v7 music/speech assets."""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
import wave
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "artifacts/revision_v7_audio/pcm_validation.json"
EXPECTED_MAPS = {"forest", "desert", "snow", "city", "random_city", "islands", "campaign"}
failures = []
checks = 0


def require(condition, message):
    global checks
    checks += 1
    if not condition:
        failures.append(message)


def inspect(path):
    with wave.open(str(path), "rb") as source:
        metadata = {"channels": source.getnchannels(), "sample_width": source.getsampwidth(),
                    "rate": source.getframerate(), "frames": source.getnframes()}
        raw = np.frombuffer(source.readframes(source.getnframes()), dtype="<i2")
    x = raw.astype(np.float64) / 32768
    f = np.fft.rfftfreq(len(x), 1 / metadata["rate"])
    power = abs(np.fft.rfft(x)) ** 2
    total = max(float(np.sum(power)), 1e-12)
    return metadata, raw, {
        "duration_s": len(x) / metadata["rate"], "peak_dbfs": float(20 * np.log10(max(np.max(abs(x)), 1e-12))),
        "rms_dbfs": float(20 * np.log10(max(np.sqrt(np.mean(x*x)), 1e-12))), "dc": float(np.mean(x)),
        "spectral_centroid_hz": float(np.sum(f * power) / total),
        "energy_above_4khz_percent": float(np.sum(power[f >= 4000]) / total * 100),
        "edge_start": int(raw[0]), "edge_end": int(raw[-1]), "clipped_samples": int(np.count_nonzero(abs(raw.astype(np.int32)) >= 32767)),
    }


music = json.loads((ROOT / "assets/audio/music/manifest.json").read_text())
speech = json.loads((ROOT / "assets/audio/radio/manifest.json").read_text())
require(set(music["map_tracks"]) == EXPECTED_MAPS, "Every currently selectable map and tutorial have a dedicated theme")
require(len(set(music["map_tracks"].values())) == len(EXPECTED_MAPS), "Map IDs resolve to different compositions")
require(len(music["tracks"]) == 12 and len(speech["clips"]) == 20, "Expected scene/map and faction/action coverage")
require(len({c["sha256"] for c in music["tracks"]}) == 12, "All musical assets are independently rendered")
require(music["license"] == "CC0-1.0" and speech["license"] == "GPL-3.0-or-later", "Original music and conservative GPL Mandarin audio have distinct license scopes")
results = {}
comparisons = {}
for family, entries in [("music", music["tracks"]), ("radio", speech["clips"])]:
    for entry in entries:
        path = ROOT / entry["path"].removeprefix("res://")
        metadata, raw, stats = inspect(path)
        relative = path.relative_to(ROOT).as_posix()
        require(metadata["channels"] == 1 and metadata["sample_width"] == 2 and metadata["rate"] == 22050, relative + " has the intended PCM format")
        require(hashlib.sha256(path.read_bytes()).hexdigest() == entry["sha256"], relative + " matches its provenance hash")
        require(abs(stats["duration_s"] - entry["duration_s"]) < .00001, relative + " exact duration")
        require(stats["clipped_samples"] == 0 and stats["peak_dbfs"] < -10, relative + " has conservative peak headroom")
        require(abs(stats["dc"]) < .001, relative + " avoids DC offset")
        require(stats["energy_above_4khz_percent"] < .15, relative + " controls bright high-frequency energy")
        if family == "music":
            require(raw[0] == raw[-1], relative + " has continuous loop boundary")
            require(64 <= entry["bpm"] <= 80 and entry["melody_midi_range"][1] <= 64, relative + " keeps the slow, low-register score")
            require(80 < stats["spectral_centroid_hz"] < 170, relative + " retains a warm low-frequency balance")
        else:
            require(raw[0] == 0 and raw[-1] == 0, relative + " has silent faded edges")
            require(entry["spoken_words"] and entry["language"] == "cmn" and entry["text"], relative + " records real Mandarin phrase metadata")
            require(not entry["provenance"]["online_service"] and not entry["provenance"]["human_recording"] and not entry["provenance"]["neural_model"], relative + " uses native offline synthesis and no new dialogue recording/model")
            require(entry["voice_settings"]["voice"] == "cmn-latn-pinyin+m3" and entry["phoneme_rendering"] and all("(en)" not in p for p in entry["phoneme_rendering"]), relative + " uses audited Mandarin phonemes without English switches")
            require(entry["provenance"]["upstream_phoneme_waveforms"], relative + " discloses upstream phoneme waveform contribution")
            require(-25 < stats["rms_dbfs"] < -22, relative + " stays within consistent speech loudness budget")
        results[relative] = {**metadata, **stats, "sha256": entry["sha256"]}
        before = ROOT / "artifacts/revision_v7_audio/before" / path.relative_to(ROOT)
        if before.exists():
            _, _, old = inspect(before)
            comparisons[relative] = {"before": old, "after": stats}

rules = json.loads((ROOT / "data/rules.json").read_text())
spoken_keys = {(c["faction"], c["action"]) for c in speech["clips"]}
for spec, unit in rules["units"].items():
    for action in unit.get("voices", {}):
        require((unit["faction"], action) in spoken_keys, spec + "/" + action + " has a spoken acknowledgement")
require(speech["engine"]["runtime_bundled"] is False, "Game does not bundle or link eSpeak")
require(speech["generator_license"] == "GPL-3.0-or-later", "Separate build tool carries its GPL linking license")
for name in ["ESPEAK_GPL-3.0.txt", "ESPEAK_DEBIAN_COPYRIGHT.txt", "UNICODE-LICENSE.txt"]:
    require((ROOT / "assets/audio/licenses" / name).is_file(), "Bundled source/data license record: " + name)
for manifest in [music, speech]:
    generator = ROOT / manifest["generator"]
    require(hashlib.sha256(generator.read_bytes()).hexdigest() == manifest["generator_sha256"], "Generator identity is pinned: " + str(generator))

kit = ROOT / "tools/source_assets/espeak-ng"
source = json.loads((kit / "source_download_manifest.json").read_text())
require(source["source_version"] == speech["engine"]["package_version"] == "1.51+dfsg-12build1", "Complete corresponding source matches exact installed engine/data version")
for entry in source["archives"] + [source["dsc"]]:
    path = kit / entry["file"]
    require(path.stat().st_size == entry["bytes"] and hashlib.sha256(path.read_bytes()).hexdigest() == entry["sha256"], "Official corresponding source digest/bytes: " + entry["file"])
require((kit / "project/generate_demo_radio.py").read_bytes() == (ROOT / "tools/generate_demo_radio.py").read_bytes(), "Source kit includes exact editable generation tool")
require((kit / "project/generated_audio_manifest.json").read_bytes() == (ROOT / "assets/audio/radio/manifest.json").read_bytes(), "Source kit pins final audio manifest")
for entry in speech["clips"]:
    path = kit / "project/radio" / Path(entry["path"]).name
    require(hashlib.sha256(path.read_bytes()).hexdigest() == entry["sha256"], "Source companion carries accessible raw GPL PCM: " + path.name)

report = {"status": "PASS" if not failures else "FAIL", "checks": checks, "asset_count": len(results),
          "failures": failures, "scope": "PCM only: formats, headroom, soft edges, loop seam, spectrum, map/Chinese action coverage and licensing provenance; no subjective listening claim",
          "assets": results, "before_after": comparisons}
OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
print(json.dumps({"status": report["status"], "checks": checks, "assets": len(results), "failures": failures}, ensure_ascii=False))
raise SystemExit(bool(failures))
