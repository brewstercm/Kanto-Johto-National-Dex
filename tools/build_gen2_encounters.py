"""Build the G/S/C-only encounter overlay from the maintained R/B/Y pool.

The R/B/Y file is never rewritten. Every unique ordinary species in that pool,
plus the Kanto relocations, is assigned once along the native Gen 2 campaign:
early/mid/late Johto first, then postgame Kanto and Mt. Silver. Area-access,
evolution and strength floors constrain assignment. Very late land evolutions
move inside Mt. Silver; water species remain in water pools.
"""
from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
IDENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
NUMBER = re.compile(r"-?\d+(?:\.\d+)?")


class LuaTableParser:
    def __init__(self, text: str):
        self.s = text
        self.i = self.s.index("return") + 6

    def ws(self):
        while self.i < len(self.s) and self.s[self.i].isspace():
            self.i += 1

    def token(self):
        self.ws()
        match = IDENT.match(self.s, self.i)
        if not match:
            raise ValueError(f"token expected at {self.i}")
        self.i = match.end()
        return match.group()

    def value(self):
        self.ws()
        char = self.s[self.i]
        if char == "{":
            return self.table()
        if char == '"':
            end = self.i + 1
            while True:
                end = self.s.find('"', end)
                if self.s[end - 1] != "\\":
                    break
                end += 1
            value = self.s[self.i + 1:end]
            self.i = end + 1
            return value
        match = NUMBER.match(self.s, self.i)
        if match:
            self.i = match.end()
            raw = match.group()
            return float(raw) if "." in raw else int(raw)
        word = self.token()
        return {"true": True, "false": False, "nil": None}.get(word, word)

    def table(self):
        self.ws()
        if self.s[self.i] != "{":
            raise ValueError(f"table expected at {self.i}")
        self.i += 1
        array, obj = [], {}
        while True:
            self.ws()
            if self.s[self.i] == "}":
                self.i += 1
                break
            save, key = self.i, None
            if self.s[self.i] == "[":
                self.i += 1
                key = self.value()
                self.ws()
                if self.s[self.i] != "]":
                    raise ValueError(f"] expected at {self.i}")
                self.i += 1
                self.ws()
                if self.s[self.i] != "=":
                    raise ValueError(f"= expected at {self.i}")
                self.i += 1
            elif self.s[self.i].isalpha() or self.s[self.i] == "_":
                candidate = self.token()
                self.ws()
                if self.i < len(self.s) and self.s[self.i] == "=":
                    key = candidate
                    self.i += 1
                else:
                    self.i = save
            value = self.value()
            if key is None:
                array.append(value)
            else:
                obj[key] = value
            self.ws()
            if self.i < len(self.s) and self.s[self.i] in ",;":
                self.i += 1
        if obj and array:
            obj["__array"] = array
            return obj
        return obj or array


def load_lua(name: str):
    return LuaTableParser((ROOT / "data" / name).read_text(encoding="utf-8-sig")).value()


