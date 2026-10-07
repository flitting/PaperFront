#!/usr/bin/env python3
"""Create v8 Mandarin radio and individually designed sound effects.

python tools/generate_revision_v8_audio.py --generate
python tools/generate_revision_v8_audio.py --validate-only

Reads OPENROUTER_API_KEY from the environment without writing it anywhere.
Paid requests are cached before processing. HTTP 402 or an explicit provider
insufficient-credit response stops ALL new paid requests and writes a pause
record. Resume only after the user confirms recharge, with --resume-paid.
The game needs neither network access nor an API key to play the delivered WAVs.
"""
from __future__ import annotations
import argparse
import base64
from concurrent.futures import ThreadPoolExecutor, as_completed
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import threading
import time
import urllib.error
import urllib.request
import wave
import numpy as np
from revision_v8_dialogue import PROFILES, FIXED_SPEAKERS, specifications

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/audio/revision_v8'
REPORT = ROOT / 'artifacts/revision_v8_audio'
RAW = REPORT / 'raw'
PAUSE = REPORT / 'credit_pause.json'
TTS_MODEL = 'microsoft/mai-voice-2.1'
SFX_MODEL = 'bytedance-seed/seed-audio-1-0'
MUSIC_MODEL = 'google/lyria-3-pro-preview'
SR_VOICE, SR_SFX = 22050, 44100
STOP_PAID = threading.Event()
WRITE_LOCK = threading.Lock()

# Each family has a separate authored acoustic brief. Three variants are actual
# independent model generations, not pitch changes of a single recorded sound.
SFX = {
    'fire_machine_gun': (1.15, 'A close military machine gun firing one tight four-round burst with rapid distinct dry cracks, lower mechanical cycling and short outdoor reflections. No ongoing firing after the burst.'),
    'fire_rifle': (.75, 'One isolated infantry rifle shot: a dry ballistic crack with a light low thud, quiet bolt action and tiny outdoor tail.'),
    'fire_anti': (1.05, 'One isolated infantry anti-armor launcher firing: a strong compact pressure pop followed by rushing expelled gases and a low smoky tail.'),
    'fire_cannon': (2.0, 'One isolated heavy tank cannon firing in an open field: an immediate sharp pressure crack, powerful deep muzzle thump and short outdoor gas and echo tail.'),
    'fire_artillery': (2.6, 'One isolated large field artillery gun firing: a weighty deep concussion, hard pressure crack, vibrating gun carriage and a rolling outdoor muzzle gas tail.'),
    'fire_air': (.95, 'An aircraft autocannon fires one short three-round burst: tight dry rapid cannon cracks with mechanical vibration and a short air tail, no airplane passby.'),
    'impact_small': (1.2, 'One small shell hitting dry soil: a sharp close impact, compact low explosion puff, a few grains of earth scattering and settling.'),
    'impact_medium': (2.0, 'One tank shell exploding on earth: forceful sharp initial blast, a deep ground thump, gritty soil and rock fragments scattering with a decaying dusty rumble.'),
    'impact_large': (2.8, 'One large artillery shell exploding in dirt: sudden broad low concussion, hard pressure snap, expanding dusty rumble and scattered falling soil and stone.'),
    'death_building': (3.2, 'A medium industrial battlefield building is destroyed in one explosion: a big low blast, cracking structure and roof supports, uneven masonry collapse, long soft gritty falling rubble tail.'),
    'death_vehicle': (2.5, 'A tank destroyed in one ammo detonation: dense low blast, sharp armor plate fracture and metal panels flying, irregular rattling chunks falling to the ground and a dying mechanical groan.'),
    'death_infantry': (.55, 'A brief cloth and field equipment collapse onto soil: soft heavy body thud, a small metallic gear clatter. No voice, no breathing, no gunshot, no gore.'),
    'deploy_building': (2.3, 'A compact battlefield building unfolds and locks in place: several heavy panel hinges open in sequence, mechanical servo strain, thick metal latches engage, final solid settling clunk. No chime.'),
    'construct_building': (1.4, 'A short practical workshop construction sequence: a few hammer impacts, heavy support fitting into its socket, bolts ratcheting tight, brief low mechanical settling. No chime.'),
    'bomb_release': (.8, 'One aircraft bomb release mechanism: short heavy rack latch click, quiet servo release and a brief airy falling whoosh. No explosion, no aircraft engine.'),
    'rearm': (1.0, 'Short mechanical vehicle ammunition rearming: metal ammunition rack slides in, cartridge clips latch sequentially, one final solid loading clunk. No chime or voice.'),
}

MUSIC = {
    'menu': 'Generate an original instrumental warm calm strategy-game menu soundtrack, 64 seconds duration, gentle piano and warm orchestral strings, relaxed 80 BPM, no vocals, no lyrics, no speech, no sound effects. A beautiful clear soft melody, subtle restrained brushed percussion, optimistic and thoughtful, a consistent loopable music bed with matching beginning and end. No reference to existing artists or songs.',
    'battle_intense': 'Compose a completely original 64-second instrumental high-intensity battle cue for a paper tabletop real-time strategy game. Passionate heroic urgency, driving rhythmic low strings, muscular low brass, snare rolls and deep orchestral tom percussion, a forceful minor-key motif developing through 8-bar phrases. 128 beats per minute, D minor, energetic steady momentum with focused tactical tension and confident resolve. Rich cinematic orchestral game music, lively instrumental detail rather than a single drone. No vocals, no choir, no speech, no weapon effects, no existing tune references. Keep a continuous strong rhythmic bed throughout with matching loopable beginning and ending; no long fadeout, no silence or finale. Avoid piercing highs and leave a clear midrange opening for military radio voices and combat effects.',
    'battle_engaged': 'Compose a completely original 64-second instrumental moderately engaged battle cue for a paper tabletop real-time strategy game. Focused forward tactical motion rather than an all-out climax: rhythmic low strings, warm woodwind responses, restrained brass accents, measured hand drums and soft snare pulse. A memorable coherent minor-key motif, 104 beats per minute, D minor with hopeful harmonic turns. Detailed natural orchestral game soundtrack, alert and purposeful but less dense and less aggressive than a very intense battle score. No vocals, no choir, no speech, no weapon or explosion effects, no artist or existing tune references. Keep a steady complete instrumental arrangement and a musically loopable matching beginning and end without a long fade or finale. Preserve substantial headroom and clear midrange space for Mandarin radio dialogue and combat sound effects.',
}

class CreditPause(RuntimeError):
    pass

