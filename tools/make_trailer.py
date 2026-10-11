#!/usr/bin/env python3
"""Encode a 29-second English trailer from fixed-camera gameplay footage.

python3 tools/make_trailer.py
Add --render to recapture the current action and map/UI scenes first.
Requires Godot for capture, ffmpeg, ffprobe, Noto Sans, OpenCV, NumPy and Pillow.
"""
from __future__ import annotations
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import subprocess
import wave
import cv2
import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "artifacts/trailer_revision_20261011"
WORK = BASE / "edit"
MEDIA = ROOT / "media"
FONT = Path("/usr/share/fonts/truetype/noto/NotoSans-Regular.ttf")
MUSIC = ROOT / "assets/audio/music/battle_city.wav"
VW, VH, VX, VY = 1216, 684, 32, 36
CREDITS = ["Thanks to Codex for its contributions", "Powered by Godot Engine"]


def path(value):
    p = Path(value)
    return p if p.is_absolute() else ROOT / p


def digest(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def run(command, name, env=None):
    print(name, flush=True)
    with (WORK / (name + ".log")).open("w") as log:
        result = subprocess.run(command, cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT)
    if result.returncode:
        raise RuntimeError((WORK / (name + ".log")).read_text()[-8000:])


def label(text, name, size, y, x="(w-tw)/2"):
    assert text.isascii(), "Promotional text must be English"
    p = WORK / ("text-" + name + ".txt")
    p.write_text(text)
    return (f"drawtext=fontfile='{FONT}':textfile='{p}':fontsize={size}:"
            f"fontcolor=0xeee3cc:x={x}:y={y}:shadowcolor=black@0.35:shadowx=0:shadowy=1")


def inputs(source):
    p = str(path(source["path"]))
    if source["kind"] == "sequence":
        return ["-framerate", str(source["fps"]), "-start_number",
                str(source.get("start_number", 0)), "-i", p]
    return ["-i", p]


def screenshot(source, seconds, output):
    run(["ffmpeg", "-y", "-hide_banner", "-loglevel", "error", *inputs(source),
         "-vf", f"select='gte(t,{seconds})'", "-frames:v", "1", "-q:v", "2", str(output)], output.stem)


def encode(arguments, filters, output, seconds):
    run(["ffmpeg", "-y", "-hide_banner", "-loglevel", "error", *arguments,
         "-vf", ",".join(filters), "-an", "-t", str(seconds), "-r", "30", "-c:v", "libx264",
         "-preset", "medium", "-crf", "20", "-pix_fmt", "yuv420p", "-threads", "4",
         "-movflags", "+faststart", str(output)], output.stem)


def frame(cap, seconds):
    cap.set(cv2.CAP_PROP_POS_MSEC, seconds * 1000)
    ok, image = cap.read()
    if not ok:
        raise RuntimeError(f"Cannot decode frame at {seconds}")
    return image


def verify_background(cap, segment, source):
    """Track scenery only; moving units and HUD updates are excluded."""
    start, duration = segment["timeline_start"], segment["duration"]
    first = frame(cap, start + .2)
    gray = cv2.cvtColor(first, cv2.COLOR_BGR2GRAY)
    mask = np.zeros(gray.shape, np.uint8)
    sw, sh = source["native_size"]
    for x, y, width, height in source["static_regions"]:
        left, top = round(VX + x * VW/sw), round(VY + y * VH/sh)
        mask[top:round(top + height*VH/sh), left:round(left + width*VW/sw)] = 255
    points = cv2.goodFeaturesToTrack(gray, 400, .015, 7, mask=mask)
    if points is None or len(points) < 12:
        raise RuntimeError("Too few fixed scenery anchors: " + segment["source"])
    samples = []
    for t in np.arange(.7, duration-.15, .5):
        current = cv2.cvtColor(frame(cap, start+float(t)), cv2.COLOR_BGR2GRAY)
        tracked, status, error = cv2.calcOpticalFlowPyrLK(gray, current, points, None, winSize=(21,21), maxLevel=3)
        back, bs, _ = cv2.calcOpticalFlowPyrLK(current, gray, tracked, None, winSize=(21,21), maxLevel=3)
        valid = ((status[:,0] == 1) & (bs[:,0] == 1)
                 & (np.linalg.norm(back-points, axis=2)[:,0] < .7) & (error[:,0] < 18))
        vectors = (tracked-points)[valid,0,:]
        if len(vectors) < 10:
            raise RuntimeError("Fixed scenery tracking lost its anchors")
        median = np.median(vectors, axis=0)
        samples.append({"local_time":float(t), "tracked_points":len(vectors),
                        "median_dx":float(median[0]), "median_dy":float(median[1]),
                        "global_translation_pixels":float(np.linalg.norm(median))})
    maximum = max(s["global_translation_pixels"] for s in samples)
    assert maximum <= .35, f"Fixed scenery moves {maximum:.3f}px in {segment['source']}"
    last = frame(cap, start+duration-.2)
    difference = cv2.absdiff(first[VY:,VX:VX+VW], last[VY:,VX:VX+VW])
    changed = float(np.mean(np.max(difference, axis=2) > 18))
    if source["role"] in ["combat", "construction"]:
        assert changed > .001, "Action footage must visibly progress"
    return {"source":segment["source"], "static_regions":source["static_regions"],
            "initial_points":len(points), "samples":samples,
            "maximum_global_translation_pixels":maximum, "changed_viewport_fraction":changed, "result":"pass"}


def recapture():
    with (BASE / "capture.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        jobs = [("map_ui", "tools/capture_trailer_map_ui.gd", {"PAPER_FRONT_TRAILER_MAP_UI_MOTION":"1"})]
        jobs += [(name, "tools/capture_trailer_action.gd", {"PAPER_FRONT_ACTION_SHOT":name})
                 for name in ["construction", "combat"]]
        for name, script, changes in jobs:
            env = os.environ.copy()
            env.pop("PAPER_FRONT_ACTION_FRAMES", None)
            env.update(changes)
            run(["python3", "tools/run_offscreen_capture.py", script, "--size", "1600x900",
                 "--timeout", "1800", "--bootstrap", "--report",
                 f"artifacts/trailer_revision_20261011/{name}-recapture-report.json"],
                "capture-" + name, env)


def soundtrack(segments, sources, duration):
    """Quiet native effects follow recorded combat events, never invented beats."""
    data = subprocess.check_output([
        "ffmpeg","-hide_banner","-loglevel","error","-i",str(MUSIC),"-t",str(duration),
        "-af",f"loudnorm=I=-18:TP=-2:LRA=9,afade=t=in:st=0:d=0.6,afade=t=out:st={duration-1.5}:d=1.5",
        "-ar","48000","-ac","2","-f","f32le","pipe:1"])
    music = np.frombuffer(data,dtype="<f4").reshape(-1,2).copy()
    length = round(duration*48000)
    music = np.pad(music[:length],((0,max(0,length-len(music))),(0,0)))
    events = []
    effects = {}
    for segment in segments:
        source = sources[segment["source"]]
        if source["role"] != "combat": continue
        evidence = json.loads(path(source["evidence_path"]).read_text())
        last = {"fire":-10.0,"impact":-10.0}
        for event in evidence.get("event_timeline",[]):
            kind = event["kind"]
            if kind not in last: continue
            local = event["frame"]/source["fps"] - segment.get("start",0)
            if not 0 <= local < segment["duration"] or local-last[kind] < .55: continue
            weapon_identity = str(event.get("weapon","")) + " " + str(event.get("spec",""))
            if kind == "fire" and not any(v in weapon_identity for v in ["tank","artillery"]): continue
            last[kind] = local
            filename = "fire_cannon_1.wav" if kind == "fire" else "impact_medium_1.wav"
            sound = ROOT/"assets/audio/revision_v8/sfx"/filename
            if filename not in effects:
                raw = subprocess.check_output(["ffmpeg","-hide_banner","-loglevel","error","-i",str(sound),
                    "-ar","48000","-ac","2","-f","f32le","pipe:1"])
                pcm = np.frombuffer(raw,dtype="<f4").reshape(-1,2)
                effects[filename] = pcm * (.085/max(float(np.max(np.abs(pcm))),1e-6))
            when = segment["timeline_start"]+local
            offset = round(when*48000)
            effect = effects[filename][:length-offset]
            music[offset:offset+len(effect)] += effect
            events.append({"timeline_seconds":when,"source":segment["source"],"source_frame":event["frame"],
                "kind":kind,"file":str(sound.relative_to(ROOT)),"sha256":digest(sound),"peak_gain_target_dbfs":-21.4})
    peak = float(np.max(np.abs(music)))
    if peak > .95: music *= .95/peak
    output = WORK/"soundtrack.wav"
    with wave.open(str(output),"wb") as wav:
        wav.setparams((2,2,48000,0,"NONE","not compressed"))
        wav.writeframes((np.clip(music,-1,1)*32767).astype("<i2").tobytes())
    return output, events


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", default="tools/trailer_edit.json")
    parser.add_argument("--render", action="store_true")
    args = parser.parse_args()
    WORK.mkdir(parents=True, exist_ok=True)
    MEDIA.mkdir(exist_ok=True)
    (MEDIA / ".gdignore").touch()
    if args.render:
        recapture()
    edit = json.loads(path(args.manifest).read_text())
    sources, segments = edit["sources"], edit["segments"]
    for name, source in sources.items():
        evidence = json.loads(path(source["evidence_path"]).read_text())
        required_frames = round(max(s.get("start",0)+s["duration"] for s in segments if s["source"]==name)*evidence["fps"])
        source["native_size"] = evidence["resolution"]
        source["fps"] = evidence["fps"]
        source["map_size"] = evidence["map_size"]
        source["map_mode"] = evidence["map_mode"]
        if source["role"] in ["map", "interface"]:
            shot = next(s for s in evidence["shots"] if s["name"] == source["shot_id"])
            assert not evidence["failures"] and evidence["geometry_unchanged"]
            assert shot["frames"] >= required_frames
            source["camera_fixed"] = shot["max_camera_position_drift"] < 1e-6 and shot["max_camera_basis_drift"] < 1e-6
            source["simulation"] = {"time_start":shot["sim_time_start"],"time_end":shot["sim_time_end"],
                "commands":evidence["actions"],"map_geometry_sha256":evidence["map_geometry_sha256"],
                "geometry_unchanged":evidence["geometry_unchanged"],"camera_start":shot["camera_start"],"camera_end":shot["camera_end"]}
        else:
            assert evidence["frames"] >= required_frames and evidence["terrain_edited"] is False
            source["camera_fixed"] = evidence["camera_fixed_every_frame"]
            source["simulation"] = {k:evidence[k] for k in ["sim_time_start","sim_time_end","simulation_multiplier",
                "initial_money","final_money","event_counts","orders","construction_complete_frame","terrain_edited"]}
            ledger = evidence["frames_ledger"]
            sample_indices = {0,len(ledger)//2,len(ledger)-1}
            if evidence["construction_complete_frame"] >= 0:
                sample_indices.add(evidence["construction_complete_frame"])
            source["simulation"]["sampled_states"] = [ledger[i] for i in sorted(sample_indices)]
            source["simulation"]["geometry_unchanged"] = evidence.get("geometry_unchanged",False)
            source["simulation"]["map_geometry_sha256"] = evidence.get("map_geometry_sha256","")
    duration = 2 + sum(s["duration"] for s in segments) + 4
    assert abs(duration-29) < .01 and duration <= 30
    for s in sources.values():
        assert s["map_size"] in [192,320] and s["camera_fixed"] is True and s["fps"] == 30
        assert s["native_size"][0]*9 == s["native_size"][1]*16
        assert path(s["evidence_path"]).is_file() and s["static_regions"]
    assert {"construction","combat"}.issubset({s["role"] for s in sources.values()})
    cover = WORK / "cover.jpg"
    screenshot(sources[segments[0]["source"]], .2, cover)
    opening = WORK / "00-opening.mp4"
    encode(["-loop","1","-framerate","30","-i",str(cover)], [
        "scale=1280:720","setsar=1","drawbox=color=0x171b1c@0.62:t=fill",
        label("PAPER FRONT","opening-title",78,238),
        label("A paper-crafted real-time strategy game","opening-subtitle",25,355),
        label("ACTUAL IN-ENGINE FOOTAGE","opening-note",17,641),"fade=t=in:st=0:d=0.18"], opening, 2)
    clips, timeline = [opening], 2.0
    for i, segment in enumerate(segments,1):
        source = sources[segment["source"]]
        output = WORK / f"{i:02}-{segment['source']}.mp4"
        encode(inputs(source), [
            f"trim=start={segment.get('start',0)}:duration={segment['duration']}",
            "setpts=PTS-STARTPTS","fps=30",f"scale={VW}:{VH}","setsar=1",
            f"pad=1280:720:{VX}:{VY}:color=0x171b1c",
            label("PAPER FRONT",segment["source"]+"-brand",15,9,32),
            label(segment["caption"],segment["source"]+"-caption",19,7)], output, segment["duration"])
        segment["timeline_start"] = timeline
        timeline += segment["duration"]
        clips.append(output)
    closing = WORK / "99-closing.mp4"
    encode(["-loop","1","-framerate","30","-i",str(cover)], [
        "scale=1280:720","setsar=1","drawbox=color=0x171b1c@0.7:t=fill",
        label("BUILD YOUR FRONT.","closing-title",56,157),label("WINDOWS / LINUX","closing-platforms",23,274),
        label("github.com/flitting/PaperFront","closing-url",26,333),
        label(CREDITS[0],"closing-codex",24,455),label(CREDITS[1],"closing-godot",24,501),
        "fade=t=out:st=3.65:d=0.35"], closing, 4)
    clips.append(closing)
    concat = WORK / "clips.txt"
    concat.write_text("".join(f"file '{p}'\n" for p in clips))
    audio_input, sound_events = soundtrack(segments,sources,duration)
    movie = MEDIA / "paper-front-trailer.mp4"
    run(["ffmpeg","-y","-hide_banner","-loglevel","error","-f","concat","-safe","0","-i",str(concat),
         "-i",str(audio_input),"-t",str(duration),"-map","0:v","-map","1:a","-c:v","copy",
         "-c:a","aac","-b:a","160k","-ar","48000","-ac","2",
         "-movflags","+faststart",str(movie)],"final-trailer")
    probe = json.loads(subprocess.check_output(["ffprobe","-v","error","-show_streams","-show_format","-of","json",str(movie)]))
    (WORK/"ffprobe.json").write_text(json.dumps(probe,indent=2)+"\n")
    v = next(s for s in probe["streams"] if s["codec_type"]=="video")
    a = next(s for s in probe["streams"] if s["codec_type"]=="audio")
    assert v["codec_name"]=="h264" and a["codec_name"]=="aac" and v["r_frame_rate"]=="30/1"
    assert [v["width"],v["height"]]==[1280,720] and abs(float(probe["format"]["duration"])-duration)<.05
    assert movie.stat().st_size < 25*1024*1024
    cap = cv2.VideoCapture(str(movie))
    motion = [verify_background(cap,s,sources[s["source"]]) for s in segments]
    times = [1.0]+[s["timeline_start"]+s["duration"]/2 for s in segments]+[duration-2]
    sheet = Image.new("RGB",(1280,((len(times)+1)//2)*380),"#171b1c")
    draw = ImageDraw.Draw(sheet)
    for i,t in enumerate(times):
        image = frame(cap,t)
        cv2.imwrite(str(WORK/f"review-{i+1:02}.jpg"),image,[cv2.IMWRITE_JPEG_QUALITY,94])
        thumb = Image.fromarray(cv2.cvtColor(image,cv2.COLOR_BGR2RGB))
        thumb.thumbnail((630,355))
        x,y = (i%2)*640,(i//2)*380
        sheet.paste(thumb,(x,y));draw.text((x+8,y+359),f"{t:.2f}s",fill="white")
    cap.release()
    sheet.save(WORK/"video-contact-sheet.jpg")
    for name,spec in edit["screenshots"].items():
        screenshot(sources[spec["source"]],spec["time"],MEDIA/name)
    poster_source = WORK/"poster-source.jpg"
    screenshot(sources[edit["poster"]["source"]],edit["poster"]["time"],poster_source)
    run(["ffmpeg","-y","-hide_banner","-loglevel","error","-i",str(poster_source),"-vf",",".join([
        "scale=1920:1080","setsar=1","drawbox=color=0x171b1c@0.6:t=fill",
        label("PAPER FRONT","poster-title",116,360),
        label("Build your base. Command the battle.","poster-subtitle",38,542),
        label("WATCH ACTUAL IN-ENGINE FOOTAGE","poster-note",27,942)]),
         "-frames:v","1","-q:v","2",str(MEDIA/"poster.jpg")],"poster")
    for old in ["gameplay-factions.jpg","gameplay-fleet.jpg"]:
        (MEDIA/old).unlink(missing_ok=True)
    scenes = [{**s,"id":name,"camera_locked":True,"evidence_sha256":digest(path(s["evidence_path"]))}
              for name,s in sources.items()]
    provenance = {
        "title":"Paper Front - actual gameplay showcase","language":"English","duration_seconds":duration,
        "camera_locked":True,"video":"1280x720, H.264, 30 fps","audio":"AAC, 48 kHz stereo",
        "visual_origin":"Controlled current in-engine dynamic gameplay with real construction/combat commands and simulation progression, formal unedited maps and the complete English HUD. Intro and credits use still frames from this footage.",
        "editing":"Only fixed scale and pad. Full 16:9 viewport retained; no frame-dependent reframing. Captions occupy an independent 36px top strip. Map views use hard cuts.",
        "scenes":scenes,"segments":segments,"credits":CREDITS,
        "sound_effects":{"origin":"Selected current nonverbal native sound effects aligned to recorded event frames, mixed quietly below music", "license":"Provider-generated output under OpenRouter / ByteDance Seed Audio service terms; not CC0", "manifest":"assets/audio/revision_v8/sfx/manifest.json", "events":sound_events},
        "music":{"file":str(MUSIC.relative_to(ROOT)),"track_id":"battle_city","license":"CC0-1.0",
                 "origin":"project-authored mathematical synthesis","manifest":"assets/audio/music/manifest.json","sha256":digest(MUSIC)},
        "assets_notice":"assets/LICENSE.md and docs/demo_credits.md govern underlying game assets.",
        "files":{p.name:{"bytes":p.stat().st_size,"sha256":digest(p)} for p in sorted(MEDIA.iterdir()) if p.suffix in [".jpg",".mp4"]}}
    (MEDIA/"provenance.json").write_text(json.dumps(provenance,indent=2)+"\n")
    validation = {
        "duration_seconds":duration,"language":"English","video_sha256":digest(movie),"size_bytes":movie.stat().st_size,
        "map_sizes":{n:s["map_size"] for n,s in sources.items()},"camera_locked":True,
        "fixed_background_optical_flow":motion,"sampled_timestamps":times,
        "full_viewport_layout":{"output":[1280,720],"gameplay":[VX,VY,VW,VH],"caption_strip":[0,0,1280,36]},
        "checks":["Formal 192/320 maps","Real construction and combat progression",
                  "Fixed scenery passes 0.35px optical-flow tolerance","Whole viewport and HUD retained",
                  "English captions and Codex/Godot credits","29 seconds, H.264/AAC, under 25 MiB"]}
    (WORK/"validation.json").write_text(json.dumps(validation,indent=2)+"\n")
    print(f"Verified {movie}: {duration}s, {movie.stat().st_size/1024/1024:.2f} MiB")


if __name__ == "__main__":
    main()