# (map id, intended median level, region). Only maps with native encounters in
# all three Gen 2 cartridges are used. Ruins of Alph remains cartridge-native.
PLANS = {
    "grass": [
        ("ROUTE_29", 3, "johto"), ("ROUTE_30", 4, "johto"),
        ("ROUTE_31", 5, "johto"), ("ROUTE_32", 8, "johto"),
        ("ROUTE_33", 10, "johto"), ("ILEX_FOREST", 12, "johto"),
        ("ROUTE_34", 14, "johto"), ("ROUTE_35", 16, "johto"),
        ("NATIONAL_PARK", 17, "johto"), ("ROUTE_36", 18, "johto"),
        ("ROUTE_37", 19, "johto"), ("ROUTE_38", 21, "johto"),
        ("ROUTE_39", 22, "johto"), ("ROUTE_42", 24, "johto"),
        ("ROUTE_43", 25, "johto"), ("ROUTE_44", 27, "johto"),
        ("ROUTE_45", 30, "johto"), ("ROUTE_46", 31, "johto"),
        ("ROUTE_26", 33, "johto"), ("ROUTE_27", 34, "johto"),
        ("ROUTE_1", 34, "kanto"), ("ROUTE_2", 35, "kanto"),
        ("ROUTE_3", 35, "kanto"), ("ROUTE_4", 36, "kanto"),
        ("ROUTE_5", 36, "kanto"), ("ROUTE_6", 37, "kanto"),
        ("ROUTE_7", 37, "kanto"), ("ROUTE_8", 38, "kanto"),
        ("ROUTE_9", 38, "kanto"), ("ROUTE_10_NORTH", 39, "kanto"),
        ("ROUTE_11", 39, "kanto"), ("ROUTE_13", 40, "kanto"),
        ("ROUTE_14", 40, "kanto"), ("ROUTE_15", 41, "kanto"),
        ("ROUTE_16", 41, "kanto"), ("ROUTE_17", 42, "kanto"),
        ("ROUTE_18", 42, "kanto"), ("ROUTE_21", 43, "kanto"),
        ("ROUTE_22", 43, "kanto"), ("ROUTE_24", 44, "kanto"),
        ("ROUTE_25", 44, "kanto"), ("ROUTE_28", 46, "kanto"),
        ("SILVER_CAVE_OUTSIDE", 48, "johto"),
    ],
    "indoor": [
        ("DARK_CAVE_VIOLET_ENTRANCE", 4, "johto"),
        ("SPROUT_TOWER_2F", 5, "johto"), ("SPROUT_TOWER_3F", 7, "johto"),
        ("UNION_CAVE_1F", 8, "johto"), ("UNION_CAVE_B1F", 10, "johto"),
        ("SLOWPOKE_WELL_B1F", 10, "johto"), ("SLOWPOKE_WELL_B2F", 13, "johto"),
        ("UNION_CAVE_B2F", 14, "johto"), ("BURNED_TOWER_1F", 16, "johto"),
        ("BURNED_TOWER_B1F", 18, "johto"),
        ("MOUNT_MORTAR_1F_OUTSIDE", 20, "johto"),
        ("MOUNT_MORTAR_1F_INSIDE", 22, "johto"),
        ("MOUNT_MORTAR_B1F", 24, "johto"),
        ("WHIRL_ISLAND_NW", 24, "johto"), ("WHIRL_ISLAND_NE", 25, "johto"),
        ("WHIRL_ISLAND_SW", 26, "johto"), ("WHIRL_ISLAND_SE", 27, "johto"),
        ("ICE_PATH_1F", 28, "johto"), ("ICE_PATH_B1F", 29, "johto"),
        ("ICE_PATH_B2F_MAHOGANY_SIDE", 30, "johto"),
        ("ICE_PATH_B2F_BLACKTHORN_SIDE", 31, "johto"),
        ("ICE_PATH_B3F", 31, "johto"),
        ("DARK_CAVE_BLACKTHORN_ENTRANCE", 32, "johto"),
        ("TOHJO_FALLS", 33, "johto"), ("VICTORY_ROAD", 35, "johto"),
        ("MOUNT_MOON", 36, "kanto"), ("DIGLETTS_CAVE", 36, "kanto"),
        ("ROCK_TUNNEL_1F", 38, "kanto"), ("ROCK_TUNNEL_B1F", 39, "kanto"),
        ("TIN_TOWER_4F", 40, "johto"), ("TIN_TOWER_6F", 41, "johto"),
        ("TIN_TOWER_8F", 42, "johto"), ("TIN_TOWER_9F", 43, "johto"),
        ("WHIRL_ISLAND_B1F", 43, "johto"), ("WHIRL_ISLAND_B2F", 44, "johto"),
        ("WHIRL_ISLAND_CAVE", 45, "johto"),
        ("SILVER_CAVE_ITEM_ROOMS", 46, "johto"),
        ("SILVER_CAVE_ROOM_1", 47, "johto"),
        ("SILVER_CAVE_ROOM_2", 48, "johto"),
        ("SILVER_CAVE_ROOM_3", 50, "johto"),
    ],
    "water": [
        ("NEW_BARK_TOWN", 3, "johto"), ("CHERRYGROVE_CITY", 4, "johto"),
        ("ROUTE_30", 5, "johto"), ("ROUTE_31", 6, "johto"),
        ("VIOLET_CITY", 8, "johto"), ("ROUTE_32", 10, "johto"),
        ("UNION_CAVE_1F", 11, "johto"), ("SLOWPOKE_WELL_B1F", 12, "johto"),
        ("ILEX_FOREST", 13, "johto"), ("ROUTE_34", 15, "johto"),
        ("ROUTE_35", 17, "johto"), ("ECRUTEAK_CITY", 19, "johto"),
        ("OLIVINE_CITY", 21, "johto"), ("ROUTE_40", 22, "johto"),
        ("ROUTE_41", 24, "johto"), ("CIANWOOD_CITY", 25, "johto"),
        ("ROUTE_42", 25, "johto"), ("LAKE_OF_RAGE", 27, "johto"),
        ("ROUTE_44", 28, "johto"), ("BLACKTHORN_CITY", 30, "johto"),
        ("DRAGONS_DEN_B1F", 32, "johto"), ("ROUTE_26", 33, "johto"),
        ("ROUTE_27", 34, "johto"), ("TOHJO_FALLS", 35, "johto"),
        ("PALLET_TOWN", 35, "kanto"), ("VIRIDIAN_CITY", 36, "kanto"),
        ("ROUTE_4", 36, "kanto"), ("ROUTE_6", 37, "kanto"),
        ("CERULEAN_CITY", 38, "kanto"), ("ROUTE_9", 38, "kanto"),
        ("ROUTE_10_NORTH", 39, "kanto"), ("VERMILION_CITY", 39, "kanto"),
        ("CELADON_CITY", 40, "kanto"), ("FUCHSIA_CITY", 41, "kanto"),
        ("ROUTE_12", 41, "kanto"), ("ROUTE_13", 42, "kanto"),
        ("ROUTE_19", 43, "kanto"), ("ROUTE_20", 44, "kanto"),
        ("ROUTE_21", 45, "kanto"), ("ROUTE_24", 45, "kanto"),
        ("ROUTE_25", 46, "kanto"), ("ROUTE_28", 47, "kanto"),
        ("SILVER_CAVE_OUTSIDE", 48, "johto"),
        ("SILVER_CAVE_ROOM_2", 50, "johto"),
    ],
}

