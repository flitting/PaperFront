#!/usr/bin/env python3
"""Compatibility entry point for all 22 distinct paper infantry roles."""
from pathlib import Path
import subprocess
from generate_distinct_infantry import generate
if __name__ == "__main__":
    generate()
    subprocess.run(["godot", "--headless", "--path", str(Path(__file__).resolve().parents[1]), "--script", "res://tools/register_expanded_infantry_contours.gd"], check=True)
