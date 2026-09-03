"""Build shiny sheets from PokeAPI's Gen 5-style sprite collection.

The source commit is pinned so a later upstream art change cannot silently
change a release. Downloads and conversion happen in a temporary directory;
the maintained assets are only replaced after all 2,050 inputs succeed.
"""
from __future__ import annotations

import hashlib
import io
import json
import os
import re
import shutil
import tempfile
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

from PIL import Image, ImageSequence


ROOT = Path(__file__).resolve().parents[1]
SOURCE_COMMIT = "b2486a428a7548c874ad3900951d5334a40d21a5"
POKEMON_ROOT = (
    "https://raw.githubusercontent.com/PokeAPI/sprites/"
    f"{SOURCE_COMMIT}/sprites/pokemon"
)
SOURCE_CANDIDATES = {
    "front": (
        ("black-white-animated", "versions/generation-v/black-white/animated/shiny/{dex}.gif"),
        ("black-white-static", "versions/generation-v/black-white/shiny/{dex}.png"),
        ("pokeapi-default", "shiny/{dex}.png"),
    ),
    "back": (
        ("black-white-animated", "versions/generation-v/black-white/animated/back/shiny/{dex}.gif"),
        ("black-white-static", "versions/generation-v/black-white/back/shiny/{dex}.png"),
        ("pokeapi-default", "back/shiny/{dex}.png"),
    ),
}
FIRST_DEX = 1
LAST_DEX = 1025
WORKERS = 12


def normal_dimensions() -> dict[int, dict[str, tuple[int, int]]]:
    text = (ROOT / "data" / "anim_meta.lua").read_text(encoding="utf-8-sig")
    rows = {
        int(dex): {"front": (int(fw), int(fh)), "back": (int(bw), int(bh))}
        for dex, fw, fh, _fc, bw, bh, _bc in re.findall(
            r'\[(\d+)\]=\{front=\{w=(\d+),h=(\d+),count=(\d+)\},'
            r'back=\{w=(\d+),h=(\d+),count=(\d+)\}\},', text
        )
    }
    if set(rows) != set(range(FIRST_DEX, LAST_DEX + 1)):
        raise RuntimeError("normal animation metadata does not cover Dex 1-1025")
    return rows


# Loaded once before worker threads start. Matching these dimensions keeps the
# existing per-species battle scale and HUD-safe placement valid for shinies.
NORMAL_DIMENSIONS = normal_dimensions()


class MissingAsset(Exception):
    """The candidate path does not exist upstream."""


def download(url: str) -> bytes:
    last_error: Exception | None = None
    for attempt in range(4):
        try:
            request = urllib.request.Request(url, headers={"User-Agent": "Kanto-National-Dex-builder"})
            with urllib.request.urlopen(request, timeout=45) as response:
                data = response.read()
            if not data.startswith((b"GIF87a", b"GIF89a", b"\x89PNG\r\n\x1a\n")):
                raise ValueError(f"not a GIF or PNG: {url}")
            return data
        except urllib.error.HTTPError as error:
            if error.code == 404:
                raise MissingAsset(url) from error
            last_error = error
            if attempt < 3:
                time.sleep(0.5 * (2 ** attempt))
        except (OSError, urllib.error.URLError, ValueError) as error:
            last_error = error
            if attempt < 3:
                time.sleep(0.5 * (2 ** attempt))
    raise RuntimeError(f"download failed after retries: {url}: {last_error}")


