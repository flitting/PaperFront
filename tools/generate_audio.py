"""Original layered field/mechanical audio. CC0, deterministic, no external samples.

Requires only numpy. Run from any directory. All assets are 44.1 kHz mono PCM16;
engine/track beds are periodic seamless loops. Variant seeds stay reproducible.
"""
from pathlib import Path
import json
import wave
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/audio'
REPORT = ROOT / 'artifacts/visual_iteration/v44_reference_rebuild/audio'
SR = 44100
RNG = np.random.default_rng(440044)


def time(duration):
    return np.arange(round(duration * SR), dtype=np.float64) / SR


def band_noise(n, low, high):
    """Smooth FFT bandpass: no brittle white-noise top or filter ringing."""
    data = RNG.standard_normal(n)
    f = np.fft.rfftfreq(n, 1 / SR)
    mask = (1 - np.exp(-(f / max(low, 1)) ** 4)) * np.exp(-(f / high) ** 4)
    data = np.fft.irfft(np.fft.rfft(data) * mask, n)
    return data / max(np.sqrt(np.mean(data * data)), 1e-9)


def envelope(t, decay, attack=.0007):
    return (1 - np.exp(-t / attack)) * np.exp(-t / decay)


def body(t, start, finish, decay, gain=1):
    phase = 2 * np.pi * (finish * t + (start - finish) * .018 * (1 - np.exp(-t / .018)))
    return gain * np.sin(phase) * envelope(t, decay, .0005)


def place(out, sound, delay=0, gain=1):
    i = round(delay * SR)
    length = min(len(sound), len(out) - i)
    if length > 0:
        out[i:i+length] += sound[:length] * gain


def field_tail(sound, taps=((.047, .16), (.093, .09), (.151, .045))):
    out = sound.copy()
    for delay, gain in taps:
        place(out, sound, delay, gain)
    return out


def shot(style, variant):
    settings = {'rifle':(.65, 155, .039, .035, 3100),
                'anti':(.86, 125, .068, .078, 2300),
                'cannon':(1.12, 98, .14, .12, 1900),
                'artillery':(1.48, 73, .21, .19, 1600)}
    dur, bass, punch, air, high = settings[style]
    t = time(dur); v = 1 + (variant - 1) * .045
    # A pressure snap, low shell/body resonance, and dispersed muzzle gases.
    x = band_noise(len(t), 220, high * v) * envelope(t, punch * .28) * .34
    x += body(t, bass * 2.8 * v, bass * .68, punch, .63)
    x += band_noise(len(t), 55, 820) * envelope(t, air, .002) * .22
    x += band_noise(len(t), 35, 320) * envelope(t, air * 2.8, .007) * .13
    # Quiet metal action after the report: neither laser pitch nor ringing beep.
    mech = time(.12)
    click = band_noise(len(mech), 750, 4300) * envelope(mech, .009, .001) * .045
    place(x, click, .088 if style == 'rifle' else .13)
    place(x, click, .146 if style == 'rifle' else .24, .6)
    return field_tail(x)


def explosion(size, variant):
    dur = {'small': .86, 'medium': 1.42, 'large': 2.15}[size]
    scale = {'small': .65, 'medium': 1., 'large': 1.45}[size]
    t = time(dur); v = 1 + (variant - 1) * .065
    x = body(t, 150 * v, 42 / scale, .095 * scale, .58)
    x += band_noise(len(t), 80, 1900) * envelope(t, .045 * scale) * .32
    x += band_noise(len(t), 28, 620) * envelope(t, .24 * scale, .004) * .30
    x += band_noise(len(t), 23, 210) * envelope(t, .40 * scale, .008) * .19
    # Irregular delayed pieces of rubble and metal, bounded high frequencies.
    for i in range(5 if size == 'small' else 9):
        d = float(RNG.uniform(.13, dur * .68))
        debris_t = time(float(RNG.uniform(.028, .095)))
        debris = band_noise(len(debris_t), 250, 2900) * envelope(debris_t, .012) * .025
        place(x, debris, d, (1 - d / dur))
    return field_tail(x, ((.063,.17),(.137,.09),(.247,.055)))


