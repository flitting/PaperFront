#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Render short, meaningful Mandarin acknowledgements entirely offline.

This isolated build tool links the host's GPLv3+ eSpeak NG library via ctypes.
The game ships authored PCM outputs and license records, never the synthesizer.
Native Mandarin uses no neural model or online provider; upstream eSpeak
consonants also play stored phoneme WAV resources. Outputs are conservatively
GPLv3+, with the exact Ubuntu corresponding source bundled separately.
"""
from __future__ import annotations

import ctypes
import ctypes.util
import hashlib
import json
from pathlib import Path
import subprocess
import wave

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/audio/radio"
SR = 22050
FACTIONS = {
    "kestrel": {"pitch": 44, "range": 38, "voice": "cmn-latn-pinyin+m3"},
    "rivet": {"pitch": 37, "range": 34, "voice": "cmn-latn-pinyin+m3"},
    "iron": {"pitch": 40, "range": 32, "voice": "cmn-latn-pinyin+m3"},
    "sky": {"pitch": 48, "range": 38, "voice": "cmn-latn-pinyin+m3"},
}
DIALOGUE = {
    "kestrel": {"select": "收到，等待命令。", "move": "按令前进。", "attack": "目标确认，开始攻击。", "ready": "准备完毕。", "return": "返航，补充弹药。"},
    "rivet": {"select": "收到，部队待命。", "move": "开始前进。", "attack": "目标锁定，开始攻击。", "ready": "单位准备完毕。", "return": "返航，补充弹药。"},
    "iron": {"select": "检查完毕，等待命令。", "move": "稳步前进。", "attack": "目标确认，准备开火。", "ready": "检查完成，可以出发。", "return": "返航，补充弹药。"},
    "sky": {"select": "收到，等待指令。", "move": "前往目标位置。", "attack": "目标确认，执行攻击。", "ready": "准备完成。", "return": "返航，补充弹药。"},
}


class MandarinSynthesizer:
    """Synchronous native formant synthesis; no audio device is opened."""

    def __init__(self) -> None:
        library_name = ctypes.util.find_library("espeak-ng")
        if not library_name:
            raise RuntimeError("Install eSpeak NG locally before rebuilding; no online fallback is permitted")
        self.lib = ctypes.CDLL(library_name)
        self.blocks: list[np.ndarray] = []
        callback_type = ctypes.CFUNCTYPE(ctypes.c_int, ctypes.POINTER(ctypes.c_short), ctypes.c_int, ctypes.c_void_p)

        def collect(samples, count, _events):
            if samples and count > 0:
                self.blocks.append(np.ctypeslib.as_array(samples, shape=(count,)).copy())
            return 0

        self.callback = callback_type(collect)
        self.lib.espeak_Initialize.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_char_p, ctypes.c_int]
        self.lib.espeak_Initialize.restype = ctypes.c_int
        self.lib.espeak_SetSynthCallback.argtypes = [callback_type]
        self.lib.espeak_SetVoiceByName.argtypes = [ctypes.c_char_p]
        self.lib.espeak_SetVoiceByName.restype = ctypes.c_int
        self.lib.espeak_SetParameter.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_int]
        self.lib.espeak_SetParameter.restype = ctypes.c_int
        self.lib.espeak_Synth.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_uint, ctypes.c_int,
                                         ctypes.c_uint, ctypes.c_uint, ctypes.POINTER(ctypes.c_uint), ctypes.c_void_p]
        self.lib.espeak_Synth.restype = ctypes.c_int
        self.lib.espeak_TextToPhonemes.argtypes = [ctypes.POINTER(ctypes.c_void_p), ctypes.c_int, ctypes.c_int]
        self.lib.espeak_TextToPhonemes.restype = ctypes.c_char_p
        self.lib.espeak_Info.argtypes = [ctypes.POINTER(ctypes.c_char_p)]
        self.lib.espeak_Info.restype = ctypes.c_char_p
        self.lib.espeak_Terminate.argtypes = []
        sample_rate = self.lib.espeak_Initialize(2, 20, None, 0)
        if sample_rate != SR:
            raise RuntimeError(f"Expected 22050Hz native eSpeak PCM, received {sample_rate}")
        self.lib.espeak_SetSynthCallback(self.callback)
        data_path = ctypes.c_char_p()
        self.version = self.lib.espeak_Info(ctypes.byref(data_path)).decode("utf-8")
        self.data_path = Path(data_path.value.decode("utf-8"))
        self.library_name = library_name

    def phonemes(self, text: str, settings: dict) -> list[str]:
        if self.lib.espeak_SetVoiceByName(settings["voice"].encode()) != 0:
            raise RuntimeError("Reviewed native Mandarin pinyin voice is unavailable")
        encoded = ctypes.create_string_buffer(text.encode("utf-8"))
        cursor = ctypes.c_void_p(ctypes.addressof(encoded))
        blocks = []
        for _ in range(32):
            if not cursor.value:
                break
            previous = cursor.value
            value = self.lib.espeak_TextToPhonemes(ctypes.byref(cursor), 1, 0)
            if value:
                blocks.append(value.decode("utf-8"))
            if cursor.value == previous:
                raise RuntimeError("Mandarin phoneme parser did not advance")
        else:
            raise RuntimeError("Mandarin phrase unexpectedly exceeded the clause limit")
        if not blocks or any("(en)" in block for block in blocks):
            raise RuntimeError("Native Mandarin text incorrectly switched to English; do not render this audio")
        return blocks

    def speak(self, text: str, settings: dict) -> np.ndarray:
        if self.lib.espeak_SetVoiceByName(settings["voice"].encode()) != 0:
            raise RuntimeError("Native cmn Mandarin voice unavailable; no online fallback")
        for parameter, value in [(1, 175), (2, 75), (3, settings["pitch"]), (4, settings["range"]), (7, 0)]:
            if self.lib.espeak_SetParameter(parameter, value, 0) != 0:
                raise RuntimeError("eSpeak voice parameter rejected")
        self.blocks.clear()
        encoded = ctypes.create_string_buffer(text.encode("utf-8"))
        identifier = ctypes.c_uint()
        status = self.lib.espeak_Synth(encoded, len(encoded), 0, 1, 0, 1 | 0x1000, ctypes.byref(identifier), None)
        if status != 0 or not self.blocks:
            raise RuntimeError(f"Native offline Mandarin generation failed: {status}")
        return np.concatenate(self.blocks).astype(np.float64) / 32768.0


def soften_voice(x: np.ndarray) -> np.ndarray:
    active = np.flatnonzero(abs(x) > .003)
    if not active.size:
        raise RuntimeError("Synthesizer produced silent speech")
    # Preserve consonants around the first/last detected word, remove long
    # provider-like silence, and add a short consistent comfortable pause.
    padding = round(.055 * SR)
    x = x[max(0, active[0] - padding): min(len(x), active[-1] + padding + 1)]
    # Smooth spectral shelving tames 2-6kHz sibilance while preserving the
    # Mandarin formants and lexical tones; no radio hiss or acknowledgement beep.
    length = len(x)
    padded = np.pad(x, (padding, padding))
    f = np.fft.rfftfreq(len(padded), 1 / SR)
    highpass = (f / np.maximum(f, 70.0)) ** 2
    shelf = .52 + .48 / (1 + (f / 1650.0) ** 4)
    lowpass = 1 / np.sqrt(1 + (f / 4100.0) ** 8)
    padded = np.fft.irfft(np.fft.rfft(padded) * highpass * shelf * lowpass, n=len(padded))
    x = padded[padding: padding + length]
    x -= np.mean(x)
    # Gentle saturation only catches isolated consonant peaks, followed by a
    # fixed output budget. Every faction/action has the same perceived level.
    rms = np.sqrt(np.mean(x * x))
    x = .28 * np.tanh(x * (.09 / max(rms, 1e-12)) / .28)
    frequencies = np.fft.rfftfreq(len(x), 1 / SR)
    x = np.fft.irfft(np.fft.rfft(x) / np.sqrt(1 + (frequencies / 4100.0) ** 8), n=len(x))
    rms = np.sqrt(np.mean(x * x))
    x *= min(.28 / max(np.max(abs(x)), 1e-12), .075 / max(rms, 1e-12))
    edge = min(round(.015 * SR), len(x) // 3)
    fade = .5 - .5 * np.cos(np.linspace(0, np.pi, edge))
    x[:edge] *= fade
    x[-edge:] *= fade[::-1]
    return np.pad(x, (round(.045 * SR), round(.12 * SR)))


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    synth = MandarinSynthesizer()
    clips = []
    try:
        for faction, settings in FACTIONS.items():
            for action, text in DIALOGUE[faction].items():
                phonemes = synth.phonemes(text, settings)
                x = soften_voice(synth.speak(text, settings))
                pcm = np.round(np.clip(x, -1, 1) * 32767).astype("<i2")
                path = OUT / f"{faction}_{action}.wav"
                with wave.open(str(path), "wb") as output:
                    output.setparams((1, 2, SR, 0, "NONE", "not compressed"))
                    output.writeframes(pcm.tobytes())
                frequencies = np.fft.rfftfreq(len(x), 1 / SR)
                power = abs(np.fft.rfft(x)) ** 2
                clips.append({"faction": faction, "action": action, "text": text,
                              "path": "res://" + path.relative_to(ROOT).as_posix(), "duration_s": round(len(pcm) / SR, 6),
                              "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                              "peak_dbfs": round(20 * np.log10(np.max(abs(x))), 3),
                              "rms_dbfs": round(20 * np.log10(np.sqrt(np.mean(x*x))), 3),
                              "energy_above_4khz_percent": round(float(np.sum(power[frequencies >= 4000]) / np.sum(power) * 100), 6),
                              "spoken_words": True, "language": "cmn", "voice_settings": settings,
                              "phoneme_rendering": phonemes,
                              "provenance": {"type": "offline_formant_synthesized_speech", "human_recording": False,
                                             "human_recording_scope": "No newly recorded unit dialogue; upstream eSpeak consonants use GPL phoneme WAV resources",
                                             "upstream_phoneme_waveforms": True,
                                             "provider": "eSpeak NG native Mandarin", "engine_version": synth.version,
                                             "online_service": False, "neural_model": False}})
        dictionary = synth.data_path / "cmn_dict"
        source_folder = ROOT / "tools/source_assets/espeak-ng"
        source_manifest = json.loads((source_folder / "source_download_manifest.json").read_text())
        package_version = subprocess.check_output(["dpkg-query", "-W", "-f=${Version}", "libespeak-ng1"], text=True).strip()
        if package_version != source_manifest["source_version"]:
            raise RuntimeError("Bundled corresponding source must match the installed synthesis package")
        for record in source_manifest["archives"] + [source_manifest["dsc"]]:
            if hashlib.sha256((source_folder / record["file"]).read_bytes()).hexdigest() != record["sha256"]:
                raise RuntimeError("Bundled corresponding source hash mismatch")
        build_inputs = {}
        for name in ["cmn_dict", "phondata", "phonindex", "phontab", "intonations", "lang/sit/cmn", "lang/sit/cmn-Latn-pinyin", "voices/!v/m3"]:
            source = synth.data_path / name
            build_inputs[name] = {"path": str(source), "bytes": source.stat().st_size, "sha256": hashlib.sha256(source.read_bytes()).hexdigest()}
        library_path = Path("/usr/lib/x86_64-linux-gnu/libespeak-ng.so.1").resolve()
        build_inputs["synthesis_library"] = {"path": str(library_path), "bytes": library_path.stat().st_size, "sha256": hashlib.sha256(library_path.read_bytes()).hexdigest()}
        manifest = {"version": 3, "license": "GPL-3.0-or-later", "license_scope": "Generated Mandarin acknowledgement PCM and separate linked generator; authored phrase text is additionally CC0",
                    "generator_license": "GPL-3.0-or-later", "generator": "tools/generate_demo_radio.py",
                    "generator_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                    "origin": "Project-authored short Mandarin phrases rendered by host eSpeak NG native formant synthesis",
                    "engine": {"name": "eSpeak NG", "version": synth.version, "license": "GPL-3.0-or-later",
                               "library": synth.library_name, "package_version": package_version,
                               "dictionary_sha256": hashlib.sha256(dictionary.read_bytes()).hexdigest(), "build_inputs": build_inputs,
                               "source": "https://github.com/espeak-ng/espeak-ng/tree/1.51", "runtime_bundled": False},
                    "license_basis": {"output": "Conservatively distribute generated PCM under GPLv3+ because native Mandarin also plays upstream GPL phoneme WAV resources; do not claim purely original CC0 speech",
                                      "output_source": "https://raw.githubusercontent.com/espeak-ng/espeak-ng/1.51/COPYING",
                                      "dictionary": "Mandarin pronunciations derive from Unicode Unihan; Unicode commercial data permission is retained",
                                      "dictionary_source": "https://raw.githubusercontent.com/espeak-ng/espeak-ng/1.51/dictsource/cmn_list",
                                      "unicode_license": "https://www.unicode.org/license.txt",
                                      "corresponding_source": "tools/source_assets/espeak-ng/",
                                      "source_version": source_manifest["source_version"],
                                      "source_dsc_sha256": source_manifest["dsc"]["sha256"],
                                      "distribution": "Ship the complete source kit, generator, dialogue parameters, manifests and license notices alongside the independent WAV assets"},
                    "format": "mono 22050 Hz signed 16-bit PCM WAV", "voice_quality": "mechanical formant Mandarin; human listening acceptance remains required",
                    "rate": 175, "lowpass_hz": 4100, "high_frequency_shelf": .52,
                    "clips": clips}
        (OUT / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
        print(json.dumps({"clips": len(clips), "seconds": sum(c["duration_s"] for c in clips), "engine": synth.version, "output": str(OUT)}))
    finally:
        synth.lib.espeak_Terminate()


if __name__ == "__main__":
    main()
