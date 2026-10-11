#!/usr/bin/env python3
"""Generate local English unit, commander, and system speech banks.

Generation prerequisites (not runtime dependencies):
    python -m pip install kokoro-onnx==0.4.9 numpy==2.5.0
    python tools/generate_english_audio.py --download-model --generate
    python tools/generate_english_audio.py --validate-only

English speech is synthesized locally with checksum-pinned Kokoro-82M ONNX.
No API key, paid request, or runtime synthesis is used. Chinese radio/commander/system assets are read only. Model weights are cached outside the repository and never shipped.
"""
from __future__ import annotations
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import importlib.metadata
import json
from pathlib import Path
import re
import urllib.request
import wave

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/audio/english'
REPORT = ROOT / 'artifacts/english_voice_generation'
CACHE = Path.home() / '.cache/paper_front_kokoro'
RATE = 22050
MODEL_VERSION = 'Kokoro-82M v1.0 / kokoro-onnx model-files-v1.1 int8'
MODEL_FILES = {
    'kokoro-v1.0.int8.onnx': ('https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.1/kokoro-v1.0.int8.onnx', 'ae315a79b623f244700e4afb9246c46a26066782e049ba174bf3ba433970ee9c'),
    'voices-v1.0.bin': ('https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.1/voices-v1.0.bin', 'bca610b8308e8d99f32e6fe4197e7ec01679264efed0cac9140fe9c29f1fbf7d'),
}
# One fixed base speaker per faction/category, used for every action/variant.
# Voice names identify stock Kokoro voice embeddings, not commissioned actors.
PROFILES = {
    'kestrel/infantry': ('am_michael', 'male', 1.06, 'en-us', 'Composed professional infantry leader'),
    'kestrel/vehicle': ('bm_george', 'male', 1.02, 'en-gb', 'Steady armored vehicle commander'),
    'kestrel/air': ('af_kore', 'female', 1.08, 'en-us', 'Crisp professional pilot'),
    'rivet/infantry': ('am_fenrir', 'male', 1.06, 'en-us', 'Direct heavy-assault infantry leader'),
    'rivet/vehicle': ('am_onyx', 'male', 1.00, 'en-us', 'Deliberate heavy armored commander'),
    'rivet/air': ('am_puck', 'male', 1.08, 'en-us', 'Decisive combat pilot'),
    'iron/infantry': ('af_bella', 'female', 1.02, 'en-us', 'Warm dependable field soldier'),
    'iron/vehicle': ('bm_fable', 'male', 1.00, 'en-gb', 'Practical industrial vehicle commander'),
    'iron/air': ('bf_emma', 'female', 1.03, 'en-gb', 'Calm maintenance-minded pilot'),
    'sky/infantry': ('af_heart', 'female', 1.06, 'en-us', 'Precise advanced-technology infantry specialist'),
    'sky/vehicle': ('af_sarah', 'female', 1.02, 'en-us', 'Focused advanced-technology vehicle operator'),
    'sky/air': ('af_nova', 'female', 1.08, 'en-us', 'Agile advanced-technology pilot'),
}
ANNOUNCER = ('af_aoede', 'female', 1.00, 'en-us', 'Neutral tactical announcer')
# Current v8 manifests deliberately removed several renamed faction lines.
# Restore the missing variant slots with the current faction's English name.
EXTRA_TRANSLATIONS = {
    '长钉步兵，随时帮忙。': 'Long Nail infantry. Ready to help.',
    '长钉步兵，准备好了。': 'Long Nail infantry ready.',
    '长钉扎稳，继续压制！': 'Long Nail holding firm. Keep suppressing!',
    '长钉车组，检查完毕。': 'Long Nail crew. Checks complete.',
    '长钉装甲，整备完成。': 'Long Nail armor ready.',
    '长钉航空，检查正常。': 'Long Nail aviation. Checks normal.',
    '长钉航空，整备完成。': 'Long Nail aviation ready.',
    '天意步兵，感知在线。': 'Skywing infantry. Sensors online.',
    '天意步兵，校准完成。': 'Skywing infantry. Calibration complete.',
    '天意车组，蓄能正常。': 'Skywing crew. Energy storage normal.',
    '天意装甲，校准完成。': 'Skywing armor. Calibration complete.',
    '天意航空，空域在线。': 'Skywing aviation. Airspace online.',
    '标定目标，天意出击。': 'Target designated. Skywing strikes.',
    '天意航空，校准完成。': 'Skywing aviation. Calibration complete.',
    '天意覆盖，保持锁定！': 'Skywing covering. Maintain lock!',
    '建筑准备就绪。': 'Building ready for placement.',
    '建筑已完成。': 'Construction complete.',
    '单位生产完成。': 'Unit ready.',
    '发现敌军。': 'Enemy sighted.',
    '发现大批敌军。': 'Large enemy force detected.',
    '发现敌方基地。': 'Enemy base located.',
    '我方步兵受到攻击。': 'Our infantry are under attack.',
    '我方车辆受到攻击。': 'Our vehicles are under attack.',
    '矿车受到攻击。': 'Harvester under attack.',
    '我方建筑受到攻击。': 'Our building is under attack.',
    '基地受到攻击。': 'Base under attack.',
    '我方部队正在交火。': 'Our forces are engaging the enemy.',
    '我方单位阵亡。': 'Unit lost.',
    '电力不足，请增建电站。': 'Low power. Build more power plants.',
    '电力已恢复。': 'Power restored.',
}
# Missing Skywing source captions use the current faction name.
EXTRA_TRANSLATIONS.update({source.replace('天意', '天翼'): english
                           for source, english in list(EXTRA_TRANSLATIONS.items()) if '天意' in source})


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def write_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + '.tmp')
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')
    temporary.replace(path)


