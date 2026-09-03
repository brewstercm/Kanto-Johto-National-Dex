"""Remove imported J2 encounter records while retaining native Kanto rows."""
from __future__ import annotations

import json
from pathlib import Path

from validate_distributed_progression import LuaTableParser

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "data" / "encounters.lua"


def quote(value: str) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"))


def slot_lua(slot: dict) -> str:
    return "{level=" + str(int(slot["level"])) + ",species=" + quote(slot["species"]) + "}"


def terrain_lua(row: dict) -> str:
    return "{rate=" + str(int(row["rate"])) + ",slots={" \
        + ",".join(slot_lua(slot) for slot in row.get("slots", [])) + "}}"


data = LuaTableParser(SOURCE.read_text(encoding="utf-8-sig")).value()
removed = sorted(map_id for map_id in data if map_id.startswith("J2_"))
kanto = {map_id: row for map_id, row in data.items() if not map_id.startswith("J2_")}
maps = []
for map_id in sorted(kanto):
    terrains = []
    for terrain in ("grass", "water"):
        if terrain in kanto[map_id]:
            terrains.append(terrain + "=" + terrain_lua(kanto[map_id][terrain]))
    maps.append("[" + quote(map_id) + "]={" + ",".join(terrains) + "}")
SOURCE.write_text("return {" + ",".join(maps) + ",}\n", encoding="utf-8")
print(json.dumps({"kantoMaps": len(kanto), "removedJ2Maps": len(removed)}))
