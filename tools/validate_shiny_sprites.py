"""Validate shiny sheet coverage, metadata dimensions, and runtime wiring."""
from __future__ import annotations

import json
import re
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    metadata_text = (ROOT / "data" / "anim_shiny_meta.lua").read_text(encoding="utf-8-sig")
    pattern = (
        r'\[(\d+)\]=\{front=\{w=(\d+),h=(\d+),count=(\d+)\},'
        r'back=\{w=(\d+),h=(\d+),count=(\d+)\}\},'
    )
    rows = {
        int(dex): {
            "front": (int(fw), int(fh), int(fc)),
            "back": (int(bw), int(bh), int(bc)),
        }
        for dex, fw, fh, fc, bw, bh, bc in re.findall(pattern, metadata_text)
    }
    normal_rows = {
        int(dex): {"front": (int(fw), int(fh)), "back": (int(bw), int(bh))}
        for dex, fw, fh, _fc, bw, bh, _bc in re.findall(
            pattern, (ROOT / "data" / "anim_meta.lua").read_text(encoding="utf-8-sig")
        )
    }
    failures: list[str] = []
    different_from_normal = 0
    static_sheets = 0
    animated_sheets = 0

    if set(rows) != set(range(1, 1026)):
        failures.append("metadata does not cover exactly National Dex 1-1025")
    for dex in range(1, 1026):
        for side in ("front", "back"):
            path = ROOT / "assets" / "anim" / "shiny" / side / f"{dex:04d}.png"
            if not path.is_file():
                failures.append(f"missing sheet: {side}/{dex:04d}.png")
                continue
            try:
                with Image.open(path) as image:
                    image.load()
                    width, height, count = rows[dex][side]
                    if (width, height) != normal_rows[dex][side]:
                        failures.append(
                            f"frame differs from normal layout: {side}/{dex:04d}.png"
                        )
                    if image.mode != "RGBA":
                        failures.append(f"wrong mode: {side}/{dex:04d}.png = {image.mode}")
                    if image.size != (width * count, height):
                        failures.append(
                            f"metadata mismatch: {side}/{dex:04d}.png "
                            f"{image.size} != {(width * count, height)}"
                        )
                    if count == 1:
                        static_sheets += 1
                    else:
                        animated_sheets += 1
            except OSError as error:
                failures.append(f"unreadable sheet: {side}/{dex:04d}.png: {error}")
            normal = ROOT / "assets" / "anim" / side / f"{dex:04d}.png"
            if normal.is_file() and path.read_bytes() != normal.read_bytes():
                different_from_normal += 1

    runtime = (ROOT / "animated_sprites.lua").read_text(encoding="utf-8-sig")
    main_lua = (ROOT / "main.lua").read_text(encoding="utf-8-sig")
    required = (
        'local function shinyState(mon)',
        'if mon.shiny then return true end',
        'tonumber(dvs.defense) == 10',
        'local variant = shiny and "shiny/" or ""',
        'p:frame(mon.species, back and "back" or "front", mon)',
        'p:frame(mon.species, "front", mon)',
    )
    for snippet in required:
        if snippet not in runtime:
            failures.append(f"missing runtime selector: {snippet}")
    if 'ownModule("data/anim_shiny_meta.lua")' not in main_lua:
        failures.append("main.lua does not load shiny metadata")

    source_report = json.loads((ROOT / "SHINY_SPRITE_QA.json").read_text(encoding="utf-8"))
    if source_report.get("totalSheets") != 2050:
        failures.append("source report does not record all 2050 sheets")

    report = {
        "species": len(rows),
        "frontSheets": len(list((ROOT / "assets" / "anim" / "shiny" / "front").glob("*.png"))),
        "backSheets": len(list((ROOT / "assets" / "anim" / "shiny" / "back").glob("*.png"))),
        "animatedSheets": animated_sheets,
        "staticSheets": static_sheets,
        "sheetsDifferentFromNormal": different_from_normal,
        "failures": failures,
    }
    print(json.dumps(report, indent=2))
    if failures:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
