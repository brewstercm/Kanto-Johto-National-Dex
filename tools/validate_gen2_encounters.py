"""Validate the generated Gen 2 overlay against an imported G/S/C cache."""
from __future__ import annotations

import json
import sys
from pathlib import Path

from build_gen2_encounters import LuaTableParser, ROOT


def load(path: Path):
    return LuaTableParser(path.read_text(encoding="utf-8-sig")).value()


def main():
    if len(sys.argv) != 2:
        raise SystemExit("usage: validate_gen2_encounters.py <generated-cache-directory>")
    cache = Path(sys.argv[1])
    overlay = load(ROOT / "data" / "extra_encounters_gen2.lua")
    maps = load(cache / "maps.lua")
    native = load(cache / "encounters.lua")
    failures = []
    species = []
    for map_id, terrains in overlay["maps"].items():
        if map_id not in maps:
            failures.append(f"missing map: {map_id}")
        for terrain, rows in terrains.items():
            native_group = "water" if terrain == "water" else "grass"
            if map_id not in native.get(native_group, {}):
                failures.append(f"no native {native_group} encounters: {map_id}")
            for row in rows:
                species.append(row["species"])
                if not 2 <= int(row["level"]) <= 100:
                    failures.append(f"invalid level: {map_id}/{row['species']}")
    duplicates = len(species) - len(set(species))
    if len(species) != 774:
        failures.append(f"expected 774 species, got {len(species)}")
    if duplicates:
        failures.append(f"duplicate species: {duplicates}")
    report = {
        "maps": len(overlay["maps"]),
        "species": len(species),
        "duplicates": duplicates,
        "failures": failures,
    }
    print(json.dumps(report, indent=2))
    if failures:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