def mechanism(kind):
    dur = {'select':.095,'command':.17,'build':.78,'sell':.40,'produce':.57,
           'delivery':.53,'low_power':.83,'error':.27,'result':1.65,'death_soft':.44}[kind]
    t = time(dur); x = np.zeros(len(t))
    def knock(delay, tone=210, gain=.3, decay=.025):
        tt=time(min(.28,dur-delay))
        hit=body(tt,tone*1.5,tone,decay,.44)
        hit+=band_noise(len(tt),300,2400)*envelope(tt,decay*.33)*.12
        place(x,hit,delay,gain)
    if kind=='select':
        knock(0,380,.7,.014)
    elif kind=='command':
        knock(0,265,.8,.025); knock(.054,350,.27,.018)
    elif kind=='build':
        knock(0,145,1,.063); knock(.15,190,.6,.04); knock(.29,130,.45,.06)
        x+=band_noise(len(t),65,700)*envelope(t,.18,.018)*.07
    elif kind=='sell':
        knock(0,340,.7);knock(.09,220,.55);knock(.18,150,.4)
    elif kind in ('produce','delivery'):
        knock(0,170,.6,.06)
        # Subdued struck resonators: short workshop completion and cargo latch.
        notes=[(0.10,480),(0.23,640)] if kind=='produce' else [(0.12,520),(0.21,710),(0.31,820)]
        for delay,freq in notes:
            tt=time(dur-delay)
            chime=(np.sin(2*np.pi*freq*tt)+.12*np.sin(2*np.pi*freq*2.76*tt))*envelope(tt,.09,.003)*.095
            place(x,chime,delay)
    elif kind=='low_power':
        for delay in (0,.3):
            tt=time(.39);place(x,np.sin(2*np.pi*185*tt)*envelope(tt,.09,.012)*.22,delay)
    elif kind=='error':
        knock(0,165,.6,.033); knock(.085,125,.5,.04)
    elif kind=='death_soft':
        knock(0,112,.8,.054)
        x+=band_noise(len(t),80,900)*envelope(t,.10,.002)*.11
    elif kind=='result':
        for delay,freq in ((0,330),(.14,415),(.28,495),(.5,660)):
            tt=time(dur-delay)
            resonator=(np.sin(2*np.pi*freq*tt)+.15*np.sin(2*np.pi*freq*2*tt))*envelope(tt,.24,.008)*.13
            place(x,resonator,delay)
    return x


def loop(kind):
    # Whole-number cycles make the wave and every modulation periodic at 2 sec.
    t=time(2.0)
    if kind=='engine':
        rpm=37.0
        x=np.zeros(len(t))
        for h,g in ((1,.32),(2,.19),(3,.12),(4,.07),(6,.027)):
            x+=np.sin(2*np.pi*rpm*h*t + .06*np.sin(2*np.pi*2*t))*g
        x*=(1+.14*np.sin(2*np.pi*8*t)+.06*np.sin(2*np.pi*11.5*t))
        x+=band_noise(len(t),35,530)*.065
    else:
        # A low, granular track/tyre bed instead of a sharp motor buzz.
        grain=band_noise(len(t),150,1800)
        pulses=(.5+.5*np.sin(2*np.pi*11*t))**5
        x=grain*(.028+.11*pulses)
        x+=np.sin(2*np.pi*65*t)*.06
    return x


