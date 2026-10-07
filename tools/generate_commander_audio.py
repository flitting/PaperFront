#!/usr/bin/env python3
"""Generate restrained Mandarin commander recordings with the free Edge voice.

Requires edge-tts, numpy, pyworld and ffmpeg only while regenerating. The game plays local PCM
WAV files offline; no API key, paid API, or run-time synthesis is used.
"""
import asyncio
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import wave
import edge_tts
import numpy as np
import pyworld

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/audio/commander"
VOICE = "zh-CN-XiaoxiaoNeural"
DIALOGUE = {
    "building_ready": "建筑准备就绪。",
    "building_complete": "建筑已完成。",
    "unit_ready": "单位生产完成。",
    "enemy_seen": "发现敌军。",
    "enemy_mass": "发现大批敌军。",
    "enemy_base": "发现敌方基地。",
    "infantry_attacked": "我方步兵受到攻击。",
    "vehicle_attacked": "我方车辆受到攻击。",
    "harvester_attacked": "矿车受到攻击。",
    "building_attacked": "我方建筑受到攻击。",
    "base_attacked": "基地受到攻击。",
    "combat": "我方部队正在交火。",
    "unit_lost": "我方单位阵亡。",
}

def restrain_prosody(wav):
    """Keep words/timing/formants and gently reduce voiced pitch excursions.

    This is a measurable deadpan delivery treatment, not an emotion classifier
    or a claim that a human has auditioned the result.
    """
    with wave.open(str(wav)) as source:
        sr = source.getframerate()
        signal = np.frombuffer(source.readframes(source.getnframes()), dtype="<i2").astype(np.float64) / 32768.0
    f0, times = pyworld.dio(signal, sr, f0_floor=80, f0_ceil=500, frame_period=5.0)
    f0 = pyworld.stonemask(signal, f0, times, sr)
    voiced = f0 > 0
    if not np.any(voiced):
        raise RuntimeError("No voiced frames detected; refusing an unverified deadpan treatment")
    spectrum = pyworld.cheaptrick(signal, f0, times, sr)
    noise = pyworld.d4c(signal, f0, times, sr)
    median = float(np.median(f0[voiced]))
    controlled = f0.copy()
    controlled[voiced] = median + (f0[voiced] - median) * .60
    result = pyworld.synthesize(controlled, spectrum, noise, sr, frame_period=5.0)
    peak = float(np.max(np.abs(result)))
    original_peak = float(np.max(np.abs(signal)))
    if peak > original_peak: result *= original_peak / peak
    with wave.open(str(wav), "wb") as destination:
        destination.setnchannels(1); destination.setsampwidth(2); destination.setframerate(sr)
        destination.writeframes((np.clip(result, -.98, .98) * 32767).astype("<i2").tobytes())
    return {"algorithm":"WORLD analysis/synthesis with preserved spectral envelope and timing", "f0_deviation_scale":.60,"median_voiced_hz":round(median,2),"voiced_std_hz_before":round(float(np.std(f0[voiced])),2),"voiced_std_hz_after":round(float(np.std(controlled[voiced])),2)}

async def main():
    OUT.mkdir(parents=True, exist_ok=True)
    clips = []
    with tempfile.TemporaryDirectory(prefix="paper-commander-") as temp:
        for key, text in DIALOGUE.items():
            mp3 = Path(temp) / (key + ".mp3")
            wav = Path(temp) / (key + ".wav")
            await edge_tts.Communicate(text, VOICE, rate="-10%", pitch="-10Hz", volume="-15%").save(str(mp3))
            subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", str(mp3), "-ar", "22050", "-ac", "1", "-c:a", "pcm_s16le", str(wav)], check=True)
            treatment = restrain_prosody(wav)
            with wave.open(str(wav)) as source:
                duration = source.getnframes() / source.getframerate()
                assert source.getnchannels() == 1 and source.getsampwidth() == 2 and duration > .5
            clips.append({"action": key, "text": text, "file": "res://assets/audio/commander/" + wav.name, "duration_s": round(duration, 4), "sha256": hashlib.sha256(wav.read_bytes()).hexdigest(),"post_processing":treatment})
            print(key, round(duration, 2), flush=True)
        # Keep the installed recordings intact if any network request or
        # speech treatment fails. Publish the complete bank only after all13.
        for key in DIALOGUE: (Path(temp) / (key + ".wav")).replace(OUT / (key + ".wav"))
    (OUT / "manifest.json").write_text(json.dumps({"version": 2, "language": "zh-CN", "speaker_gender": "female", "speaker": VOICE, "delivery": "Concise neutral tactical sentences; news-capable adult female actor, slowed10%, pitch-10Hz and voiced F0 deviation reduced40% for restrained deadpan delivery. Human listening audit not performed.", "provenance": "Microsoft Edge online speech via edge-tts, locally processed with WORLD; no paid request or API key. Provider-generated audio; no CC0 claim.", "sample_rate": 22050, "clips": clips}, ensure_ascii=False, indent=2) + "\n")

if __name__ == "__main__":
    asyncio.run(main())