def model_files(cache, download=False):
    cache.mkdir(parents=True, exist_ok=True)
    for name, (url, checksum) in MODEL_FILES.items():
        destination = cache / name
        if destination.exists() and sha256(destination) == checksum:
            continue
        if not download:
            raise RuntimeError(f'Missing verified model file {destination}. Use --download-model.')
        temporary = destination.with_suffix(destination.suffix + '.download')
        with urllib.request.urlopen(url, timeout=120) as response, temporary.open('wb') as output:
            while chunk := response.read(1024 * 1024):
                output.write(chunk)
        if sha256(temporary) != checksum:
            raise RuntimeError('Model checksum mismatch: ' + name)
        temporary.replace(destination)
    return cache / 'kokoro-v1.0.int8.onnx', cache / 'voices-v1.0.bin'


def profile_record(profile):
    voice, gender, tempo, accent, direction = profile
    return {'voice': voice, 'speaker_identity': voice,
            'speaker_id': f'kokoro/{voice}@speed={tempo:.3f}',
            'speaker_gender': gender, 'tempo': tempo, 'accent': accent,
            'direction': direction, 'model': MODEL_VERSION,
            'request_strategy': 'One fixed stock neural speaker for every action and variant; no pitch shifting'}


def specifications():
    from revision_v8_dialogue import specifications as chinese_specs
    translations = {}
    for path in sorted((ROOT / 'data/localization').glob('en_*.json')):
        translations.update(json.loads(path.read_text()))
    translations.update(EXTRA_TRANSLATIONS)
    # Existing keys/text are authoritative. Supplement missing variant slots
    # from the authored dialogue without editing the Chinese source bank.
    radio = {clip['key']: clip for clip in chinese_specs()}
    current = json.loads((ROOT / 'assets/audio/revision_v8/radio/manifest.json').read_text())
    current_keys = {clip['key'] for clip in current['clips']}
    radio.update({clip['key']: clip for clip in current['clips']})
    jobs = []
    def append(bank, clip, profile):
        text = str(clip['text'])
        translated = translations.get(text, text)
        if re.search('[\u3400-\u9fff]', translated):
            raise RuntimeError('Missing spoken English translation: ' + text)
        # Kokoro's punctuation front end accepts ordinary ASCII ellipses.
        translated = translated.replace('…', '...').replace('！', '!')
        item = {key: clip[key] for key in ('key', 'faction', 'category', 'action', 'variant') if key in clip}
        source_text = text.replace('天意', '天翼') if bank == 'radio' and item['key'] not in current_keys else text
        item.update({'bank': bank, 'text': translated, 'source_text': source_text, 'source_text_zh_CN': source_text,
                     'language': 'en', 'spoken_words': True, **profile_record(profile)})
        jobs.append(item)
    for key, clip in sorted(radio.items()):
        append('radio', clip, PROFILES[clip['faction'] + '/' + clip['category']])
    commander = json.loads((ROOT / 'assets/audio/commander/manifest.json').read_text())
    for clip in commander['clips']:
        append('commander', dict(clip, key='commander/' + clip['action'] + '/1', variant=1, category='commander', faction=''), ANNOUNCER)
    system = json.loads((ROOT / 'assets/audio/revision_v8/system/manifest.json').read_text())
    for clip in system['clips']:
        append('system', clip, ANNOUNCER)
    return jobs


