"""Validate collision-safe deterministic gift/static placement pools."""
from __future__ import annotations
import json, re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.setrecursionlimit(20000)
IDENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
NUMBER = re.compile(r"-?\d+(?:\.\d+)?")

class LuaTableParser:
    def __init__(self, text: str):
        self.s = text
        self.i = self.s.index("return") + 6
        self.depth = 0
    def ws(self):
        while self.i < len(self.s) and self.s[self.i].isspace(): self.i += 1
    def token(self):
        self.ws(); m = IDENT.match(self.s, self.i)
        if not m: raise ValueError(f"token at {self.i}")
        self.i = m.end(); return m.group()
    def value(self):
        self.ws(); c = self.s[self.i]
        if c == "{": return self.table()
        if c == '"':
            j = self.i + 1
            while True:
                j = self.s.find('"', j)
                if self.s[j-1] != "\\": break
                j += 1
            raw = self.s[self.i:j+1]; self.i = j+1
            return bytes(raw[1:-1], "utf8").decode("unicode_escape")
        m = NUMBER.match(self.s, self.i)
        if m:
            self.i = m.end(); return float(m.group()) if "." in m.group() else int(m.group())
        word = self.token()
        return {"true": True, "false": False, "nil": None}.get(word, word)
    def table(self):
        self.depth += 1
        if self.depth > 20: raise ValueError(f"deep table at {self.i}: {self.s[self.i:self.i+100]}")
        self.ws(); assert self.s[self.i] == "{"; self.i += 1
        arr, obj = [], {}
        while True:
            self.ws()
            if self.s[self.i] == "}": self.i += 1; break
            save = self.i; key = None
            if self.s[self.i] == "[":
                self.i += 1; key = self.value(); self.ws(); assert self.s[self.i] == "]"; self.i += 1
                self.ws(); assert self.s[self.i] == "="; self.i += 1
            elif self.s[self.i].isalpha() or self.s[self.i] == "_":
                candidate = self.token(); self.ws()
                if self.i < len(self.s) and self.s[self.i] == "=": key = candidate; self.i += 1
                else: self.i = save
            val = self.value()
            if key is None: arr.append(val)
            else: obj[key] = val
            self.ws()
            if self.s[self.i] in ",;": self.i += 1
        self.depth -= 1
        if obj and arr: obj["__array"] = arr; return obj
        return obj or arr

def load(name): return LuaTableParser((ROOT / "data" / name).read_text(encoding="utf-8-sig")).value()
maps, tilesets = load("maps.lua"), load("tilesets.lua")

STARTERS = ["NEW_BARK_TOWN","CHERRYGROVE_CITY","ROUTE_30","VIOLET_CITY","ROUTE_32","AZALEA_TOWN","ILEX_FOREST","GOLDENROD_CITY","ROUTE_35","ECRUTEAK_CITY","ROUTE_38","OLIVINE_CITY","ROUTE_40","CIANWOOD_CITY","ROUTE_42","MAHOGANY_TOWN","LAKE_OF_RAGE","ROUTE_44","BLACKTHORN_CITY","ROUTE_45","ROUTE_26","VERMILION_CITY","CELADON_CITY","SAFFRON_CITY","CERULEAN_CITY","FUCHSIA_CITY","PEWTER_CITY"]
TIERS = {
1:["OLIVINE_LIGHTHOUSE_4F","OLIVINE_LIGHTHOUSE_5F","MOUNT_MORTAR_1F_INSIDE","MOUNT_MORTAR_B1F","TEAM_ROCKET_BASE_B3F","ICE_PATH_1F"],
2:["ICE_PATH_B1F","ICE_PATH_B2F_MAHOGANY_SIDE","ICE_PATH_B3F","DRAGONS_DEN_B1F","TOHJO_FALLS","VICTORY_ROAD"],
3:["WHIRL_ISLAND_B1F","WHIRL_ISLAND_B2F","TIN_TOWER_4F","TIN_TOWER_6F","TIN_TOWER_8F","VICTORY_ROAD"],
4:["ROCK_TUNNEL_1F","ROCK_TUNNEL_B1F","MOUNT_MOON","POWER_PLANT","DIGLETTS_CAVE","TIN_TOWER_9F"],
5:["RUINS_OF_ALPH_AERODACTYL_CHAMBER","RUINS_OF_ALPH_KABUTO_CHAMBER","RUINS_OF_ALPH_OMANYTE_CHAMBER","RUINS_OF_ALPH_HO_OH_CHAMBER","SILVER_CAVE_ITEM_ROOMS","SILVER_CAVE_ROOM_1"],
6:["SILVER_CAVE_ROOM_1","SILVER_CAVE_ROOM_2","SILVER_CAVE_ROOM_3","TIN_TOWER_7F","WHIRL_ISLAND_CAVE","DRAGONS_DEN_B1F"],
7:["SILVER_CAVE_ROOM_1","SILVER_CAVE_ROOM_2","SILVER_CAVE_ROOM_3","RUINS_OF_ALPH_INNER_CHAMBER","TIN_TOWER_9F","WHIRL_ISLAND_B2F"],
8:["SILVER_CAVE_ROOM_1","SILVER_CAVE_ROOM_2","SILVER_CAVE_ROOM_3","MOUNT_MORTAR_2F_INSIDE","TIN_TOWER_ROOF","WHIRL_ISLAND_LUGIA_CHAMBER"],
9:["SILVER_CAVE_ROOM_1","SILVER_CAVE_ROOM_2","SILVER_CAVE_ROOM_3","RUINS_OF_ALPH_INNER_CHAMBER","TIN_TOWER_ROOF","WHIRL_ISLAND_LUGIA_CHAMBER"]}

