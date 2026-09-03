"""Static validation for the generation-specific legendary quest profiles."""
from __future__ import annotations

import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "data" / "progression_specials.lua"
RUNTIME = ROOT / "progression_acquisition.lua"


def block(text: str, marker: str, end_marker: str) -> str:
    start = text.index(marker)
    end = text.index(end_marker, start)
    return text[start:end]


def main() -> None:
    catalog = CATALOG.read_text(encoding="utf-8-sig")
    runtime = RUNTIME.read_text(encoding="utf-8-sig")
    qa = json.loads((ROOT / "FAMILY_QUEST_QA.json").read_text(encoding="utf-8"))

    family_body = block(catalog, "familyQuests={", "\n  },\n}")
    family_ids = set(re.findall(r'\{id="([A-Z0-9_]+)"', family_body))
    profile_body = block(catalog, "researchers={", "\n    },\n  },")
    profile_rows = re.findall(
        r'^\s+([A-Z0-9_]+)=\{map="([A-Z0-9_]+)"(?:,badge="([A-Z0-9_]+)")?\},',
        profile_body,
        re.MULTILINE,
    )
    researchers = {key: {"map": map_id, "badge": badge or None}
                   for key, map_id, badge in profile_rows}
    expected = family_ids | {"BIRDS", "REGIS", "LUNAR"}
    johto_maps = set(re.findall(r'^\s+([A-Z0-9_]+)="johto",',
                                (ROOT / "data" / "extra_encounters_gen2.lua")
                                .read_text(encoding="utf-8-sig"), re.MULTILINE))
    johto_maps |= {"GOLDENROD_CITY", "MAHOGANY_TOWN"}

    failures: list[str] = []
    if set(researchers) != expected:
        failures.append("Gen 2 researcher keys do not match all 29 quest families")
    for key, row in researchers.items():
        if row["map"] not in johto_maps:
            failures.append(f"{key} is not assigned to a Johto map: {row['map']}")
        if key == "BIRDS" and row["badge"] is not None:
            failures.append("BIRDS must remain ungated")
        if key != "BIRDS" and row["badge"] != "RISING":
            failures.append(f"{key} must use the Rising Badge in Gen 2")

    required_runtime = (
        'mod.commands:register("knd_has_badge"',
        'questProfile=gen2Profile and "gen2_johto" or "gen1_kanto"',
        'local birdsMap=questDefinition("BIRDS","PEWTER_CITY",nil)',
        'local regisMap,regisBadge=questDefinition(',
        'local lunarMap,lunarBadge=questDefinition(',
        '{"knd_has_badge",badge}',
    )
    for snippet in required_runtime:
        if snippet not in runtime:
            failures.append(f"missing runtime integration: {snippet}")

    reported = qa["generationProfiles"]["gen2"]["researcherMaps"]
    if reported != {key: row["map"] for key, row in researchers.items()}:
        failures.append("FAMILY_QUEST_QA Gen 2 map report is out of sync")

    report = {
        "questFamilies": len(expected),
        "gen2Researchers": len(researchers),
        "johtoMapsUsed": len({row["map"] for row in researchers.values()}),
        "risingBadgeGates": sum(row["badge"] == "RISING"
                                for row in researchers.values()),
        "ungatedFamilies": sorted(key for key, row in researchers.items()
                                  if row["badge"] is None),
        "failures": failures,
    }
    print(json.dumps(report, indent=2))
    if failures:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