def write_wav(path, samples, rate):
    import numpy as np
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix('.wav.tmp')
    with wave.open(str(temporary), 'wb') as stream:
        stream.setnchannels(1)
        stream.setsampwidth(2)
        stream.setframerate(rate)
        stream.writeframes(np.rint(np.clip(samples, -.98, .98) * 32767).astype('<i2').tobytes())
    temporary.replace(path)
    # Keep Godot's import lossless and do not normalize or trim speech twice.
    resource = 'res://' + path.relative_to(ROOT).as_posix()
    imported = f'res://.godot/imported/{path.name}-{hashlib.md5(resource.encode()).hexdigest()}.sample'
    config = Path(str(path) + '.import')
    if not config.exists():
        config.write_text(f'[remap]\n\nimporter="wav"\ntype="AudioStreamWAV"\npath="{imported}"\n\n[deps]\n\nsource_file="{resource}"\ndest_files=["{imported}"]\n\n[params]\n\nforce/8_bit=false\nforce/mono=false\nforce/max_rate=false\nforce/max_rate_hz={rate}\nedit/trim=false\nedit/normalize=false\nedit/loop_mode=0\nedit/loop_begin=0\nedit/loop_end=-1\ncompress/mode=0\n')


def process_voice(samples, rate, is_radio):
    import numpy as np
    samples = np.asarray(samples, dtype=np.float64).ravel()
    if not np.isfinite(samples).all():
        raise RuntimeError('Non-finite speech samples')
    samples -= samples.mean()
    active = np.flatnonzero(np.abs(samples) > max(np.max(np.abs(samples)) * .006, .0004))
    if not len(active):
        raise RuntimeError('Silent generated speech')
    samples = samples[max(0, active[0] - round(rate * .025)):min(len(samples), active[-1] + round(rate * .10))]
    frequency = np.fft.rfftfreq(len(samples), 1 / rate)
    band = (1 - np.exp(-(frequency / (105 if is_radio else 70)) ** 4)) * np.exp(-(frequency / (4700 if is_radio else 7000)) ** 6)
    samples = np.fft.irfft(np.fft.rfft(samples) * band, len(samples))
    if rate != RATE:
        samples = np.interp(np.arange(round(len(samples) * RATE / rate)) * rate / RATE, np.arange(len(samples)), samples)
    # Mild compression and headroom, with untouched pitch and formants.
    samples = np.tanh(samples * 1.1)
    samples -= samples.mean()
    samples *= (.53 if is_radio else .60) / max(np.max(np.abs(samples)), 1e-12)
    attack, release = round(RATE * .002), round(RATE * .014)
    samples[:attack] *= np.linspace(0, 1, attack)
    samples[-release:] *= np.linspace(1, 0, release)
    return samples


def wav_record(path):
    import numpy as np
    with wave.open(str(path)) as stream:
        rate, channels, width, frames = stream.getframerate(), stream.getnchannels(), stream.getsampwidth(), stream.getnframes()
        if (rate, channels, width) != (RATE, 1, 2):
            raise RuntimeError('Incorrect speech PCM format: ' + str(path))
        signal = np.frombuffer(stream.readframes(frames), dtype='<i2').astype(np.float64) / 32768
    duration = frames / rate
    rms, peak = float(np.sqrt(np.mean(signal ** 2))), float(np.max(np.abs(signal)))
    if not .12 < duration < 15 or rms < .006 or peak >= .98:
        raise RuntimeError(f'Invalid speech duration or level: {path} ({duration:.3f}s, RMS {rms:.5f}, peak {peak:.4f})')
    return dict(file='res://' + path.relative_to(ROOT).as_posix(), duration_s=round(duration, 4),
                sample_rate=rate, channels=channels, sample_width=width, sha256=sha256(path),
                audio_checks={'rms': round(rms, 6), 'peak': round(peak, 6), 'clipped_samples': int(np.sum(np.abs(signal) >= .98))})