def candidates(base):
    d=maps["J2_"+base]; ts=tilesets[d["tileset"]]; walk=set(ts["walkable"])
    occupied=set(); hazards=[]
    for kind,radius in (("objects",1),("warps",3),("signs",1)):
        for o in d.get(kind,[]): occupied.add((o["x"],o["y"])); hazards.append((o["x"],o["y"],radius))
    def passing(x,y):
        if not (0<=x<d["width"]*2 and 0<=y<d["height"]*2): return False
        block=d["blocks"][(y//2)*d["width"]+x//2]
        tile=ts["blocks"][block][4+(x%2)*2+(y%2)*8]
        return tile in walk
    out=[]
    for y in range(1,d["height"]*2-1):
      for x in range(1,d["width"]*2-1):
        if passing(x,y) and (x,y) not in occupied and all(abs(x-a)+abs(y-b)>r for a,b,r in hazards):
          degree=sum(passing(a,b) for a,b in ((x+1,y),(x-1,y),(x,y+1),(x,y-1)))
          if 0<degree<4: out.append({"x":x,"y":y,"degree":degree,"edge":min(x,y,d["width"]*2-1-x,d["height"]*2-1-y)})
    return sorted(out,key=lambda q:(q["degree"],q["edge"],q["y"],q["x"]))

RESERVED=set()
def slots(names,wanted,per_map):
    choices={n:candidates(n) for n in names}; selected=[]
    for _ in range(per_map):
      for name in names:
        pick=next((q for q in choices[name] if (name,q["x"],q["y"]) not in RESERVED and all(u["base"]!=name or abs(q["x"]-u["x"])+abs(q["y"]-u["y"])>=5 for u in selected)),None)
        if pick:
          choices[name].remove(pick); selected.append({"base":name,**pick}); RESERVED.add((name,pick["x"],pick["y"]))
          if len(selected)>=wanted: return selected
    raise AssertionError((wanted,len(selected),{n:len(v) for n,v in choices.items()}))

catalog_text=(ROOT/"data/progression_specials.lua").read_text()
counts={int(g):len(re.findall(fr"generation={g},",catalog_text))-1 for g in range(1,10)}
starter_slots=slots(STARTERS,27,1)
tier_slots={g:slots(TIERS[g],counts[g],4) for g in range(1,10)}
all_slots=starter_slots+[q for rows in tier_slots.values() for q in rows]
starter_names=[]
for body in re.findall(r'species=\{([^}]*)\}',catalog_text):
    starter_names.extend(re.findall(r'"([A-Z0-9_]+)"',body))
static_rows=[(species,int(generation)) for species,generation in
             re.findall(r'\{dex=\d+,species="([A-Z0-9_]+)",generation=(\d+),bst=',catalog_text)]
starter_assignments={species:slot for species,slot in zip(starter_names,starter_slots)}
generation_index={g:0 for g in range(1,10)}
static_assignments={}
for species,generation in static_rows:
    static_assignments[species]=tier_slots[generation][generation_index[generation]]
    generation_index[generation]+=1
affected_maps=sorted({q["base"] for q in all_slots})
affected_tilesets=sorted({maps["J2_"+base]["tileset"] for base in affected_maps})
report={"version":"0.9.11","starter_gifts":len(starter_slots),"static_catalog":sum(counts.values()),
        "starter_slots":starter_slots,"static_slots_by_generation":tier_slots,
        "starter_assignments":starter_assignments,"static_assignments":static_assignments,
        "save_editor_map_descriptors":{"maps":len(affected_maps),"tilesets":affected_tilesets,
          "fields":["id","label","tileset","width","height","blocks","borderBlock","region"]},
        "checks":{"all_maps_exist":True,"collision_passable":True,"warps_signs_objects_avoided":True,
                  "no_shared_tiles":len({(q["base"],q["x"],q["y"]) for q in all_slots})==len(all_slots),
                  "minimum_same_generation_map_distance":5,"annex_entrance_present":False}}
(ROOT/"DISTRIBUTED_PROGRESSION_QA.json").write_text(json.dumps(report,indent=2)+"\n",encoding="utf-8")
print(json.dumps({"starter_gifts":len(starter_slots),"static_catalog":sum(counts.values()),"by_generation":counts}))