def safe_message(value):
    value=str(value)
    secret=os.environ.get('OPENROUTER_API_KEY','')
    if secret:value=value.replace(secret,'[REDACTED]')
    return re.sub(r'sk-(?:or-v1-)?[A-Za-z0-9_-]{16,}','[REDACTED]',value)

def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + '.tmp')
    temporary.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n')
    temporary.replace(path)

def fetch_json(endpoint):
    request = urllib.request.Request('https://openrouter.ai/api/v1/' + endpoint,
            headers={'Authorization': 'Bearer ' + os.environ['OPENROUTER_API_KEY']})
    with urllib.request.urlopen(request, timeout=20) as response:
        return json.load(response)

def credits_usage():
    data = fetch_json('credits')['data']
    return float(data['total_usage']), float(data['total_credits']) - float(data['total_usage'])

def pause_credit(status, message):
    STOP_PAID.set()
    with WRITE_LOCK:
        write_json(PAUSE, {'status': 'AWAITING_USER_RECHARGE', 'http_status': status,
                          'reason': message[:220], 'new_paid_requests_paused': True,
                          'resume': 'Only after explicit user recharge confirmation: --resume-paid'})
    raise CreditPause('OpenRouter credits insufficient; paid production paused pending user response.')

def request_pcm(name, payload):
    if STOP_PAID.is_set() or PAUSE.exists():
        raise CreditPause('Related production paused while awaiting user recharge confirmation.')
    source_hash = hashlib.sha256(json.dumps(payload, ensure_ascii=False, sort_keys=True).encode()).hexdigest()
    meta_path, pcm_path = RAW / (name + '.json'), RAW / (name + '.pcm')
    if pcm_path.exists() and meta_path.exists():
        metadata = json.loads(meta_path.read_text())
        if metadata['request_sha256'] == source_hash:
            raw = pcm_path.read_bytes()
            if hashlib.sha256(raw).hexdigest() == metadata['raw_sha256']:
                return raw, metadata
    if STOP_PAID.is_set() or PAUSE.exists():
        raise CreditPause('No new requests while awaiting recharge.')
    request = urllib.request.Request('https://openrouter.ai/api/v1/audio/speech',
        data=json.dumps(payload, ensure_ascii=False).encode(),
        headers={'Authorization': 'Bearer ' + os.environ['OPENROUTER_API_KEY'],
                 'Content-Type': 'application/json'}, method='POST')
    for attempt in range(3):
        if STOP_PAID.is_set() or PAUSE.exists():
            raise CreditPause('No new requests while awaiting recharge.')
        try:
            with urllib.request.urlopen(request, timeout=65) as response:
                raw = response.read()
                content_type = response.headers.get('Content-Type', '')
                generation_id = response.headers.get('X-Generation-Id', '')
            if 'audio/pcm' not in content_type:
                raise RuntimeError(f'Expected raw PCM, received {content_type}')
            rate = int(re.search(r'rate=(\d+)', content_type).group(1)) if 'rate=' in content_type else 24000
            channels = int(re.search(r'channels=(\d+)', content_type).group(1)) if 'channels=' in content_type else 1
            if len(raw) < rate * channels // 10 or len(raw) % (2 * channels):
                raise RuntimeError('Corrupt or empty PCM response')
            metadata = {'request': payload, 'request_sha256': source_hash,
                        'raw_sha256': hashlib.sha256(raw).hexdigest(),
                        'source_sample_rate': rate, 'source_channels': channels,
                        'generation_id': generation_id,
                        'source_duration_s': round(len(raw) / (2 * rate * channels), 4),
                        'content_type': content_type}
            pcm_path.write_bytes(raw)
            write_json(meta_path, metadata)
            return raw, metadata
        except urllib.error.HTTPError as exc:
            body = exc.read().decode(errors='replace')
            try:
                message = safe_message(json.loads(body).get('error', {}).get('message', ''))
            except (ValueError, AttributeError):
                message = 'Provider request failed'
            if exc.code == 402 or 'insufficient credit' in message.lower() or 'insufficient balance' in message.lower():
                pause_credit(exc.code, message)
            if exc.code not in (429, 500, 502, 503, 504) or attempt == 2:
                raise RuntimeError(f'Speech provider HTTP {exc.code}: {message[:180]}') from None
            time.sleep(1.5 * (attempt + 1))
        except (TimeoutError, urllib.error.URLError):
            if attempt == 2:
                raise
            time.sleep(1.5 * (attempt + 1))

def prepare_raw(raw, metadata, sample_rate, voice=False):
    samples = np.frombuffer(raw, dtype='<i2').reshape(-1, metadata['source_channels']).astype(float) / 32768
    samples = samples.mean(axis=1)
    samples -= samples.mean()
    # Keep a small natural leading edge. Remove provider-generated empty padding
    # while retaining the audible release/rumble tail and never trimming words.
    threshold = max(np.max(np.abs(samples)) * (.007 if voice else .004), .0004)
    active = np.flatnonzero(np.abs(samples) > threshold)
    if not len(active):
        raise RuntimeError('Silent audio response')
    src_rate = metadata['source_sample_rate']
    begin = max(0, int(active[0]) - round(src_rate * .025))
    end = min(len(samples), int(active[-1]) + round(src_rate * (.1 if voice else .18)))
    samples = samples[begin:end]
    # A subtle radio band preserves natural speech and makes mixed calls clear.
    # Sound effects retain their full bass and attack spectrum.
    frequency = np.fft.rfftfreq(len(samples), 1 / src_rate)
    spectrum = np.fft.rfft(samples)
    if voice:
        spectrum *= (1 - np.exp(-(frequency / 105) ** 4)) * np.exp(-(frequency / 4700) ** 6)
    else:
        spectrum *= (1 - np.exp(-(frequency / 26) ** 4)) * np.exp(-(frequency / 11000) ** 6)
    samples = np.fft.irfft(spectrum, len(samples))
    if src_rate != sample_rate:
        samples = np.interp(np.arange(round(len(samples) * sample_rate / src_rate)) * src_rate / sample_rate,
                            np.arange(len(samples)), samples)
    return master(samples, sample_rate, .66 if voice else .76)

