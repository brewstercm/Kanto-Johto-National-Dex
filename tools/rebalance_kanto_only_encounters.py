"""Move every J2-only completion species into the Kanto encounter overlay."""
from __future__ import annotations

import json
import statistics
from pathlib import Path

from validate_distributed_progression import LuaTableParser

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "data" / "extra_encounters.lua"
REPORT = ROOT / "KANTO_ONLY_ENCOUNTER_QA.json"


def load_table(path: Path):
    return LuaTableParser(path.read_text(encoding="utf-8-sig")).value()


def quote(value: str) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"))


def dump_slot(slot: dict) -> str:
    return "{species=" + quote(slot["species"]) + ",level=" + str(int(slot["level"])) + "}"


def dump_table(data: dict) -> str:
    pieces = ["return {chance=" + str(int(data.get("chance", 25))) + ",maps={"]
    maps = data["maps"]
    map_rows = []
    for map_id in sorted(maps):
        terrain_rows = []
        for terrain in ("grass", "indoor", "water"):
            pool = maps[map_id].get(terrain)
            if pool:
                terrain_rows.append(terrain + "={" + ",".join(dump_slot(s) for s in pool) + "}")
        map_rows.append("[" + quote(map_id) + "]={" + ",".join(terrain_rows) + "}")
    pieces.append(",".join(map_rows))
    pieces.append("}}\n")
    return "".join(pieces)


data = load_table(SOURCE)
all_maps = data["maps"]
kanto_maps = {key: value for key, value in all_maps.items() if not key.startswith("J2_")}
j2_maps = {key: value for key, value in all_maps.items() if key.startswith("J2_")}

kanto_species = {
    slot["species"]
    for row in kanto_maps.values()
    for pool in row.values()
    for slot in pool
}
j2_occurrences: dict[str, list[tuple[str, int, str]]] = {}
for map_id, row in j2_maps.items():
    for terrain, pool in row.items():
        for slot in pool:
            j2_occurrences.setdefault(slot["species"], []).append(
                (terrain, int(slot["level"]), map_id)
            )

missing = sorted(set(j2_occurrences) - kanto_species)
targets: list[dict] = []
for map_id, row in sorted(kanto_maps.items()):
    for terrain, pool in row.items():
        if not pool:
            continue
        targets.append({
            "map": map_id,
            "terrain": terrain,
            "pool": pool,
            "average": statistics.mean(int(slot["level"]) for slot in pool),
            "added": 0,
        })

assignments = []
for species in missing:
    occurrences = j2_occurrences[species]
    levels = [level for _, level, _ in occurrences]
    level = int(round(statistics.median(levels)))
    terrain_counts = {}
    for terrain, _, _ in occurrences:
        terrain_counts[terrain] = terrain_counts.get(terrain, 0) + 1
    preferred = sorted(terrain_counts, key=lambda key: (-terrain_counts[key], key))[0]
    candidates = [target for target in targets if target["terrain"] == preferred]
    if not candidates:
        candidates = targets
    # Match progression first, then spread additions so one route never owns
    # the entire former Johto roster.
    target = min(candidates, key=lambda row: (
        abs(row["average"] - level) + row["added"] * 1.75,
        row["added"], row["map"], row["terrain"],
    ))
    target["pool"].append({"species": species, "level": level})
    target["added"] += 1
    assignments.append({
        "species": species,
        "map": target["map"],
        "terrain": target["terrain"],
        "level": level,
        "sourceMaps": sorted({where for _, _, where in occurrences}),
    })

data["maps"] = kanto_maps
SOURCE.write_text(dump_table(data), encoding="utf-8")

final_species = {
    slot["species"]
    for row in kanto_maps.values()
    for pool in row.values()
    for slot in pool
}
report = {
    "version": "0.9.11-kanto-only",
    "kantoMaps": len(kanto_maps),
    "removedJ2Maps": len(j2_maps),
    "kantoSpeciesBefore": len(kanto_species),
    "relocatedJohtoOnlySpecies": len(assignments),
    "kantoSpeciesAfter": len(final_species),
    "johtoOnlySpeciesRemaining": sorted(set(j2_occurrences) - final_species),
    "assignments": assignments,
}
REPORT.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
print(json.dumps({key: report[key] for key in (
    "kantoMaps", "removedJ2Maps", "kantoSpeciesBefore",
    "relocatedJohtoOnlySpecies", "kantoSpeciesAfter",
)}))