def prepare(x, peak=.78, seamless=False):
    x = np.asarray(x, dtype=float)
    x -= np.mean(x)
    # Soft saturation glues layers; output normalization leaves >2 dB headroom.
    x=np.tanh(x*1.12)
    if not seamless:
        fade=min(round(.008*SR),len(x)//4)
        x[:round(.00025*SR)]*=np.linspace(0,1,round(.00025*SR))
        x[-fade:]*=np.linspace(1,0,fade)
    x *= peak / max(np.max(np.abs(x)),1e-9)
    return x


def write(name, x):
    pcm=np.round(x*32767).astype('<i2')
    with wave.open(str(OUT/(name+'.wav')),'wb') as f:
        f.setnchannels(1);f.setsampwidth(2);f.setframerate(SR);f.writeframes(pcm.tobytes())


def generate():
    OUT.mkdir(parents=True,exist_ok=True);REPORT.mkdir(parents=True,exist_ok=True)
    assets={}
    for style in ('rifle','anti','cannon','artillery'):
        for i in range(3):assets[f'fire_{style}_{i+1}']=prepare(shot(style,i))
    for size in ('small','medium','large'):
        for i in range(3):assets[f'impact_{size}_{i+1}']=prepare(explosion(size,i))
    for i in range(3):assets[f'death_{i+1}']=prepare(explosion('large',i),.75)
    for kind in ('select','command','build','sell','produce','delivery','low_power','error','result','death_soft'):
        assets[kind]=prepare(mechanism(kind),.6 if kind in ('select','command','error') else .72)
    for kind in ('engine','tracks'):assets[kind+'_loop']=prepare(loop(kind),.6,True)
    # Keep existing generic public event filenames usable as sensible fallbacks.
    assets['fire']=assets['fire_cannon_1'];assets['impact']=assets['impact_medium_1'];assets['death']=assets['death_1']
    for name,x in assets.items():write(name,x)
    stats={name:{'duration_s':round(len(x)/SR,3),'sample_rate':SR,'channels':1,
                 'peak_dbfs':round(20*np.log10(max(np.max(np.abs(x)),1e-12)),2),
                 'rms_dbfs':round(20*np.log10(max(np.sqrt(np.mean(x*x)),1e-12)),2),
                 'clipped_samples':int(np.count_nonzero(np.abs(x)>=1)),
                 'dc':round(float(np.mean(x)),6)} for name,x in assets.items()}
    (REPORT/'asset_validation.json').write_text(json.dumps(stats,indent=2)+'\n')
    # Review mixes use the same per-category gain as runtime; intentionally no
    # normalization afterward, so the relative levels/headroom remain audible.
    groups={'weapons':['fire_rifle_1','fire_anti_1','fire_cannon_1','fire_artillery_1'],
            'explosions':['impact_small_1','impact_medium_1','impact_large_1','death_1'],
            'ui_workshop':['select','command','build','produce','delivery','sell','low_power','error','result']}
    for group,names in groups.items():
        review=np.zeros(round(sum(len(assets[n])/SR+.55 for n in names)*SR))
        cursor=0
        for name in names:
            place(review,assets[name],cursor,10**(-13/20))
            cursor+=len(assets[name])/SR+.55
        with wave.open(str(REPORT/(group+'_audition.wav')),'wb') as f:
            f.setnchannels(1);f.setsampwidth(2);f.setframerate(SR);f.writeframes(np.round(review*32767).astype('<i2').tobytes())
    battlefield=np.zeros(12*SR)
    for d in np.arange(0,12,2):
        place(battlefield,assets['engine_loop'],d,.043)
        place(battlefield,assets['tracks_loop'],d,.028)
    timeline=[(.5,'fire_rifle_1'),(.84,'fire_rifle_2'),(1.2,'fire_anti_1'),(1.78,'impact_small_1'),
              (2.4,'fire_cannon_1'),(2.6,'fire_rifle_3'),(3.05,'impact_medium_2'),
              (4.,'fire_artillery_2'),(4.3,'fire_cannon_3'),(5.0,'impact_large_1'),(5.28,'impact_medium_3'),
              (6.6,'death_2'),(7.5,'fire_rifle_1'),(7.72,'fire_rifle_2'),(8.4,'fire_cannon_2'),
              (9.1,'impact_medium_1'),(10.,'death_1')]
    for d,n in timeline:place(battlefield,assets[n],d,10**(-16/20))
    with wave.open(str(REPORT/'battlefield_audition.wav'),'wb') as f:
        f.setnchannels(1);f.setsampwidth(2);f.setframerate(SR);f.writeframes(np.round(battlefield*32767).astype('<i2').tobytes())
    print(f'Generated {len(assets)} original assets; peak {np.max(np.abs(battlefield)):.3f} in battlefield review.')


if __name__=='__main__':generate()
