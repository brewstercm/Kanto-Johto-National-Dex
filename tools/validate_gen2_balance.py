"""ROM-free regression checks for the authored Gen II balance policy."""
import json
from build_gen2_encounters import load_lua, observations, species_minimums, balanced_plans


def main():
    overlay = load_lua("extra_encounters_gen2.lua")["maps"]
    minimums = species_minimums()
    plans = balanced_plans()
    targets = {(map_id, habitat): target for habitat, rows in plans.items()
               for map_id, target, _ in rows}
    assigned = {}
    failures = []
    for map_id, terrains in overlay.items():
        for habitat, rows in terrains.items():
            target = targets[(map_id, habitat)]
            for row in rows:
                species, level = row["species"], row["level"]
                if species in assigned:
                    failures.append(f"duplicate {species}")
                assigned[species] = (map_id, level)
                if level < minimums[species] or target < minimums[species]:
                    failures.append(f"premature {species} on {map_id}")
                if not target - 2 <= level <= target + 2:
                    failures.append(f"area level mismatch {species} on {map_id}")
    assert set(assigned) == set(observations()), "species coverage changed"
    assert len(assigned) == 774
    assert overlay["ROUTE_46"]["grass"]
    assert all(row["level"] <= 6 for row in overlay["ROUTE_46"]["grass"])
    assert assigned["KIRLIA"][1] >= 20
    assert assigned["HYDREIGON"][1] >= 64
    assert assigned["DRAGONITE"][1] >= 55
    print(json.dumps({"species": len(assigned), "maps": len(overlay),
                      "failures": failures, "examples": {
                          name: assigned[name] for name in
                          ("KIRLIA", "DRAGONITE", "HYDREIGON", "TYRUNT")}}, indent=2))
    assert not failures


if __name__ == "__main__":
    main()
