#!/usr/bin/env python3
"""Validate a trailer update while preserving the existing player packages."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / "artifacts/trailer-publication"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load(name: str):
    return json.loads((WORK / name).read_text())


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verify-upload", action="store_true")
    args = parser.parse_args()
    tag = os.environ["PAPER_FRONT_RELEASE_TAG"]
    if not re.fullmatch(r"v\d+\.\d+\.\d+", tag):
        raise ValueError("Expected an existing numeric release tag")
    original = load("original-release.json")
    if original["tag_name"] != tag or original["draft"]:
        raise ValueError("Expected the published release selected by tag")
    assets = {asset["name"]: asset for asset in original["assets"]}
    packages = [f"PaperFront-{tag}-linux-x86_64.tar.gz", f"PaperFront-{tag}-windows-x86_64.zip"]
    package_digests = {name: assets[name]["digest"] for name in packages}

    if args.verify_upload:
        published = {asset["name"]: asset for asset in load("published-release.json")["assets"]}
        for name, digest in package_digests.items():
            if published[name]["digest"] != digest or published[name]["id"] != assets[name]["id"]:
                raise ValueError("Player package was unexpectedly replaced: " + name)
        for path in [ROOT / "media/paper-front-trailer.mp4", ROOT / "media/poster.jpg",
                     WORK / "trailer-provenance.json", WORK / "SHA256SUMS"]:
            if published[path.name]["state"] != "uploaded" or published[path.name]["digest"] != "sha256:" + sha256(path):
                raise ValueError("Uploaded media differs: " + path.name)
        print("Verified: trailer, poster, provenance and checksums; player packages unchanged.")
        return

    sums_path = WORK / "SHA256SUMS"
    if assets["SHA256SUMS"]["digest"] != "sha256:" + sha256(sums_path):
        raise ValueError("Downloaded checksum file differs from GitHub's digest")
    sums = {}
    for line in sums_path.read_text().splitlines():
        digest, name = line.split("  ", 1)
        if not re.fullmatch(r"[0-9a-f]{64}", digest) or Path(name).name != name:
            raise ValueError("Invalid checksum entry")
        sums[name] = digest
    for name, digest in package_digests.items():
        if "sha256:" + sums[name] != digest:
            raise ValueError("Player package checksum mismatch: " + name)

    probe = load("ffprobe.json")
    video = next(stream for stream in probe["streams"] if stream["codec_type"] == "video")
    audio = next(stream for stream in probe["streams"] if stream["codec_type"] == "audio")
    duration = float(probe["format"]["duration"])
    if not 0 < duration <= 30 or video["codec_name"] != "h264" or audio["codec_name"] != "aac":
        raise ValueError("Expected an H.264/AAC trailer lasting at most 30 seconds")
    if video["width"] < 1280 or video["height"] < 720:
        raise ValueError("Trailer resolution is too low")
    provenance = json.loads((ROOT / "media/provenance.json").read_text())
    if provenance["language"] != "English" or not provenance.get("camera_locked"):
        raise ValueError("Expected an English trailer with fixed cameras")
    if abs(float(provenance["duration_seconds"]) - duration) > 0.1:
        raise ValueError("Trailer duration does not match its provenance")
    if not provenance["scenes"] or any(int(scene["map_size"]) not in (192, 320) for scene in provenance["scenes"]):
        raise ValueError("Only current 192/320 maps may appear")
    if provenance["files"]["paper-front-trailer.mp4"]["sha256"] != sha256(ROOT / "media/paper-front-trailer.mp4"):
        raise ValueError("Trailer hash does not match its provenance")
    provenance["publication"] = {
        "source_commit": os.environ["GITHUB_SHA"],
        "workflow_url": f"https://github.com/{os.environ['GITHUB_REPOSITORY']}/actions/runs/{os.environ['GITHUB_RUN_ID']}",
        "scope": "Promotional media update; existing player archives are preserved.",
    }
    (WORK / "trailer-provenance.json").write_text(json.dumps(provenance, indent=2, ensure_ascii=False) + "\n")
    for path in [ROOT / "media/paper-front-trailer.mp4", ROOT / "media/poster.jpg", WORK / "trailer-provenance.json"]:
        sums[path.name] = sha256(path)
    sums_path.write_text("".join(f"{digest}  {name}\n" for name, digest in sums.items()))
    print(f"Validated {duration:.3f}s English trailer and prepared checksums.")


if __name__ == "__main__":
    main()
