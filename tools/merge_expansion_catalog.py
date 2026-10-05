#!/usr/bin/env python3
"""Add expansion content while preserving the current simulation configuration.

This is an asset/data authoring utility, not a test or a rules validator. It only
writes entries owned by iron/sky and their paper-card contours. Read the current
rules at merge time so concurrent economy or performance edits remain intact.
"""
import json
from pathlib import Path
from faction_balance import apply_balance
from naval_catalog import apply as apply_naval
from creator_hand_catalog import apply as apply_creator_hand

ROOT = Path(__file__).resolve().parents[1]


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def main():
    delta_path = ROOT / "data/faction_expansion.json"
    delta = json.loads(delta_path.read_text())
    rules_path = ROOT / "data/rules.json"
    rules = json.loads(rules_path.read_text())
    for category in ("factions", "buildings", "units", "weapons"):
        for key, value in delta[category].items():
            if category in ("buildings", "units"):
                portrait = ROOT / "assets/cards" / (key + "_portrait.png")
                if portrait.exists():
                    value["animations"]["idle"] = "res://assets/cards/" + portrait.name
            rules[category][key] = value
    apply_balance(rules)
    apply_naval(rules)
    apply_creator_hand(rules)
    apply_balance(delta)
    write_json(rules_path, rules)
    write_json(delta_path, delta)
    contour_path = ROOT / "assets/cards/contours.json"
    contours = json.loads(contour_path.read_text())
    contours.update(json.loads((ROOT / "data/faction_expansion_contours.json").read_text()))
    write_json(contour_path, contours)
    print("Merged iron/sky catalog and paper-card contours.")


if __name__ == "__main__":
    main()