# The generated national payload only repeats species that the mod adds to a
# cartridge, so native Gen 1/2 type rows are not available there. This compact
# set supplies the missing Water typing needed by the habitat classifier.
NATIVE_WATER = {
    "PSYDUCK", "GOLDUCK", "POLIWAG", "POLIWHIRL", "POLIWRATH",
    "TENTACOOL", "TENTACRUEL", "SLOWPOKE", "SLOWBRO", "SEEL", "DEWGONG",
    "SHELLDER", "CLOYSTER", "KRABBY", "KINGLER", "HORSEA", "SEADRA",
    "GOLDEEN", "SEAKING", "STARYU", "STARMIE", "MAGIKARP", "GYARADOS",
    "LAPRAS", "VAPOREON", "OMANYTE", "OMASTAR", "KABUTO", "KABUTOPS",
    "CHINCHOU", "LANTURN", "MARILL", "AZUMARILL", "POLITOED", "WOOPER",
    "QUAGSIRE", "SLOWKING", "QWILFISH", "CORSOLA", "REMORAID", "OCTILLERY",
    "MANTINE", "KINGDRA",
}


def observations():
    source = load_lua("extra_encounters.lua")["maps"]
    relocation = load_lua("kanto_native_relocations.lua")
    found: dict[str, list[tuple[str, int]]] = {}
    for maps in (source, relocation):
        for terrains in maps.values():
            for terrain, rows in terrains.items():
                normalized = "indoor" if terrain == "indoor" else terrain
                for row in rows:
                    found.setdefault(row["species"], []).append(
                        (normalized, int(row["level"])))
    return found


