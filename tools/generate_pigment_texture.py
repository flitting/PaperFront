#!/usr/bin/env python3
"""Deterministic CC0 scalar pigment atlas, sampled with filtering/mipmaps in Godot."""
from pathlib import Path
import random
from PIL import Image

output = Path(__file__).resolve().parents[1] / 'assets/textures/pigment_noise.png'
output.parent.mkdir(parents=True, exist_ok=True)
rng = random.Random(440044)
image = Image.new('L', (64, 64))
image.putdata([rng.randrange(256) for _ in range(64 * 64)])
image.save(output)
print(output)