def generate_english(jobs, cache, force, workers):
    import onnxruntime as ort
    from kokoro_onnx import Kokoro
    model, voices = model_files(cache)
    options = ort.SessionOptions()
    options.intra_op_num_threads = 4
    options.inter_op_num_threads = 1
    options.execution_mode = ort.ExecutionMode.ORT_SEQUENTIAL
    options.log_severity_level = 3
    session = ort.InferenceSession(str(model), sess_options=options, providers=['CPUExecutionProvider'])
    # The checksum-pinned 2026 export has float speed even though wrapper
    # 0.4.9 assumes int32 for input_ids models. Read graph types explicitly.
    import numpy as np
    class TypedKokoro(Kokoro):
        def _create_audio(self, phonemes, voice, speed):
            tokens = self.tokenizer.tokenize(phonemes)
            if not tokens or len(tokens) > 510:
                raise RuntimeError('Invalid speech phoneme count')
            inputs = {item.name: item.type for item in self.sess.get_inputs()}
            token_name = 'input_ids' if 'input_ids' in inputs else 'tokens'
            style = np.asarray(voice[min(len(tokens), len(voice) - 1)], dtype=np.float32).reshape(1, 256)
            speed_dtype = np.float32 if inputs['speed'] == 'tensor(float)' else np.int32
            output = self.sess.run(None, {token_name: np.asarray([[0, *tokens, 0]], dtype=np.int64),
                                          'style': style, 'speed': np.asarray([speed], dtype=speed_dtype)})[0]
            return np.asarray(output).ravel(), 24000
    tts = TypedKokoro.from_session(session, str(voices))
    # espeak changes shared language state, so phonemize serially before
    # parallel ONNX inference; each voice keeps the intended accent.
    phonemes = {job['key']: tts.tokenizer.phonemize(job['text'], job['accent']) for job in jobs}
    previous = {}
    for bank in {job['bank'] for job in jobs}:
        path = OUT / bank / 'manifest.json'
        if path.exists():
            previous.update({clip['key']: clip for clip in json.loads(path.read_text())['clips']})
    def generate(job):
        bank = job['bank']
        path = OUT / bank / (job['key'].replace('/', '_') + '.wav' if bank == 'radio' else job['action'] + '.wav')
        descriptor = {k: v for k, v in job.items() if k not in ('direction',)}
        descriptor['pipeline_version'] = 'typed-onnx-v1-padding-only'
        source_hash = hashlib.sha256(json.dumps(descriptor, sort_keys=True, ensure_ascii=False).encode()).hexdigest()
        old = previous.get(job['key'], {})
        if not force and path.exists() and old.get('source_sha256') == source_hash and old.get('sha256') == sha256(path):
            return old
        audio, rate = tts.create(phonemes[job['key']], voice=job['voice'], speed=job['tempo'], is_phonemes=True, trim=False)
        write_wav(path, process_voice(audio, rate, bank == 'radio'), RATE)
        record = {key: value for key, value in job.items() if key != 'bank'}
        record.update(wav_record(path))
        record.update(source_sha256=source_hash,
                      provenance={'type': 'synthesized_speech', 'provider': 'Local CPU inference; no network or paid API',
                                  'model': MODEL_VERSION, 'model_license': 'Apache-2.0', 'inference_wrapper': 'kokoro-onnx',
                                  'wrapper_version': importlib.metadata.version('kokoro-onnx'), 'wrapper_license': 'MIT',
                                  'model_sha256': MODEL_FILES[model.name][1], 'voices_sha256': MODEL_FILES[voices.name][1],
                                  'human_recording': False, 'stock_voice': job['voice'],
                                  'post_processing': {'pitch_shift': 0, 'sample_rate': RATE, 'radio_band_hz': [105, 4700] if bank == 'radio' else [70, 7000],
                                                      'peak_target': .53 if bank == 'radio' else .60, 'trim_padding_only': True}})
        print(f"ENGLISH {job['key']} {record['duration_s']:.2f}s", flush=True)
        return record
    # Only pure inference/DSP and independent file writes run concurrently.
    if workers > 1:
        with ThreadPoolExecutor(max_workers=workers) as pool:
            records = list(pool.map(generate, jobs))
    else:
        records = [generate(job) for job in jobs]
    for bank in sorted({job['bank'] for job in jobs}):
        bank_records = [record for record in records if any(job['key'] == record['key'] and job['bank'] == bank for job in jobs)]
        manifest = {'version': 1, 'language': 'en', 'sample_rate': RATE, 'format': 'PCM signed 16-bit mono WAV',
                    'license': 'Synthetic project dialogue generated locally with Apache-2.0 Kokoro weights; no human recording or CC0 claim.',
                    'speech_notice': 'Actual spoken English, generated offline. Fixed distinct stock neural voices; no API key required to play.',
                    'dialogue_source': 'Current Chinese audio manifests and data/localization/en_*.json, with missing faction variants restored.',
                    'regenerate': 'python tools/generate_english_audio.py --download-model --generate',
                    'profiles': {key: profile_record(value) for key, value in PROFILES.items()} if bank == 'radio' else {'announcer': profile_record(ANNOUNCER)},
                    'clips': sorted(bank_records, key=lambda record: record['key'])}
        write_json(OUT / bank / 'manifest.json', manifest)
    return records


