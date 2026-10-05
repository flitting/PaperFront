#!/usr/bin/env python3
"""Fetch the exact installed eSpeak NG Ubuntu source; verify DSC SHA-256 entries.

Only this official Ubuntu directory is contacted. This does not install or run
source code, submit data, call TTS providers, or change system packages.
"""
import hashlib
import json
from pathlib import Path
import re
import subprocess
import urllib.request

BASE = "https://archive.ubuntu.com/ubuntu/pool/main/e/espeak-ng/"
FOLDER = Path(__file__).resolve().parent
version = subprocess.check_output(["dpkg-query", "-W", "-f=${Version}", "libespeak-ng1"], text=True).strip()
data_version = subprocess.check_output(["dpkg-query", "-W", "-f=${Version}", "espeak-ng-data"], text=True).strip()
if version != "1.51+dfsg-12build1" or data_version != version:
    raise RuntimeError(f"Source kit is pinned to reviewed Ubuntu 1.51+dfsg-12build1; installed {version}/{data_version}")
dsc_name = f"espeak-ng_{version}.dsc"


def fetch(name):
    if Path(name).name != name or name.startswith("."):
        raise RuntimeError("Unexpected source archive filename")
    path = FOLDER / name
    with urllib.request.urlopen(BASE + name, timeout=40) as response:
        data = response.read(32 * 1024 * 1024)
        if response.read(1):
            raise RuntimeError("Source artifact exceeds the expected small-source limit")
    if path.exists() and path.read_bytes() != data:
        raise RuntimeError("Refusing to overwrite an existing different source artifact")
    path.write_bytes(data)
    return path, data


dsc_path, dsc = fetch(dsc_name)
text = dsc.decode("utf-8")
match = re.search(r"(?m)^Version: (.+)$", text)
if not match or match.group(1).strip() != version:
    raise RuntimeError("Official source version does not match installed generator")
lines = text.splitlines()
start = lines.index("Checksums-Sha256:") + 1
archives = []
for line in lines[start:]:
    if not line.startswith(" "):
        break
    digest, size, name = line.split()
    path, data = fetch(name)
    actual = hashlib.sha256(data).hexdigest()
    if actual != digest or len(data) != int(size):
        raise RuntimeError(f"Source SHA-256/size mismatch: {name}")
    archives.append({"file": name, "bytes": len(data), "sha256": actual, "dsc_verified": True, "url": BASE + name})
if len(archives) != 2:
    raise RuntimeError("Expected complete upstream orig and Ubuntu Debian patch tarballs")
report = {"package": "espeak-ng", "installed_binary_version": version, "installed_data_version": data_version,
          "source_version": version, "official_origin": BASE,
          "dsc": {"file": dsc_path.name, "sha256": hashlib.sha256(dsc).hexdigest(), "bytes": len(dsc), "url": BASE + dsc_path.name},
          "verification": "Official Ubuntu HTTPS DSC; both source tarballs match every DSC SHA-256 and byte count. DSC signature is retained, not asserted locally verified.",
          "archives": archives}
(FOLDER / "source_download_manifest.json").write_text(json.dumps(report, indent=2) + "\n")
print(json.dumps(report, indent=2))
