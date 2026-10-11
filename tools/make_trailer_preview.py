#!/usr/bin/env python3
"""Make the local-only clean 1080p preview from native 4K model and battle PNGs.

python3 tools/make_trailer_preview.py
All outputs stay in artifacts/trailer_preview_v3_20261011/. No publication tools
are called and media/, README and workflows are never written.
"""
from pathlib import Path
import hashlib
import json
import subprocess
import sys
import re
import wave
import cv2
import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "artifacts/trailer_preview_v3_20261011"
EDIT = OUT / "edit"
FONT = Path("/usr/share/fonts/truetype/noto/NotoSans-Regular.ttf")
MUSIC = ROOT / "assets/audio/music/battle_city.wav"
FPS = 30
PLAN = [
    ("base",4.0,"Paper-crafted battlefields"),
    ("factions",3.0,"Four factions"),
    ("armor",2.0,"Distinct war machines"),
    ("fleet",4.0,"Land. Sea. Sky."),
    ("battle",7.0,"Command the battle"),
    ("infantry",3.0,"Infantry squads"),
]
CREDITS = ["Thanks to Codex for its contributions","Powered by Godot Engine"]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(args,name):
    print(name,flush=True)
    with (EDIT/(name+".log")).open("w") as log:
        p=subprocess.run(args,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT)
    if p.returncode:
        raise RuntimeError((EDIT/(name+".log")).read_text()[-8000:])


def text(value,name,size,y,x="(w-tw)/2",scene=False):
    assert value.isascii()
    path=EDIT/("text-"+name+".txt");path.write_text(value)
    style="fontcolor=0x302a22:box=1:boxcolor=0xeee3cc@0.86:boxborderw=12:enable='lt(t,1.5)'" if scene else "fontcolor=0xeee3cc:shadowcolor=black@0.4:shadowx=0:shadowy=2"
    return f"drawtext=fontfile='{FONT}':textfile='{path}':fontsize={size}:x={x}:y={y}:{style}"


def encode(arguments,filters,output,seconds):
    inputs={p:digest(Path(p)) for p in arguments if Path(p).is_file()}
    for f in filters:
        for p in re.findall(r"textfile='([^']+)'",f):inputs[p]=digest(Path(p))
    fingerprint=hashlib.sha256(json.dumps([arguments,filters,seconds,inputs],sort_keys=True).encode()).hexdigest()
    cache=output.with_suffix(".cache.json")
    if output.is_file() and cache.is_file() and json.loads(cache.read_text()).get("fingerprint")==fingerprint:
        print("reuse "+output.stem,flush=True);return
    run(["ffmpeg","-y","-hide_banner","-loglevel","error",*arguments,"-vf",",".join(filters),
         "-t",str(seconds),"-an","-r","30","-c:v","libx264","-preset","slow","-crf","17",
         "-profile:v","high","-pix_fmt","yuv420p","-threads","6","-movflags","+faststart",str(output)],output.stem)
    cache.write_text(json.dumps({"fingerprint":fingerprint})+"\n")


def native_frame(folder,number):
    p=folder/f"{number:04d}.png"
    assert p.is_file(),p
    with Image.open(p) as im:
        assert im.size==(3840,2160),f"Not a native 4K frame: {p}"
    return p


