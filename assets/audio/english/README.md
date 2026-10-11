# English speech assets

These are actual English recordings synthesized locally with **Kokoro-82M v1.0**, using twelve fixed stock neural speakers for faction radio and a separate neutral female announcer for commander and system alerts. Each faction/category keeps the same speaker for every action and variant. No Chinese recording is relabeled or overwritten.

The banks contain 300 radio clips (four factions × three categories × seven ordinary actions × three variants, plus four death variants per profile), 13 commander alerts, and two power announcements. Existing instrumental end-game audio remains unchanged. The radio bank retains all 285 installed Chinese-bank keys and fills the 15 missing ordinary-action slots from the authored dialogue.

`text` is the spoken English line. `source_text` supplies the Chinese caption independently of the chosen spoken language. WAVs are 22,050 Hz, mono, signed 16-bit PCM, with speech-preserving filtering, mild compression, and headroom. The radio filter covers roughly 105–4,700 Hz. Pitch and formants are not shifted. These are synthetic stock voices, not recordings commissioned from actors or cloned from user-provided speech.

The game uses the delivered WAVs offline. Python, the model, network access, and API keys are unnecessary for playback. Model weights are cached outside the repository in `~/.cache/paper_front_kokoro` and are not included in the game.

To regenerate:

```bash
python -m pip install kokoro-onnx==0.4.9 numpy==2.5.0
python tools/generate_english_audio.py --download-model --generate
python tools/generate_english_audio.py --validate-only
```

Matching complete-bank entries are cached by source and WAV hashes. `--force` regenerates audio. `--banks radio commander system` selects banks; `--workers 1` serializes inference. English synthesis uses no paid service. The generator adapts token and speed types to the pinned ONNX graph instead of relying on the older wrapper's incorrect speed-type assumption.

## Sources and licensing

- [Kokoro-82M upstream model](https://huggingface.co/hexgrad/Kokoro-82M): Apache-2.0.
- [Kokoro stock voice descriptions](https://huggingface.co/hexgrad/Kokoro-82M/blob/main/VOICES.md).
- [Kokoro ONNX inference wrapper](https://github.com/thewh1teagle/kokoro-onnx): MIT.
- [Checksum-pinned ONNX release](https://github.com/thewh1teagle/kokoro-onnx/releases/tag/model-files-v1.1).

The model and wrapper license notices are retained in `licenses/`. Generation-only dependencies include ONNX Runtime, NumPy, and the wrapper's phonemizer/espeak frontend; their code is not bundled with the game's WAV assets. The project authors its dialogue and applies local DSP. No claim is made that these synthetic outputs are human performances or CC0 assets. Source URLs, model hashes, package versions, and original input-manifest hashes are recorded in `provenance.json`; individual output hashes and durations are in each manifest.

Validation checks every WAV's format, duration, amplitude, hash, unique key, complete slot coverage, source-caption presence, and profile speaker consistency. These objective checks do not constitute a claim of a human listening audit.