def master(samples, rate, peak, loop=False):
    samples = np.asarray(samples, dtype=float)
    samples -= samples.mean()
    samples = np.tanh(samples * 1.1)
    samples -= samples.mean()
    samples *= peak / max(np.max(np.abs(samples)), 1e-12)
    if not loop:
        attack = min(round(rate * .001), len(samples) // 8)
        release = min(round(rate * .014), len(samples) // 8)
        samples[:attack] *= np.linspace(0, 1, attack)
        samples[-release:] *= np.linspace(1, 0, release)
    else:
        # Cyclic FFT-generated beds are periodic; align the last sample with
        # the first through a 5 ms linear distributed boundary correction.
        n = round(rate * .005)
        samples[-n:] += np.linspace(0, samples[0] - samples[-1], n)
    return samples

def write_wav(path, samples, rate):
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), 'wb') as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(rate)
        output.writeframes(np.rint(samples * 32767).astype('<i2').tobytes())
    # Explicit PCM imports avoid Godot's lossy QOA default and stale format
    # assumptions. The editor fills import UIDs without changing this policy.
    res = 'res://' + path.relative_to(ROOT).as_posix()
    imported = f'res://.godot/imported/{path.name}-{hashlib.md5(res.encode()).hexdigest()}.sample'
    import_path = Path(str(path) + '.import')
    if not import_path.exists():
        import_path.write_text(f'[remap]\n\nimporter="wav"\ntype="AudioStreamWAV"\npath="{imported}"\n\n[deps]\n\nsource_file="{res}"\ndest_files=["{imported}"]\n\n[params]\n\nforce/8_bit=false\nforce/mono=false\nforce/max_rate=false\nforce/max_rate_hz={rate}\nedit/trim=false\nedit/normalize=false\nedit/loop_mode=0\nedit/loop_begin=0\nedit/loop_end=-1\ncompress/mode=0\n')