def audio_mix(battle,start,seconds):
    raw=subprocess.check_output(["ffmpeg","-hide_banner","-loglevel","error","-i",str(MUSIC),
        "-t",str(seconds),"-af",f"loudnorm=I=-18:TP=-2:LRA=9,afade=t=in:st=0:d=0.6,afade=t=out:st={seconds-1.5}:d=1.5",
        "-ar","48000","-ac","2","-f","f32le","pipe:1"])
    a=np.frombuffer(raw,dtype="<f4").reshape(-1,2).copy()
    length=round(seconds*48000);a=np.pad(a[:length],((0,max(0,length-len(a))),(0,0)))
    sounds={};events=[];last={"fire":-10.0,"impact":-10.0}
    for event in battle.get("event_timeline",[]):
        kind=event["kind"]
        if kind not in last:continue
        t=event["frame"]/30
        if t-last[kind]<.6:continue
        identity=str(event.get("weapon",""))+" "+str(event.get("spec",""))
        if kind=="fire" and not any(x in identity for x in ["tank","artillery"]):continue
        last[kind]=t
        name="fire_cannon_1.wav" if kind=="fire" else "impact_medium_1.wav"
        path=ROOT/"assets/audio/revision_v8/sfx"/name
        if name not in sounds:
            pcm=np.frombuffer(subprocess.check_output(["ffmpeg","-hide_banner","-loglevel","error",
                "-i",str(path),"-ar","48000","-ac","2","-f","f32le","pipe:1"]),dtype="<f4").reshape(-1,2)
            sounds[name]=pcm*(.08/max(float(np.max(np.abs(pcm))),1e-6))
        offset=round((start+t)*48000);effect=sounds[name][:length-offset]
        a[offset:offset+len(effect)]+=effect
        events.append({"source_frame":event["frame"],"timeline_seconds":start+t,"kind":kind,
                       "file":str(path.relative_to(ROOT)),"sha256":digest(path)})
    peak=float(np.max(np.abs(a)))
    if peak>.95:a*=.95/peak
    path=EDIT/"soundtrack.wav"
    with wave.open(str(path),"wb") as wav:
        wav.setparams((2,2,48000,0,"NONE","not compressed"))
        wav.writeframes((np.clip(a,-1,1)*32767).astype("<i2").tobytes())
    return path,events


def decode(cap,seconds):
    cap.set(cv2.CAP_PROP_POS_MSEC,seconds*1000);ok,frame=cap.read()
    if not ok:raise RuntimeError(f"Cannot decode {seconds}")
    return frame


def scenery_flow(cap,start,duration):
    first=cv2.cvtColor(decode(cap,start+1.7),cv2.COLOR_BGR2GRAY)
    mask=np.full(first.shape,255,np.uint8);mask[:120,:]=0
    corners=cv2.goodFeaturesToTrack(first,1800,.025,10,mask=mask)
    reports=[]
    for local in [duration*.70,duration-.15]:
        current=cv2.cvtColor(decode(cap,start+local),cv2.COLOR_BGR2GRAY)
        end,valid,error=cv2.calcOpticalFlowPyrLK(first,current,corners,None,winSize=(21,21),maxLevel=3)
        keep=(valid[:,0]==1)&(error[:,0]<14)
        matrix,inliers=cv2.estimateAffinePartial2D(corners[keep,0,:],end[keep,0,:],
            method=cv2.RANSAC,ransacReprojThreshold=.4,maxIters=4000)
        assert matrix is not None
        translation=float(np.linalg.norm(matrix[:,2]))
        assert translation<.35,f"Unexpected scenery drift: {translation}"
        reports.append({"local_time":local,"translation_pixels":translation,
                        "matched_features":int(np.sum(keep)),"stationary_inliers":int(np.sum(inliers))})
    return reports