def validate():
    manifests = [OUT / bank / 'manifest.json' for bank in ('radio', 'commander', 'system')]
    expected_counts = [300, 13, 2]
    summary = []
    originals = json.loads((ROOT / 'assets/audio/revision_v8/radio/manifest.json').read_text())['clips']
    chinese_hashes = {clip['sha256'] for clip in originals}
    for source in ['assets/audio/commander/manifest.json', 'assets/audio/revision_v8/system/manifest.json']:
        chinese_hashes.update(clip['sha256'] for clip in json.loads((ROOT / source).read_text())['clips'])
    for path, count in zip(manifests, expected_counts):
        manifest = json.loads(path.read_text())
        clips = manifest['clips']
        if len(clips) != count or len({clip['key'] for clip in clips}) != count:
            raise RuntimeError('Incorrect or duplicate bank entries: ' + str(path))
        for clip in clips:
            if not str(clip.get('source_text', '')).strip():
                raise RuntimeError('Missing source-language subtitle: ' + clip['key'])
            resource = clip['file']
            if not resource.startswith('res://'):
                raise RuntimeError('Invalid audio resource path')
            record = wav_record(ROOT / resource.removeprefix('res://'))
            if record['sha256'] in chinese_hashes:
                raise RuntimeError('English audio reuses a Chinese recording: ' + clip['key'])
            if record['sha256'] != clip['sha256'] or abs(record['duration_s'] - clip['duration_s']) > .00011:
                raise RuntimeError('Audio manifest mismatch: ' + clip['key'])
            if path.is_relative_to(OUT) and re.search('[\u3400-\u9fff]', clip['text']):
                raise RuntimeError('English subtitle contains Chinese: ' + clip['key'])
        if path.parent.name == 'radio':
            english_by_key = {clip['key']: clip for clip in clips}
            for original in originals:
                if original['key'] not in english_by_key or english_by_key[original['key']]['source_text'] != original['text']:
                    raise RuntimeError('Current Chinese radio key/caption was not preserved')
            for clip in clips:
                if clip['key'] not in {original['key'] for original in originals} and any(old in clip['source_text'] for old in ['天意', '铁钉同盟']):
                    raise RuntimeError('Restored caption uses a retired faction name')
            slots = {(clip['faction'], clip['category'], clip['action'], clip['variant']) for clip in clips}
            for profile in PROFILES:
                faction, category = profile.split('/')
                for action in ('select', 'move', 'attack', 'ready', 'return', 'combat', 'under_attack', 'death'):
                    for variant in range(1, 5 if action == 'death' else 4):
                        if (faction, category, action, variant) not in slots:
                            raise RuntimeError('Missing faction/category/action/variant')
                speakers = {clip['speaker_id'] for clip in clips if (clip['faction'], clip['category']) == (faction, category)}
                if len(speakers) != 1:
                    raise RuntimeError('Speaker identity changes across a profile')
        summary.append({'manifest': 'res://' + path.relative_to(ROOT).as_posix(), 'clips': len(clips),
                        'total_duration_s': round(sum(clip['duration_s'] for clip in clips), 3),
                        'min_duration_s': min(clip['duration_s'] for clip in clips), 'max_duration_s': max(clip['duration_s'] for clip in clips)})
    report = {'pass': True, 'checks': ['Complete slot coverage', 'Unique keys', 'PCM 22050 Hz mono 16-bit', 'Manifest SHA-256 matches WAV',
                                     'Actual duration matches manifest', 'Non-silent audio', 'No clipped samples', 'Fixed speaker identity per profile',
                                     'English text contains no Chinese', 'Original Chinese radio keys/captions preserved', 'Restored captions use current faction names', 'English recordings do not reuse Chinese WAVs'],
              'listening_audit': 'Objective checks only; no claim of a human listening audit.', 'banks': summary}
    write_json(REPORT / 'validation.json', report)
    print(json.dumps(report, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--generate', action='store_true')
    parser.add_argument('--validate-only', action='store_true')
    parser.add_argument('--download-model', action='store_true')
    parser.add_argument('--force', action='store_true')
    parser.add_argument('--workers', type=int, default=2, choices=range(1, 5))
    parser.add_argument('--cache', type=Path, default=CACHE)
    parser.add_argument('--banks', nargs='+', choices=['radio', 'commander', 'system'], default=['radio', 'commander', 'system'])
    args = parser.parse_args()
    if args.download_model:
        model_files(args.cache, download=True)
    if args.generate:
        jobs = [job for job in specifications() if job['bank'] in args.banks]
        if jobs:
            generate_english(jobs, args.cache, args.force, args.workers)
    if args.validate_only or (args.generate and len(args.banks) == 3):
        validate()
    elif not args.generate and not args.download_model:
        parser.print_help()


if __name__ == '__main__':
    main()