def wav_record(path):
    with wave.open(str(path)) as wav:
        return {'file': 'res://' + path.relative_to(ROOT).as_posix(),
                'duration_s': round(wav.getnframes() / wav.getframerate(), 4),
                'sample_rate': wav.getframerate(), 'channels': wav.getnchannels(),
                'sample_width': wav.getsampwidth(),
                'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}

def voice_job(spec):
    name = spec['key'].replace('/', '_')
    model=spec.get('model',TTS_MODEL)
    payload = {'model': model, 'input': spec['text'], 'voice': spec['voice'],
               'response_format': 'pcm'}
    if model.startswith('x-ai/'):
        payload['provider']={'options':{'xai':{'language':'zh'}}}
    cache_name='fixed_speaker_'+name
    accepted_report=REPORT/'speaker_identity_revision/confirmed_repairs.json'
    if accepted_report.exists() and spec['action']!='death':
        for record in json.loads(accepted_report.read_text()).get('repairs',[]):
            if record.get('key')!=spec['key'] or not record.get('pass'):continue
            candidate=f'repair_v9_{int(record["attempt"])}_fixed_speaker_'+name
            cached_meta=RAW/(candidate+'.json');cached_pcm=RAW/(candidate+'.pcm')
            if cached_meta.exists() and cached_pcm.exists() and json.loads(cached_meta.read_text()).get('request')==payload:
                cache_name=candidate
    raw, metadata = request_pcm(cache_name, payload)
    path = OUT / 'radio' / (name + '.wav')
    samples=prepare_raw(raw, metadata, SR_VOICE, True)
    # Constant atempo per profile preserves vocal pitch; action/context never
    # changes this actor's voice identity or playback pitch.
    tempo=float(spec.get('tempo',1))
    if tempo!=1:
        with tempfile.TemporaryDirectory(prefix='paper-front-voice-tempo-') as directory:
            input_wav=Path(directory)/'input.wav';output_wav=Path(directory)/'output.wav'
            with wave.open(str(input_wav),'wb') as wav:
                wav.setnchannels(1);wav.setsampwidth(2);wav.setframerate(SR_VOICE)
                wav.writeframes(np.rint(samples*32767).astype('<i2').tobytes())
            subprocess.run(['ffmpeg','-hide_banner','-loglevel','error','-y','-i',str(input_wav),'-af',f'atempo={tempo:.3f}','-ar',str(SR_VOICE),'-ac','1','-c:a','pcm_s16le',str(output_wav)],check=True)
            with wave.open(str(output_wav)) as wav:
                samples=np.frombuffer(wav.readframes(wav.getnframes()),dtype='<i2').astype(float)/32768
            samples=master(samples,SR_VOICE,.66)
    samples=compact_voice_pauses(samples,SR_VOICE)*.8
    if spec['action']=='death':samples=death_voice_process(samples,SR_VOICE,spec['category'])
    write_wav(path, samples, SR_VOICE)
    return {**spec, **wav_record(path), 'provenance': {
        'type': 'synthesized_speech', 'provider': 'OpenRouter / xAI Grok Voice' if model.startswith('x-ai/') else 'OpenRouter / Alibaba Qwen TTS' if model.startswith('qwen/') else 'OpenRouter / Microsoft Azure MAI Voice',
        'model': model, 'human_recording': False, 'generation_id': metadata['generation_id'],
        'speaker_id':spec['speaker_id'],'managed_voice':spec['voice'],
        'accepted_request_cache':cache_name,
        'speaker_strategy':'Fixed managed Mandarin speaker; no generative per-action delivery or gender prompt',
        'post_processing':{'tempo':tempo,'pitch':1.0,'pitch_preserved':True,'amplitude_gain':.8,'internal_pause_cap_s':.12,
                           'death_delivery':'short cry/distress fragment, strained saturation and radio interruption' if spec['action']=='death' else 'normal'},
        'request_sha256': metadata['request_sha256'], 'raw_sha256': metadata['raw_sha256'],
        'license_notice': 'Provider-generated synthetic voice; not claimed as CC0 or human recording.'},
        'language':'cmn', 'spoken_words':True,
        'license':'Provider-generated output under OpenRouter and the respective speech-provider service terms; no CC0 claim.'}

def compact_voice_pauses(samples,rate):
    """Remove only long low-energy pauses in a single authored phrase.

    Not used for splitting a batch or determining words. Very quiet consonants
    and natural brief speech gaps are retained; a120ms+ silent span is shortened
    with frame-alignment headroom so measured pauses stay below120ms. Vocal
    pitch and speaker stay unchanged.
    """
    frame=max(1,round(rate*.01));n=len(samples)
    energy=np.array([np.sqrt(np.mean(samples[i:min(i+frame,n)]**2)) for i in range(0,n,frame)])
    quiet=energy<.003
    spans=[];start=None
    for index,value in enumerate(quiet):
        if value and start is None:start=index
        if (not value or index==len(quiet)-1) and start is not None:
            end=index if not value else index+1
            if start>0 and end<len(quiet) and end-start>=12:spans.append((start*frame,min(end*frame,n)))
            start=None
    out=[];cursor=0;keep=round(rate*.08)
    for begin,end in spans:
        out.append(samples[cursor:begin+keep//2]);cursor=end-keep//2
    out.append(samples[cursor:]);result=np.concatenate(out)
    fade=min(round(rate*.014),len(result)//4)
    result[:min(round(rate*.001),len(result)//4)]*=np.linspace(0,1,min(round(rate*.001),len(result)//4))
    result[-fade:]*=np.linspace(1,0,fade)
    return result

def death_voice_process(samples,rate,category):
    # The fixed actor and pitch remain intact. Only dying utterances receive
    # faster urgency, strained dynamics and a short interrupted radio release.
    # No normal acknowledgement inherits this processing.
    with tempfile.TemporaryDirectory(prefix='paper-front-death-voice-') as directory:
        src=Path(directory)/'input.wav';dst=Path(directory)/'output.wav'
        with wave.open(str(src),'wb') as wav:
            wav.setnchannels(1);wav.setsampwidth(2);wav.setframerate(rate);wav.writeframes(np.rint(samples*32767).astype('<i2').tobytes())
        subprocess.run(['ffmpeg','-hide_banner','-loglevel','error','-y','-i',str(src),'-af','atempo=1.15','-c:a','pcm_s16le',str(dst)],check=True)
        with wave.open(str(dst)) as wav:samples=np.frombuffer(wav.readframes(wav.getnframes()),dtype='<i2').astype(float)/32768
    samples=samples[:round(rate*1.8)]
    samples=np.tanh(samples*2.0);samples-=samples.mean()
    samples*=.45/max(np.max(np.abs(samples)),1e-9)
    t=np.arange(len(samples))/rate
    if category in ('vehicle','air'):
        samples+=.015*np.sin(2*np.pi*74*t)*np.exp(-t/.23)
    attack=min(round(rate*.002),len(samples)//8);release=min(round(rate*.085),len(samples)//4)
    samples[:attack]*=np.linspace(0,1,attack)
    samples[-release:]*=np.linspace(1,0,release)
    # Final small offset correction uses an edge-zero window.
    window=np.ones(len(samples));window[:attack]=np.linspace(0,1,attack);window[-release:]=np.linspace(1,0,release)
    samples-=samples.mean()*window/max(window.mean(),1e-9)
    return samples

def selection_power_effect():
    t=np.arange(round(SR_SFX*.36))/SR_SFX
    x=(np.sin(2*np.pi*(180*t+90*t*t))+.24*np.sin(2*np.pi*520*t))*np.sin(np.pi*t/.36)**2*np.exp(-t*8)
    x+=.035*np.sin(2*np.pi*70*t)*np.sin(np.pi*t/.36)**2
    path=OUT/'sfx/select_power.wav';write_wav(path,master(x,SR_SFX,.62),SR_SFX)
    return {'family':'select_power','kind':'select_power','variant':1,'loop':False,**wav_record(path),
        'provenance':{'type':'original_dsp','provider':'Local original electrical selection cue','source':'tools/generate_revision_v8_audio.py','license':'CC0-1.0'}}

def interface_tap_effect(name):
    duration=.09 if name=='ui_key' else .12
    t=np.arange(round(SR_SFX*duration))/SR_SFX
    rng=np.random.default_rng(1081 if name=='ui_key' else 1082)
    frequency=np.fft.rfftfreq(len(t),1/SR_SFX)
    noise=np.fft.irfft(np.fft.rfft(rng.standard_normal(len(t)))*np.exp(-(frequency/(3600 if name=='ui_key' else 1700))**4),len(t))
    noise/=max(np.sqrt(np.mean(noise*noise)),1e-9)
    envelope=(1-np.exp(-t/.001))*np.exp(-t/(.011 if name=='ui_key' else .024))
    signal=(noise*.24+np.sin(2*np.pi*(510 if name=='ui_key' else 175)*t)*.3)*envelope
    path=OUT/'sfx'/(name+'.wav');write_wav(path,master(signal,SR_SFX,.48),SR_SFX)
    return {'family':name,'kind':name,'variant':1,'loop':False,**wav_record(path),
        'provenance':{'type':'original_dsp','provider':'Local original short key tap' if name=='ui_key' else 'Local original cardboard button click','source':'tools/generate_revision_v8_audio.py','license':'CC0-1.0'}}

def generate_system_alerts():
    voice='zh-CN-Harper:MAI-Voice-2.1';clips=[]
    for action,text in [('low_power','电力不足，请增建电站。'),('power_restored','电力已恢复。')]:
        raw,metadata=request_pcm('system_alert_'+action,{'model':TTS_MODEL,'input':text,'voice':voice,'response_format':'pcm'})
        path=OUT/'system'/(action+'.wav')
        samples=compact_voice_pauses(prepare_raw(raw,metadata,SR_VOICE,True),SR_VOICE)*.8
        write_wav(path,samples,SR_VOICE)
        clips.append({'key':'system/'+action+'/1','action':action,'variant':1,'category':'system','faction':'','text':text,
            'speaker_id':voice+'@system','voice':voice,**wav_record(path),'provenance':{'type':'synthesized_speech','provider':'OpenRouter / Microsoft Azure MAI Voice','model':TTS_MODEL,'managed_voice':voice,'generation_id':metadata['generation_id'],'request_sha256':metadata['request_sha256'],'raw_sha256':metadata['raw_sha256'],'post_processing':{'pitch':1.0,'amplitude_gain':.8,'internal_pause_cap_s':.12}}})
    write_json(OUT/'system/manifest.json',{'version':10,'sample_rate':SR_VOICE,'license':'Provider-generated output under OpenRouter and Microsoft service terms; no CC0 claim.','clips':clips})

def sfx_job(item):
    if PAUSE.exists() or STOP_PAID.is_set():
        raise CreditPause('Related production paused while awaiting user recharge confirmation.')
    family, variant, duration, brief = item
    fallback=RAW/f'{family}_{variant}.fallback.json'
    if fallback.exists():
        record=json.loads(fallback.read_text())
        path=ROOT/record['file'][6:]
        if path.exists() and hashlib.sha256(path.read_bytes()).hexdigest()==record['sha256']:
            return record
    variations = ['Dry close perspective with firm low body.',
                  'Slightly wider natural outdoor reflection with distinct textured body.',
                  'Dense close perspective, a slightly different mechanical and debris texture.']
    prompt = f'{brief} {variations[variant - 1]} Produce exactly one isolated original game sound effect, beginning immediately, ending naturally, approximately {duration} seconds total. No voices, no speech, no music, no unrelated ambience.'
    payload = {'model': SFX_MODEL, 'input': prompt, 'response_format': 'pcm'}
    try:
        raw, metadata = request_pcm(f'{family}_{variant}', payload)
    except RuntimeError as exc:
        if 'HTTP 400' in str(exc) and 'generated audio was rejected' in str(exc):
            return local_effect(item,str(exc))
        raise
    path = OUT / 'sfx' / f'{family}_{variant}.wav'
    samples = prepare_raw(raw, metadata, SR_SFX)
    write_wav(path, samples, SR_SFX)
    return {'family': family, 'kind': family, 'variant': variant, 'loop': False,
            **wav_record(path), 'provenance': {
                'type': 'generated_sound_effect', 'provider': 'OpenRouter / ByteDance Seed Audio',
                'model': SFX_MODEL, 'prompt': prompt, 'generation_id': metadata['generation_id'],
                'request_sha256': metadata['request_sha256'], 'raw_sha256': metadata['raw_sha256'],
                'license_notice': 'Provider-generated effect; not claimed as an original field recording or CC0.'}}

def local_effect(item,reason):
    """One original layered pressure/debris effect when a provider returns none.

    This is a new local composition with actual provenance, never described as
    a successful model generation. It is not a workaround for missing credits.
    """
    family,variant,duration,brief=item
    if PAUSE.exists() or STOP_PAID.is_set():
        raise CreditPause('Related production paused until user recharge confirmation.')
    seed=int(hashlib.sha256(f'{family}/{variant}/v8-original'.encode()).hexdigest()[:8],16)
    rng=np.random.default_rng(seed);t=np.arange(round(SR_SFX*duration))/SR_SFX
    frequency=np.fft.rfftfreq(len(t),1/SR_SFX)
    def noise(low,high):
        mask=(1-np.exp(-(frequency/low)**4))*np.exp(-(frequency/high)**4)
        x=np.fft.irfft(np.fft.rfft(rng.standard_normal(len(t)))*mask,len(t))
        return x/max(np.sqrt(np.mean(x*x)),1e-9)
    size=1.4 if family in ('fire_artillery','impact_large','death_building') else 1.0
    snap=(1-np.exp(-t/.00035))*np.exp(-t/(.021*size))
    gas=(1-np.exp(-t/.003))*np.exp(-t/(.14*size))
    rumble=(1-np.exp(-t/.008))*np.exp(-t/(.41*size))
    pitch=48+120*np.exp(-t/.027)
    phase=np.cumsum(pitch)*2*np.pi/SR_SFX
    x=.30*noise(260,3600)*snap+.48*np.sin(phase)*np.exp(-t/(.13*size))
    x+=.22*noise(45,780)*gas+.20*noise(25,280)*rumble
    if family.startswith('fire_'):
        # Gun carriage recoil, gas reflection and breech closing.
        source=x.copy()
        for delay,gain in ((.065,.18),(.143,.08),(.231,.035)):
            n=round(delay*SR_SFX);x[n:]+=source[:-n]*gain
        for delay in (.145,.32):
            shifted=t-delay
            env=np.where(shifted>=0,np.exp(-np.maximum(shifted,0)/.009),0)
            x+=.034*noise(450,2800)*env
    else:
        for delay in rng.uniform(.12,max(.15,duration*.72),9):
            shifted=t-delay
            env=np.where(shifted>=0,np.exp(-np.maximum(shifted,0)/.018),0)
            x+=float(rng.uniform(.02,.07))*noise(240,2700)*env
    path=OUT/'sfx'/f'{family}_{variant}.wav'
    write_wav(path,master(x,SR_SFX,.76),SR_SFX)
    record={'family':family,'kind':family,'variant':variant,'loop':False,**wav_record(path),
            'provenance':{'type':'original_dsp','provider':'Local deterministic layered NumPy synthesis',
                          'source':'tools/generate_revision_v8_audio.py','license':'CC0-1.0',
                          'brief':brief,'seed':seed,'fallback_reason':reason}}
    write_json(RAW/f'{family}_{variant}.fallback.json',record)
    return record

def motion_loop(kind):
    rate, duration = SR_SFX, 2.0
    t = np.arange(round(rate * duration)) / rate
    rng = np.random.default_rng(86018 + sum(map(ord, kind)))
    freqs = np.fft.rfftfreq(len(t), 1/rate)
    noise = np.fft.irfft(np.fft.rfft(rng.standard_normal(len(t))) * np.exp(-(freqs/900)**4),len(t))
    noise /= max(np.sqrt(np.mean(noise**2)), 1e-9)
    if kind == 'engine_loop':
        # Four-stroke low combustion pulses, block harmonics and soft intake.
        samples = sum(g*np.sin(2*np.pi*36*h*t + .045*np.sin(2*np.pi*4*t)) for h,g in [(1,.4),(2,.19),(3,.11),(5,.055)])
        samples *= 1+.14*np.sin(2*np.pi*9*t)
        samples += .045*noise
    elif kind == 'tracks_loop':
        # Alternating link contact, rubber grit and roller rumble.
        pulse = (.5+.5*np.sin(2*np.pi*12*t))**7
        samples = noise*(.06+.18*pulse)+.095*np.sin(2*np.pi*66*t)
        samples += .024*np.sin(2*np.pi*420*t)*(pulse**2)
    else:
        # Propeller blade beat beneath a muted aerodynamic bed.
        samples = sum(g*np.sin(2*np.pi*78*h*t) for h,g in [(1,.3),(2,.15),(4,.07)])
        samples *= .8+.15*np.sin(2*np.pi*13*t)
        samples += .075*noise
    return master(samples, rate, .55, True)

def request_music(name,prompt):
    if PAUSE.exists() or STOP_PAID.is_set():
        raise CreditPause('Music production awaits user recharge confirmation.')
    payload={'model':MUSIC_MODEL,'messages':[{'role':'user','content':prompt}],
             'modalities':['audio'],'audio':{'format':'wav'},'stream':True}
    request_hash=hashlib.sha256(json.dumps(payload,ensure_ascii=False,sort_keys=True).encode()).hexdigest()
    encoded_path=RAW/('music_'+name+'.audio')
    meta_path=RAW/('music_'+name+'.json')
    if encoded_path.exists() and meta_path.exists():
        meta=json.loads(meta_path.read_text())
        if meta['request_sha256']==request_hash and hashlib.sha256(encoded_path.read_bytes()).hexdigest()==meta['raw_sha256']:
            return encoded_path.read_bytes(),meta
    # Reuse the successful staged Lyria menu request, not a paid duplicate.
    probe=REPORT/'lyria_menu_probe.json'
    probe_audio=REPORT/'lyria_menu_probe.wav'
    if name=='menu' and probe.exists() and probe_audio.exists():
        tested=json.loads(probe.read_text())
        if tested['request']==payload and tested.get('bytes',0)>0:
            raw=probe_audio.read_bytes()
            meta={'request':payload,'request_sha256':request_hash,'raw_sha256':hashlib.sha256(raw).hexdigest(),
                  'generation_id':tested['generation_id'],'usage':tested.get('usage',{}),'source_container':'mp3'}
            encoded_path.write_bytes(raw);write_json(meta_path,meta)
            return raw,meta
    if PAUSE.exists() or STOP_PAID.is_set():
        raise CreditPause('Music production awaits user recharge confirmation.')
    request=urllib.request.Request('https://openrouter.ai/api/v1/chat/completions',
        data=json.dumps(payload).encode(),headers={'Authorization':'Bearer '+os.environ['OPENROUTER_API_KEY'],
                'Content-Type':'application/json'},method='POST')
    parts=[];meta={'request':payload,'request_sha256':request_hash}
    try:
        with urllib.request.urlopen(request,timeout=180) as response:
            for line in response:
                if not line.startswith(b'data: '):continue
                line=line[6:].strip()
                if line==b'[DONE]':break
                chunk=json.loads(line)
                if 'id' in chunk:meta['generation_id']=chunk['id']
                if 'usage' in chunk:meta['usage']=chunk['usage']
                if 'error' in chunk:
                    error=chunk['error'];message=safe_message(error.get('message','Provider failed'))
                    if error.get('code')==402 or 'insufficient credit' in message.lower():pause_credit(402,message)
                    raise RuntimeError('Music provider stream error: '+message[:180])
                for choice in chunk.get('choices',[]):
                    data=choice.get('delta',{}).get('audio',{}).get('data')
                    if data:parts.append(base64.b64decode(data))
    except urllib.error.HTTPError as exc:
        body=json.loads(exc.read());message=safe_message(body.get('error',{}).get('message','Provider failed'))
        if exc.code==402 or 'insufficient credit' in message.lower():pause_credit(exc.code,message)
        raise RuntimeError(f'Music provider HTTP {exc.code}: {message[:180]}') from None
    raw=b''.join(parts)
    if len(raw)<10000:raise RuntimeError('Music provider returned no usable audio')
    meta['raw_sha256']=hashlib.sha256(raw).hexdigest()
    meta['source_container']='mp3' if raw[:3]==b'ID3' else 'provider audio, decoded by ffmpeg'
    encoded_path.write_bytes(raw);write_json(meta_path,meta)
    return raw,meta

def music_job(name, prompt):
    raw,metadata=request_music(name,prompt)
    # Lyria currently returns encoded stereo music even when WAV is requested;
    # inspect/decode the actual bytes instead of assuming a PCM sample rate.
    with tempfile.TemporaryDirectory(prefix='paper-front-lyria-') as directory:
        encoded=Path(directory)/'source.audio';encoded.write_bytes(raw)
        decoded=Path(directory)/'source.wav'
        subprocess.run(['ffmpeg','-hide_banner','-loglevel','error','-y','-i',str(encoded),
                        '-ac','1','-c:a','pcm_s16le',str(decoded)],check=True)
        with wave.open(str(decoded)) as wav:
            rate=wav.getframerate()
            samples=np.frombuffer(wav.readframes(wav.getnframes()),dtype='<i2').astype(float)/32768
    metadata['source_sample_rate']=rate
    metadata['source_duration_s']=round(len(samples)/rate,4)
    if len(samples)/rate<45:
        raise RuntimeError(f'Music response too short: {len(samples)/rate:.2f}s')
    samples-=samples.mean()
    frequency=np.fft.rfftfreq(len(samples),1/rate)
    spectrum=np.fft.rfft(samples)*(1-np.exp(-(frequency/27)**4))*np.exp(-(frequency/9800)**6)
    samples=np.fft.irfft(spectrum,len(samples))
    if rate!=SR_VOICE:
        samples=np.interp(np.arange(round(len(samples)*SR_VOICE/rate))*rate/SR_VOICE,np.arange(len(samples)),samples)
    # Rotate through the first two seconds and blend the closing two seconds
    # back into them. The next loop begins at the following source sample;
    # unlike an end-to-zero fade this retains the rhythm through the seam.
    overlap=round(SR_VOICE*2)
    w=np.linspace(0,1,overlap)
    blend=samples[-overlap:]*(1-w)+samples[:overlap]*w
    samples=np.concatenate([samples[overlap:-overlap],blend])
    samples=master(samples,SR_VOICE,.57,True)
    path=OUT/'music'/(name+'.wav')
    write_wav(path,samples,SR_VOICE)
    return {'id':name,'name':name,'title':{'menu':'桌边微光','battle_calm':'静谧边境','battle_engaged':'前哨警觉','battle_intense':'战线燃起','battle_danger':'孤立阵线'}[name],
            'loop':True,**wav_record(path),'provenance':{
                'type':'generated_music','provider':'OpenRouter / Google Lyria',
                'model':MUSIC_MODEL,'prompt':prompt,'generation_id':metadata['generation_id'],
                'request_sha256':metadata['request_sha256'],'raw_sha256':metadata['raw_sha256'],
                'source_duration_s':metadata['source_duration_s'],'loop_edit':'2-second cyclic crossfade',
                'provider_reported_cost_usd':metadata.get('usage',{}).get('cost'),
                'license_notice':'Provider-generated original-prompt instrumental; no CC0 claim.'}}

def generate_music(track_names=None):
    if PAUSE.exists():
        raise CreditPause('Paid production awaits user recharge confirmation.')
    before,_=credits_usage()
    previous=json.loads((OUT/'music/manifest.json').read_text()) if (OUT/'music/manifest.json').exists() else {}
    tracks={track['id']:track for track in previous.get('tracks',[])}
    for name in (track_names or list(MUSIC)):
        prompt=MUSIC[name]
        existing=tracks.get(name,{})
        if existing and (ROOT/existing['file'][6:]).exists() and hashlib.sha256((ROOT/existing['file'][6:]).read_bytes()).hexdigest()==existing['sha256']:
            print('Music cached',name,flush=True);continue
        print('Generating music',name,flush=True)
        tracks[name]=music_job(name,prompt)
        print('Music complete',name,tracks[name]['duration_s'],flush=True)
    write_json(OUT/'music/manifest.json',{'version':8,'sample_rate':SR_VOICE,'format':'PCM signed 16-bit mono WAV',
        'license':'Provider-generated output under OpenRouter and Google service terms; no CC0 claim.',
        'tracks':list(tracks.values())})
    after,_=credits_usage()
    write_json(REPORT/'music_billing.json',{'account_usage_delta_during_music_pass_usd':round(after-before,7),
        'provider_reported_cost_usd':sum(t['provenance']['provider_reported_cost_usd'] or 0 for t in tracks.values()),
        'track_count':len(tracks),'model':MUSIC_MODEL,'pricing_usd_per_song':.08,
        'note':'Account delta includes concurrently generated speech/SFX; provider usage reports the exact music cost.'})

def generate(generate_paid, resume_paid, limit, representative=False):
    # The original full v8 recipe contains historical interface/music choices.
    # Once a newer selective bank is installed, it must not silently overwrite
    # accepted repairs, fixed actors or new routed families.
    current_manifest = OUT / 'radio/manifest.json'
    if current_manifest.exists() and int(json.loads(current_manifest.read_text()).get('version', 0)) >= 11:
        raise RuntimeError('The current bank uses the selective 2026-10-07 recipe; use tools/revision_audio_20261007.py. Validation remains available with --validate-only.')
    if PAUSE.exists() and not resume_paid:
        raise CreditPause('Paid generation already paused; user recharge confirmation is required.')
    if resume_paid and PAUSE.exists():
        PAUSE.unlink()
    OUT.mkdir(parents=True, exist_ok=True)
    RAW.mkdir(parents=True, exist_ok=True)
    if not generate_paid:
        raise RuntimeError('Paid requests require explicit --generate; use --validate-only to inspect existing files.')
    before, remaining = credits_usage()
    # Two small probes are included in the final account-delta cost report.
    initial = REPORT / 'billing_start.json'
    if not initial.exists():
        write_json(initial, {'total_usage_before_production_usd':before,
                             'pricing_docs': 'https://openrouter.ai/docs/guides/overview/multimodal/tts',
                             'maximum_planned_spend_usd': 1.0})
    if remaining < .35:
        pause_credit(402, 'Remaining credit is below the conservative planned production estimate.')
    jobs = [('voice', spec) for spec in specifications()]
    jobs += [('sfx', (family, variant, duration, brief))
             for family,(duration,brief) in SFX.items() for variant in range(1,4)]
    if representative:
        jobs = [('voice',spec) for spec in specifications() if spec['action']=='select' and spec['variant']==1]
        jobs += [('sfx',(family,1,*SFX[family])) for family in ('fire_machine_gun','fire_cannon','deploy_building')]
    if limit:
        jobs = jobs[:limit]
    clips, effects, failures = [], [], []
    with ThreadPoolExecutor(max_workers=3) as pool:
        futures = {pool.submit(voice_job if kind == 'voice' else sfx_job, spec): (kind,spec) for kind,spec in jobs}
        for count, future in enumerate(as_completed(futures), 1):
            kind,spec = futures[future]
            try:
                result = future.result()
                (clips if kind == 'voice' else effects).append(result)
                print(f'{count}/{len(jobs)} {kind} {result.get("key",result.get("family"))} {result["duration_s"]:.2f}s',flush=True)
            except CreditPause as exc:
                failures.append(str(exc))
            except Exception as exc:
                failures.append(f'{kind}: {type(exc).__name__}: {str(exc)[:180]}')
                print('FAIL',failures[-1],flush=True)
    for kind in ('engine_loop','tracks_loop','aircraft_loop'):
        path = OUT/'sfx'/(kind+'.wav')
        write_wav(path,motion_loop(kind),SR_SFX)
        effects.append({'family':kind,'kind':kind,'variant':1,'loop':True,**wav_record(path),
                        'provenance':{'type':'original_dsp','provider':'Local deterministic NumPy synthesis',
                                      'source':'tools/generate_revision_v8_audio.py','license':'CC0-1.0'}})
    effects.append(selection_power_effect())
    effects.extend(interface_tap_effect(name) for name in ['ui_key','ui_click'])
    if len(clips) == 300:
        write_json(OUT/'radio/manifest.json',{
            'version':8,'language':'zh-CN','sample_rate':SR_VOICE,'format':'PCM signed 16-bit mono WAV',
            'license':'Provider-generated output under OpenRouter and Microsoft service terms; no CC0 claim.',
            'speech_notice':'Natural Mandarin via paid OpenRouter Microsoft managed speakers; fixed identity per profile, no cloned or human-recorded voices.',
            'dialogue_source':'tools/revision_v8_dialogue.py',
            'profiles':{k:{'voice':v[0],'speaker_identity':v[0],'speaker_id':v[0]+f'@tempo={v[2]:.3f}','speaker_gender':v[1],'tempo':v[2],'request_strategy':'fixed managed speaker; no per-action prompt'} for k,v in FIXED_SPEAKERS.items()},
            'clips':sorted(clips,key=lambda x:x['key'])})
    if len(effects)==54:
        write_json(OUT/'sfx/manifest.json',{'version':8,'sample_rate':SR_SFX,'format':'PCM signed 16-bit mono WAV',
                                         'effects':sorted(effects,key=lambda x:(x['family'],x['variant']))})
    try:
        after,_ = credits_usage()
        start_record=json.loads(initial.read_text())
        beginning = start_record.get('total_usage_before_probes_usd',start_record.get('total_usage_before_production_usd',before))
        write_json(REPORT/'billing_summary.json',{'account_usage_delta_usd':round(after-beginning,7),
            'delta_includes_two_probes':'total_usage_before_probes_usd' in start_record,'successful_voice_files':len(clips),
            'successful_sfx_files':len(effects),'paid_provider':'OpenRouter',
            'models':[TTS_MODEL,SFX_MODEL,MUSIC_MODEL],
            'note':'Account total-usage delta observed during this audio-only production window, including concurrent music requests; provider TTS generation records were not exposed by the generation endpoint.'})
    except Exception:
        pass
    write_json(REPORT/'production_status.json',{'status':'PAUSED_CREDITS' if STOP_PAID.is_set() else 'COMPLETE' if not failures else 'PARTIAL',
                'voice_count':len(clips),'effect_count':len(effects),'failures':failures})
    if STOP_PAID.is_set():
        raise CreditPause('OpenRouter credit pause; tell the user to recharge and await their reply.')
    if failures:
        raise RuntimeError(f'{len(failures)} generation jobs failed; successful requests are cached for retry.')

def validate():
    failures,stats = [],{}
    for section,array in [('radio','clips'),('sfx','effects'),('music','tracks'),('system','clips')]:
        if section in ('music','system') and not (OUT/section/'manifest.json').exists():continue
        manifest=json.loads((OUT/section/'manifest.json').read_text())
        for clip in manifest[array]:
            path=ROOT/clip['file'][6:]
            with wave.open(str(path)) as wav:
                data=np.frombuffer(wav.readframes(wav.getnframes()),dtype='<i2').astype(float)/32768
                rate=wav.getframerate(); channels=wav.getnchannels(); width=wav.getsampwidth()
            peak=float(np.max(np.abs(data)));rms=float(np.sqrt(np.mean(data**2)))
            checks={**wav_record(path),'peak_dbfs':round(20*np.log10(max(peak,1e-12)),3),
                    'rms_dbfs':round(20*np.log10(max(rms,1e-12)),3),
                    'dc_offset':round(float(np.mean(data)),7),'clipped_samples':int(np.count_nonzero(np.abs(data)>=.999))}
            stats[clip['file']]=checks
            if rate!=(SR_SFX if section=='sfx' else SR_VOICE) or channels!=1 or width!=2:
                failures.append(path.name+':invalid PCM format')
            if checks['sha256']!=clip['sha256'] or abs(checks['duration_s']-clip['duration_s'])>.0001:
                failures.append(path.name+':manifest mismatch')
            if peak>.79 or checks['clipped_samples'] or rms<.012:
                failures.append(path.name+':clipping/headroom/silent response')
            if abs(checks['dc_offset'])>.002:
                failures.append(path.name+':DC offset')
            if clip.get('loop'):
                if (section=='sfx' and len(data)!=rate*2) or abs(data[0]-data[-1])>1/32768:
                    failures.append(path.name+':loop boundary/duration')
            elif data[0]!=0 or data[-1]!=0:
                failures.append(path.name+':edge fade')
    voices=json.loads((OUT/'radio/manifest.json').read_text())['clips']
    grouped={}
    for clip in voices:
        grouped.setdefault((clip['faction'],clip['category'],clip['action']),[]).append(clip)
    if len(voices)!=300 or len(grouped)!=96:
        failures.append('Incomplete faction/category/action coverage')
    for key,group in grouped.items():
        expected=4 if key[2]=='death' else 3
        if len(group)!=expected or len({c['text'] for c in group})!=expected or len({c['sha256'] for c in group})!=expected:
            failures.append(str(key)+':distinct actual variants required')
    if len(FIXED_SPEAKERS)!=12 or len({c.get('speaker_id') for c in voices})!=12 or len({c.get('voice') for c in voices})!=12:
        failures.append('Twelve stable profile identities required')
    for key,group in grouped.items():
        profile=key[0]+'/'+key[1]
        expected=FIXED_SPEAKERS[profile][0]+f'@tempo={FIXED_SPEAKERS[profile][2]:.3f}'
        if any(c.get('speaker_id')!=expected for c in group):
            failures.append(str(key)+':speaker identity differs within the profile')
    report={'status':'PASS' if not failures else 'FAIL','asset_count':len(stats),'voice_count':len(voices),
            'voice_groups':len(grouped),'failures':failures,'assets':stats}
    write_json(REPORT/'pcm_validation.json',report)
    print(report['status'],len(stats),'audio files;',len(grouped),'voice groups;',len(failures),'failures')
    if failures:
        for failure in failures: print(failure)
        raise SystemExit(1)

def audition():
    # Parallel short columns would obscure the delivery; the user can audition
    # each faction's three categories sequentially, then the standalone effects.
    manifest=json.loads((OUT/'radio/manifest.json').read_text())['clips']
    review=REPORT/'review';review.mkdir(parents=True,exist_ok=True)
    for faction in ('kestrel','rivet','iron','sky'):
        actions=('select','move','attack','combat','under_attack','death')
        categories=('infantry','vehicle','air')
        clips=[c for c in manifest if c['faction']==faction and c['action'] in actions and c['variant']==1]
        samples=[];timeline=[];cursor=0
        for clip in sorted(clips,key=lambda x:(categories.index(x['category']),actions.index(x['action']))):
            with wave.open(str(ROOT/clip['file'][6:])) as wav:
                data=np.frombuffer(wav.readframes(wav.getnframes()),dtype='<i2').astype(float)/32768
            timeline.append({'at_s':round(cursor,3),'category':clip['category'],'action':clip['action'],'text':clip['text']})
            samples.extend([data*.64,np.zeros(round(SR_VOICE*.48))]);cursor+=len(data)/SR_VOICE+.48
        write_wav(review/(faction+'_voices.wav'),np.concatenate(samples),SR_VOICE)
        write_wav(REPORT/(f'preview_voices_{faction}.wav'),np.concatenate(samples),SR_VOICE)
        write_json(review/(faction+'_timeline.json'),timeline)
    effects=json.loads((OUT/'sfx/manifest.json').read_text())['effects']
    samples=[];timeline=[];cursor=0
    for clip in effects:
        if clip['variant']!=1:continue
        with wave.open(str(ROOT/clip['file'][6:])) as wav:
            data=np.frombuffer(wav.readframes(wav.getnframes()),dtype='<i2').astype(float)/32768
        timeline.append({'at_s':round(cursor,3),'family':clip['family']})
        samples.extend([data*.55,np.zeros(round(SR_SFX*.65))]);cursor+=len(data)/SR_SFX+.65
    write_wav(review/'sound_effects.wav',np.concatenate(samples),SR_SFX)
    write_wav(REPORT/'preview_sound_effects.wav',np.concatenate(samples),SR_SFX)
    write_json(review/'sound_effects_timeline.json',timeline)

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--generate',action='store_true')
    parser.add_argument('--resume-paid',action='store_true')
    parser.add_argument('--validate-only',action='store_true')
    parser.add_argument('--limit',type=int,help='Produce only first N jobs for a small provider check')
    parser.add_argument('--representative',action='store_true',help='Only 12 profile samples and 3 SFX for staged production review')
    parser.add_argument('--music-only',action='store_true',help='Generate the two dedicated music tracks')
    parser.add_argument('--music-track',choices=list(MUSIC),action='append',help='Append only the chosen music track; preserve other actual tracks')
    parser.add_argument('--system-alerts-only',action='store_true')
    args=parser.parse_args()
    if args.system_alerts_only:
        if not args.generate:raise RuntimeError('--system-alerts-only requires --generate')
        generate_system_alerts();raise SystemExit(0)
    if args.music_only:
        if not args.generate:
            raise RuntimeError('--music-only requires --generate')
        generate_music(args.music_track)
        raise SystemExit(0)
    if not args.validate_only:
        generate(args.generate,args.resume_paid,args.limit,args.representative)
    if not args.limit and not args.representative:
        validate()
        audition()