def main():
    EDIT.mkdir(parents=True,exist_ok=True)
    preparing="--prepare-stills" in sys.argv
    protected=[ROOT/"README.md",*sorted((ROOT/"media").glob("*")),*sorted((ROOT/".github/workflows").glob("*"))]
    protected={str(p):digest(p) for p in protected if p.is_file()}
    models=json.loads((OUT/"models/stills_manifest.json").read_text())
    battle=json.loads((OUT/"battle/capture_manifest.json").read_text())
    model_map={s["shot"]:s for s in models["shots"]}
    assert models["mode"]=="stills" and models["resolution"]==[3840,2160]
    assert battle["resolution"]==[3840,2160] and (preparing or battle["frames"]>=210)
    assert battle["map_size"]==320 and battle["camera_fixed_every_frame"] and battle["geometry_unchanged"]
    clips=[];segments=[];timeline=2.0
    cover=native_frame(OUT/"models/base",0)
    opening=EDIT/"00-opening.mp4"
    encode(["-loop","1","-framerate","30","-i",str(cover)],[
        "scale=1920:1080:flags=lanczos","setsar=1","drawbox=color=0x211e18@0.55:t=fill",
        text("PAPER FRONT","intro-title",112,340),
        text("A paper-crafted real-time strategy game","intro-subtitle",34,520),
        "fade=t=in:st=0:d=0.2"],opening,2)
    clips.append(opening)
    battle_start=0
    for i,(name,duration,caption) in enumerate(PLAN,1):
        if name=="battle" and preparing:
            timeline+=duration;continue
        folder=OUT/"battle" if name=="battle" else OUT/"models"/name
        evidence=battle if name=="battle" else model_map[name]
        if name!="battle":
            assert evidence["resolution"]==[3840,2160] and evidence["frames"]==1
            assert evidence["camera_locked"] and evidence["lod_override"]==0
            assert not evidence["lod_enabled"] and not evidence["scenery_lod_enabled"]
            assert not evidence["dof_near"] and not evidence["dof_far"] and evidence["render_scale"]==1
            assert evidence["msaa"]=="4x" and evidence["lod_counts"][1:]==[0,0]
            assert evidence["map_size"] in [192,320]
        native_frame(folder,0)
        if name=="battle":native_frame(folder,round(duration*FPS)-1)
        output=EDIT/f"{i:02}-{name}.mp4"
        source_arguments=["-framerate","30","-i",str(folder/"%04d.png")] if name=="battle" else ["-loop","1","-framerate","30","-i",str(folder/"0000.png")]
        encode(source_arguments,[
            f"trim=duration={duration}","setpts=PTS-STARTPTS","scale=1920:1080:flags=lanczos","setsar=1",
            text(caption,name+"-caption",28,38,60,scene=True)],output,duration)
        clips.append(output)
        segments.append({"id":name,"timeline_start":timeline,"duration_seconds":duration,"caption":caption,
                         "caption_visible_seconds":1.5,"source_resolution":[3840,2160],"presentation":"actual dynamic battle" if name=="battle" else "native 4K in-engine still, fixed camera", "evidence":evidence})
        if name=="battle":battle_start=timeline
        timeline+=duration
    closing=EDIT/"99-closing.mp4"
    encode(["-loop","1","-framerate","30","-i",str(cover)],[
        "scale=1920:1080:flags=lanczos","setsar=1","drawbox=color=0x211e18@0.65:t=fill",
        text("BUILD YOUR FRONT.","end-title",78,220),text("WINDOWS / LINUX","end-platforms",30,380),
        text("github.com/flitting/PaperFront","end-url",34,456),
        text(CREDITS[0],"end-codex",32,650),text(CREDITS[1],"end-godot",32,706),
        "fade=t=out:st=3.65:d=0.35"],closing,4)
    clips.append(closing)
    duration=timeline+4;assert duration==29
    if preparing:
        print("Native 4K still segments encoded; dynamic battle and final assembly remain pending.",flush=True);return
    concat=EDIT/"clips.txt";concat.write_text("".join(f"file '{p}'\n" for p in clips))
    audio,sound_events=audio_mix(battle,battle_start,duration)
    movie=OUT/"preview.mp4"
    run(["ffmpeg","-y","-hide_banner","-loglevel","error","-f","concat","-safe","0","-i",str(concat),
        "-i",str(audio),"-map","0:v","-map","1:a","-t",str(duration),"-c:v","copy","-c:a","aac",
        "-b:a","192k","-ar","48000","-ac","2","-movflags","+faststart",str(movie)],"preview")
    probe=json.loads(subprocess.check_output(["ffprobe","-v","error","-show_streams","-show_format","-of","json",str(movie)]))
    (OUT/"ffprobe.json").write_text(json.dumps(probe,indent=2)+"\n")
    video=next(s for s in probe["streams"] if s["codec_type"]=="video")
    assert [video["width"],video["height"]]==[1920,1080] and video["r_frame_rate"]=="30/1"
    assert float(probe["format"]["duration"])==29 and video["codec_name"]=="h264"
    cap=cv2.VideoCapture(str(movie))
    flow={s["id"]:scenery_flow(cap,s["timeline_start"],s["duration_seconds"]) for s in segments if s["id"] in ["base","battle"]}
    times=[1.0]+[s["timeline_start"]+s["duration_seconds"]/2 for s in segments]+[27.0]
    sheet=Image.new("RGB",(1920,((len(times)+1)//2)*580),"#211e18");draw=ImageDraw.Draw(sheet)
    for i,t in enumerate(times):
        frame=decode(cap,t);cv2.imwrite(str(OUT/f"review-{i+1:02}.jpg"),frame,[cv2.IMWRITE_JPEG_QUALITY,96])
        thumb=Image.fromarray(cv2.cvtColor(frame,cv2.COLOR_BGR2RGB));thumb.thumbnail((950,535))
        x,y=(i%2)*960,(i//2)*580;sheet.paste(thumb,(x,y));draw.text((x+12,y+543),f"{t:.2f}s",fill="white")
    cap.release();sheet.save(OUT/"contactsheet.jpg",quality=95)
    # Poster comes directly from new native-4K armor, not an enlarged old video.
    poster_source=native_frame(OUT/"models/armor",0)
    run(["ffmpeg","-y","-hide_banner","-loglevel","error","-i",str(poster_source),"-vf",",".join([
        "scale=1920:1080:flags=lanczos","setsar=1","drawbox=color=0x211e18@0.5:t=fill",
        text("PAPER FRONT","poster-title",112,310),text("A paper-crafted RTS","poster-subtitle",36,475),
        text("LOCAL PREVIEW","poster-local",26,946)]),"-frames:v","1","-q:v","1",str(OUT/"poster.jpg")],"poster")
    assert all(Path(p).is_file() and digest(Path(p))==h for p,h in protected.items()),"Published workspace content changed during local preview"
    provenance={"local_preview_only":True,"published":False,"language":"English","duration_seconds":29,
        "output_resolution":[1920,1080],"source_resolution":[3840,2160],"fps":30,"h264_crf":17,"preset":"slow",
        "source_downsample":"One native 3840x2160 to 1920x1080 Lanczos downsample; never enlarged from an older video",
        "camera_locked":True,"hud_visible":False,"editing":"Fixed cameras, hard cuts; no continuous reframing. Small English corner labels are shown for 1.5 seconds, with no full-width subtitle strip.",
        "scenes":segments,"credits":CREDITS,"music":{"path":str(MUSIC.relative_to(ROOT)),"sha256":digest(MUSIC),"license":"CC0-1.0","manifest":"assets/audio/music/manifest.json"},
        "sound_effects":{"license":"Provider-generated under OpenRouter / ByteDance Seed Audio terms; not CC0","manifest":"assets/audio/revision_v8/sfx/manifest.json","events":sound_events},
        "models_manifest_sha256":digest(OUT/"models/stills_manifest.json"),"battle_manifest_sha256":digest(OUT/"battle/capture_manifest.json"),
        "files":{"preview.mp4":{"bytes":movie.stat().st_size,"sha256":digest(movie)},"poster.jpg":{"sha256":digest(OUT/"poster.jpg")}},
        "published_files_untouched":True}
    (OUT/"provenance.json").write_text(json.dumps(provenance,indent=2)+"\n")
    validation={"duration_seconds":29,"source_resolution":[3840,2160],"output_resolution":[1920,1080],"camera_locked":True,
        "scenery_optical_flow":flow,"sampled_timestamps":times,"all_sources_no_48_map":True,
        "source_lod0_native_msaa4x_no_dof":True,"published_files_untouched":True,"video_sha256":digest(movie)}
    (OUT/"validation.json").write_text(json.dumps(validation,indent=2)+"\n")
    print(f"LOCAL PREVIEW READY: {movie}, 29s, {movie.stat().st_size/1024/1024:.2f} MiB")


if __name__=="__main__":
    main()