def species_types():
    text = (ROOT / "data" / "species" / "generated" / "national.lua").read_text(
        encoding="utf-8-sig")
    found = {}
    pattern = re.compile(
        r"^    ([A-Z0-9_]+) = \{\r?\n.*?^      types = \{ ([^}]*) \},",
        re.MULTILINE | re.DOTALL)
    for species, body in pattern.findall(text):
        found[species] = set(re.findall(r'"([A-Z]+)"', body))
    for species in NATIVE_WATER:
        found.setdefault(species, set()).add("WATER")
    return found


def classify(species, rows, types):
    counts = {"grass": 0, "indoor": 0, "water": 0}
    for terrain, _ in rows:
        if terrain in counts:
            counts[terrain] += 1
    if "WATER" in types.get(species, set()):
        habitat = "water"
    else:
        # Several old Kanto water pools were space-saving placements rather
        # than habitat matches (for example PILOSWINE and SKARMORY). A
        # non-Water species that had no land observation returns to grass or
        # a cave according to its typing instead of being copied to Johto's sea.
        land = {key: counts[key] for key in ("grass", "indoor")}
        if max(land.values()) > 0:
            habitat = max(land, key=lambda key: (land[key], key == "indoor"))
        else:
            cave_types = {"GHOST", "ROCK", "STEEL"}
            habitat = "indoor" if types.get(species, set()) & cave_types else "grass"
    levels = sorted(level for _, level in rows)
    return habitat, levels[len(levels) // 2]


def lua_key(value: str):
    return value if IDENT.fullmatch(value) else f'["{value}"]'


# Targets describe earliest practical access, not route-number order. Water
# starts at the Surf portion of the campaign, even in the starting towns.
AREA_TARGETS = {
    "ROUTE_46": 4, "ROUTE_32": 6, "ROUTE_33": 7,
    "ILEX_FOREST": 7, "ROUTE_34": 10, "ROUTE_35": 12,
    "NATIONAL_PARK": 12, "ROUTE_36": 12, "ROUTE_37": 14,
    "ROUTE_38": 16, "ROUTE_39": 16, "ROUTE_42": 17,
    "ROUTE_43": 17, "ROUTE_44": 22, "ROUTE_45": 25,
    "UNION_CAVE_1F": 7, "UNION_CAVE_B1F": 8,
    "SLOWPOKE_WELL_B1F": 7, "SLOWPOKE_WELL_B2F": 23,
    "UNION_CAVE_B2F": 22, "BURNED_TOWER_1F": 15,
    "BURNED_TOWER_B1F": 16, "MOUNT_MORTAR_1F_OUTSIDE": 15,
    "MOUNT_MORTAR_1F_INSIDE": 20, "MOUNT_MORTAR_B1F": 20,
    "WHIRL_ISLAND_NW": 23, "WHIRL_ISLAND_NE": 23,
    "WHIRL_ISLAND_SW": 23, "WHIRL_ISLAND_SE": 23,
    "WHIRL_ISLAND_B1F": 25, "WHIRL_ISLAND_B2F": 27,
    "WHIRL_ISLAND_CAVE": 27, "TIN_TOWER_4F": 22,
    "TIN_TOWER_6F": 24, "TIN_TOWER_8F": 26, "TIN_TOWER_9F": 28,
    "ICE_PATH_1F": 23, "ICE_PATH_B1F": 24,
    "ICE_PATH_B2F_MAHOGANY_SIDE": 24,
    "ICE_PATH_B2F_BLACKTHORN_SIDE": 24, "ICE_PATH_B3F": 25,
    "DARK_CAVE_BLACKTHORN_ENTRANCE": 25,
    "SILVER_CAVE_OUTSIDE": 48, "SILVER_CAVE_ITEM_ROOMS": 52,
    "SILVER_CAVE_ROOM_1": 55, "SILVER_CAVE_ROOM_2": 60,
    "SILVER_CAVE_ROOM_3": 64,
}


def balanced_plans():
    plans = {}
    for habitat, rows in PLANS.items():
        plans[habitat] = sorted([
            (map_id, max(20, AREA_TARGETS.get(map_id, level))
             if habitat == "water" else AREA_TARGETS.get(map_id, level), region)
            for map_id, level, region in rows
        ], key=lambda row: (row[1], row[0]))
    return plans


def species_minimums():
    records = load_lua("species/generated/national.lua")["register"]
    evolutions = load_lua("species/generated/evolutions.lua")["records"]
    parents = {}
    for source, record in evolutions.items():
        for evolution in record["evolutions"]:
            parents.setdefault(evolution["species"], []).append((source, evolution))
    memo = {}

    def evolution_floor(species):
        if species not in memo:
            incoming = parents.get(species, [])
            memo[species] = min([
                max(evolution_floor(source), int(row.get("level", 0))
                    if row.get("method") == "LEVEL" else
                    (30 if source in parents else 20))
                for source, row in incoming
            ] or [2])
        return memo[species]

    result = {}
    for species, observations_for_species in observations().items():
        record = records.get(species)
        if record:
            stats = record["baseStats"]
            bst = sum(stats[key] for key in ("hp", "attack", "defense", "speed"))
            bst += record.get("spAttack", stats["special"])
            bst += record.get("spDefense", stats["special"])
            power_floor = (45 if bst >= 580 else 35 if bst >= 530 else
                           28 if bst >= 500 else 22 if bst >= 450 else
                           16 if bst >= 400 else 10 if bst >= 350 else 2)
        else:
            # Native Gen I stat records come from the cartridge, not this
            # payload. Preserve their existing median floor conservatively.
            levels = sorted(level for _, level in observations_for_species)
            power_floor = levels[len(levels) // 2]
        result[species] = max(evolution_floor(species), power_floor)
    return result


def main():
    by_habitat = {key: [] for key in PLANS}
    types = species_types()
    minimums = species_minimums()
    plans = balanced_plans()
    for species, rows in observations().items():
        habitat, level = classify(species, rows, types)
        # Very late land evolutions belong inside Mt. Silver, not as
        # under-levelled adults on ordinary outdoor routes.
        if habitat == "grass" and minimums[species] > max(row[1] for row in plans["grass"]):
            habitat = "indoor"
        by_habitat[habitat].append((level, species))

    maps: dict[str, dict[str, list[dict[str, int | str]]]] = {}
    regions = {}
    for habitat, species_rows in by_habitat.items():
        species_rows.sort(key=lambda row: (minimums[row[1]], row[0], row[1]))
        plan = plans[habitat]
        counts = {}
        for index, (old_level, species) in enumerate(species_rows):
            minimum = minimums[species]
            eligible = [row for row in plan if row[1] >= minimum]
            if not eligible:
                raise AssertionError(f"No level-appropriate {habitat} area for {species}: {minimum}")
            desired = max(minimum, old_level)
            map_id, target_level, region = min(eligible, key=lambda row: (
                abs(row[1] - desired) + counts.get(row[0], 0) * 0.5,
                counts.get(row[0], 0), row[0]))
            counts[map_id] = counts.get(map_id, 0) + 1
            level = max(minimum, target_level - 2, min(old_level, target_level + 2))
            maps.setdefault(map_id, {}).setdefault(habitat, []).append(
                {"species": species, "level": level})
            regions[map_id] = region

    lines = ["return {", "  chance=100,", "  generation=2,", "  regions={"]
    for map_id in sorted(regions):
        lines.append(f'    {lua_key(map_id)}="{regions[map_id]}",')
    lines.extend(["  },", "  maps={"])
    for map_id in sorted(maps):
        lines.append(f"    {lua_key(map_id)}={{")
        for habitat in ("grass", "indoor", "water"):
            rows = maps[map_id].get(habitat)
            if not rows:
                continue
            lines.append(f"      {habitat}={{")
            for row in rows:
                lines.append(
                    f'        {{species="{row["species"]}",level={row["level"]}}},')
            lines.append("      },")
        lines.append("    },")
    lines.extend(["  },", "}", ""])
    output = ROOT / "data" / "extra_encounters_gen2.lua"
    output.write_text("\n".join(lines), encoding="utf-8")

    assigned = [row["species"] for terrains in maps.values()
                for rows in terrains.values() for row in rows]
    if len(assigned) != 774 or len(set(assigned)) != 774:
        raise AssertionError((len(assigned), len(set(assigned))))
    johto = sum(len(rows) for map_id, terrains in maps.items()
                if regions[map_id] == "johto" for rows in terrains.values())
    kanto = len(assigned) - johto
    dex_text = (ROOT / "data" / "dex_art.lua").read_text(encoding="utf-8-sig")
    dex = {species: int(number) for species, number in
           re.findall(r"([A-Z0-9_]+)=\{dex=(\d+),", dex_text)}
    limits = (151, 251, 386, 493, 649, 721, 809, 905, 1025)
    def generation(species):
        number = dex[species]
        return next(index for index, limit in enumerate(limits, 1) if number <= limit)
    by_generation = {str(index): {"johto": 0, "kanto": 0} for index in range(1, 10)}
    for map_id, terrains in maps.items():
        region = regions[map_id]
        for rows in terrains.values():
            for row in rows:
                by_generation[str(generation(row["species"]))][region] += 1
    source_path = ROOT / "data" / "extra_encounters.lua"
    qa = {
        "version": "0.9.11-gen2-balanced",
        "balancePolicy": "earliest-access area targets, evolution floors, BST tiers; native Gen I additions retain their old median floor",
        "minimumLevelViolations": sum(row["level"] < minimums[row["species"]]
            for terrains in maps.values() for rows in terrains.values() for row in rows),
        "runtimeSelection": {"gen1": "extra_encounters.lua",
                             "gen2": "extra_encounters_gen2.lua"},
        "gen1SourceSha256": hashlib.sha256(source_path.read_bytes()).hexdigest().upper(),
        "uniqueSpecies": len(assigned),
        "duplicateSpecies": len(assigned) - len(set(assigned)),
        "mapCount": len(maps),
        "mapsByRegion": {
            region: sum(1 for value in regions.values() if value == region)
            for region in ("johto", "kanto")
        },
        "speciesPlacementsByRegion": {"johto": johto, "kanto": kanto},
        "speciesPlacementsByGenerationAndRegion": by_generation,
        "habitats": {key: len(value) for key, value in by_habitat.items()},
        "generationWeighting": "equal among generations represented on the current map/terrain",
        "speciesWeighting": "equal among unique species in the selected generation bucket",
        "ruinsOfAlph": "cartridge-native only",
        "nativeEncounterRateRetained": True,
        "nativeSpeciesMergedAtRuntime": True,
    }
    (ROOT / "GEN2_SPLIT_ENCOUNTER_QA.json").write_text(
        json.dumps(qa, indent=2) + "\n", encoding="utf-8")
    print({"species": len(assigned), "maps": len(maps),
           "johto": johto, "kanto": kanto,
           "habitats": {key: len(value) for key, value in by_habitat.items()}})


if __name__ == "__main__":
    main()
