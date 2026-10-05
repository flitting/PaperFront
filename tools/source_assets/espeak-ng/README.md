# eSpeak NG Mandarin audio corresponding source kit

This directory accompanies the project's GPL-3.0-or-later Mandarin acknowledgement WAVs. Preserve and distribute the whole kit and `assets/audio/licenses/` with those audio files. It contains the exact Ubuntu corresponding source, source/data notices, our linked generator, authored dialogue and parameters, audited phonemes, raw output WAVs, and SHA-256 manifests. The game itself only plays WAVs and does not link or bundle a synthesis engine application.

## Exact source and verification

The generation host has `libespeak-ng1` and `espeak-ng-data` version **1.51+dfsg-12build1**. All three source files were fetched from the [official Ubuntu archive](https://archive.ubuntu.com/ubuntu/pool/main/e/espeak-ng/):

- `espeak-ng_1.51+dfsg-12build1.dsc`
- `espeak-ng_1.51+dfsg.orig.tar.gz` (complete upstream source and phoneme resources)
- `espeak-ng_1.51+dfsg-12build1.debian.tar.xz` (complete Ubuntu/Debian packaging and patches)

Both archives match every SHA-256 and byte count in the DSC. `source_download_manifest.json` records URLs, versions, sizes and hashes. The original clear-signed DSC is retained; its signature has not been asserted locally verified. `source_kit_manifest.json` pins the generated tool, native library and all synthesis data inputs, and confirms all fifteen WAV resources directly named by `phsource/ph_cmn` exist in the complete upstream archive. The source archives also contain all inherited phoneme tables and vowel/formant resources.

## License scope

Native eSpeak Mandarin combines formant synthesis with stored upstream phoneme WAV resources. We therefore **conservatively license the generated Chinese PCM and separate linked generator GPL-3.0-or-later**, rather than assume the output is wholly original CC0. Original acknowledgement phrase text is additionally CC0. Upstream eSpeak/data copyright and GPL notices remain intact; the Unicode pronunciation source notice is included. `COPYING`, `DEBIAN_COPYRIGHT.txt`, and `UNICODE-LICENSE.txt` contain the terms.

GPL permits commercial redistribution with its conditions, including preserving notices and delivering corresponding source. This is the project's conservative distribution choice, not a separate supplier output authorization. Its scope is these standalone audio assets and generator; no statement here relicenses the other game code or artwork. Do not impose additional restrictions on the GPL audio or remove source access when packaging it.

## Rebuild

On a host with the matching native eSpeak package and Mandarin data, Python 3 and NumPy:

```bash
# Recreate the source archives' patched upstream tree, if needed.
dpkg-source -x espeak-ng_1.51+dfsg-12build1.dsc espeak-ng-source

# Place this entire directory at tools/source_assets/espeak-ng in a working
# project, and project/generate_demo_radio.py at tools/generate_demo_radio.py.
OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1 python3 tools/generate_demo_radio.py
```

The generator uses **cmn-latn-pinyin+m3**, with explicit reviewed pitch/range values and rate 175. Every phrase is converted to native Mandarin phonemes first; English language switches cause generation to fail. This avoids a defect in the installed default `cmn` voice, which can read internally generated pinyin and tone numbers as English. The return phrase uses unambiguous “返航，补充弹药。” to avoid the default multi-reading of 给 in 补给. Each final PCM file is in `project/radio/` and its identity is in `project/generated_audio_manifest.json`.

The generator is GPLv3+ source code, with the preferred editable text and synthesis/postprocessing parameters included. The original eSpeak build instructions, complete dictionary/formant/phoneme source and packaging recipe are in the checked source archives. No account, online speech service, neural voice database, or purchased license is required. Mechanical Mandarin listening quality remains a human acceptance item.

## Release packaging

Copy this entire directory to an accessible `GPL_AUDIO_SOURCE/espeak-ng/` beside the release, and copy `assets/audio/licenses/` to `GPL_AUDIO_SOURCE/licenses/`. Keep the generated radio manifest and this README accessible. Distribute this source companion with any package carrying `assets/audio/radio/*.wav`; do not replace it with only a URL to upstream. The raw audio in `project/radio/` stays directly accessible for recipients to edit and redistribute under GPLv3+.