def image_to_strip(data: bytes) -> tuple[Image.Image, dict[str, int]]:
    with Image.open(io.BytesIO(data)) as source:
        decoded = [frame.convert("RGBA") for frame in ImageSequence.Iterator(source)]
    # PokeAPI GIFs sometimes encode a held pose as consecutive identical
    # frames. The existing normal-sheet pipeline removes those duplicates and
    # the runtime uses a fixed FPS, so shiny sheets must apply the same rule.
    frames: list[Image.Image] = []
    previous: bytes | None = None
    for frame in decoded:
        pixels = frame.tobytes()
        if pixels != previous:
            frames.append(frame)
        previous = pixels
    if not frames:
        raise ValueError("GIF contains no frames")

    union: tuple[int, int, int, int] | None = None
    for frame in frames:
        bounds = frame.getchannel("A").getbbox()
        if bounds is None:
            continue
        if union is None:
            union = bounds
        else:
            union = (
                min(union[0], bounds[0]), min(union[1], bounds[1]),
                max(union[2], bounds[2]), max(union[3], bounds[3]),
            )
    if union is None:
        raise ValueError("GIF contains no visible pixels")

    width, height = union[2] - union[0], union[3] - union[1]
    strip = Image.new("RGBA", (width * len(frames), height), (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        strip.alpha_composite(frame.crop(union), (index * width, 0))
    return strip, {"w": width, "h": height, "count": len(frames)}


def fit_to_normal_frame(strip: Image.Image, metadata: dict[str, int],
                        dex: int, side: str) -> tuple[Image.Image, dict[str, int]]:
    source_width, source_height = metadata["w"], metadata["h"]
    target_width, target_height = NORMAL_DIMENSIONS[dex][side]
    count = metadata["count"]
    fitted = Image.new("RGBA", (target_width * count, target_height), (0, 0, 0, 0))
    scale = min(1.0, target_width / source_width, target_height / source_height)
    width = max(1, round(source_width * scale))
    height = max(1, round(source_height * scale))
    for index in range(count):
        frame = strip.crop((index * source_width, 0,
                            (index + 1) * source_width, source_height))
        if frame.size != (width, height):
            frame = frame.resize((width, height), Image.Resampling.NEAREST)
        x = index * target_width + (target_width - width) // 2
        y = target_height - height
        fitted.alpha_composite(frame, (x, y))
    return fitted, {"w": target_width, "h": target_height, "count": count}


def build_one(stage: Path, dex: int, side: str) -> tuple[int, str, dict[str, int], str, str]:
    strip = None
    metadata = None
    source_kind = None
    attempted = []
    candidates = SOURCE_CANDIDATES[side]
    # PokeAPI's animated Black/White directory ends with Genesect (#649).
    # Later generations are maintained as static Gen 5-style PNGs.
    if dex > 649:
        candidates = candidates[1:]
    for kind, pattern in candidates:
        relative = pattern.format(dex=dex)
        url = f"{POKEMON_ROOT}/{relative}"
        try:
            data = download(url)
            strip, metadata = image_to_strip(data)
            strip, metadata = fit_to_normal_frame(strip, metadata, dex, side)
            source_kind = kind
            break
        except (MissingAsset, OSError, ValueError) as error:
            attempted.append(f"{url} ({error})")
            continue
    if strip is None or metadata is None or source_kind is None:
        raise RuntimeError("no PokeAPI shiny source: " + ", ".join(attempted))
    output = stage / side / f"{dex:04d}.png"
    output.parent.mkdir(parents=True, exist_ok=True)
    strip.save(output, format="PNG", optimize=True, compress_level=9)
    digest = hashlib.sha256(output.read_bytes()).hexdigest()
    return dex, side, metadata, digest, source_kind


def lua_metadata(metadata: dict[int, dict[str, dict[str, int]]]) -> str:
    lines = ["-- Generated shiny animation-strip metadata.", "return {"]
    for dex in range(FIRST_DEX, LAST_DEX + 1):
        front, back = metadata[dex]["front"], metadata[dex]["back"]
        lines.append(
            f"  [{dex}]={{front={{w={front['w']},h={front['h']},count={front['count']}}},"
            f"back={{w={back['w']},h={back['h']},count={back['count']}}}}},"
        )
    lines.append("}")
    return "\n".join(lines) + "\n"


def atomic_text(path: Path, value: str) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(value, encoding="utf-8", newline="\n")
    os.replace(temporary, path)


def main() -> None:
    metadata: dict[int, dict[str, dict[str, int]]] = {
        dex: {} for dex in range(FIRST_DEX, LAST_DEX + 1)
    }
    digests: dict[str, str] = {}
    tasks = [(dex, side) for dex in range(FIRST_DEX, LAST_DEX + 1)
             for side in SOURCE_CANDIDATES]
    source_counts: dict[str, int] = {}

    with tempfile.TemporaryDirectory(prefix="knd-shiny-") as temporary:
        stage = Path(temporary)
        failures: list[str] = []
        completed = 0
        with ThreadPoolExecutor(max_workers=WORKERS) as executor:
            futures = {executor.submit(build_one, stage, dex, side): (dex, side)
                       for dex, side in tasks}
            for future in as_completed(futures):
                dex, side = futures[future]
                try:
                    _, _, row, digest, source_kind = future.result()
                    metadata[dex][side] = row
                    digests[f"{side}/{dex:04d}.png"] = digest
                    source_counts[source_kind] = source_counts.get(source_kind, 0) + 1
                except Exception as error:  # report every missing/broken upstream file
                    failures.append(f"{side}/{dex}: {error}")
                completed += 1
                if completed % 100 == 0 or completed == len(tasks):
                    print(f"converted {completed}/{len(tasks)}", flush=True)
        if failures:
            print("\n".join(failures))
            raise SystemExit(f"aborting with {len(failures)} failed shiny sprites")

        target = ROOT / "assets" / "anim" / "shiny"
        for side in SOURCE_CANDIDATES:
            destination = target / side
            destination.mkdir(parents=True, exist_ok=True)
            for source in sorted((stage / side).glob("*.png")):
                shutil.copy2(source, destination / source.name)

    atomic_text(ROOT / "data" / "anim_shiny_meta.lua", lua_metadata(metadata))
    aggregate = hashlib.sha256()
    for name in sorted(digests):
        aggregate.update(name.encode("utf-8"))
        aggregate.update(digests[name].encode("ascii"))
    report = {
        "version": "0.9.11",
        "source": "PokeAPI/sprites Black/White shiny collection with PokeAPI default fallback",
        "sourceRepository": "https://github.com/PokeAPI/sprites",
        "sourceCommit": SOURCE_COMMIT,
        "license": "CC0-1.0 repository distribution; Pokemon imagery copyright The Pokemon Company",
        "species": LAST_DEX - FIRST_DEX + 1,
        "frontSheets": LAST_DEX - FIRST_DEX + 1,
        "backSheets": LAST_DEX - FIRST_DEX + 1,
        "totalSheets": len(digests),
        "totalFrames": sum(row[side]["count"] for row in metadata.values()
                           for side in SOURCE_CANDIDATES),
        "sourceCounts": dict(sorted(source_counts.items())),
        "aggregateSheetSha256": aggregate.hexdigest().upper(),
        "runtimeSelection": ["mon.shiny", "Gen 2 shiny DV pattern fallback"],
        "normalSpriteFallback": True,
    }
    atomic_text(ROOT / "SHINY_SPRITE_QA.json", json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
