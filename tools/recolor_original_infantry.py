#!/usr/bin/env python3
"""Compatibility entry point for the current original-palette card pipeline.

Owner colors are limited to original insignia. Never regenerate the retired
helmet/torso color replacement or the large central owner panel.
"""
from restore_original_infantry_palette import main
if __name__ == "__main__":
    main()
