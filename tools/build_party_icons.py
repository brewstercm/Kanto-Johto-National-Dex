"""Build compact native-layout party icons. Requires Pillow; network only at build time."""
from concurrent.futures import ThreadPoolExecutor
from io import BytesIO
from pathlib import Path
import hashlib
import json
import time
import urllib.request
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
COMMIT = "b2486a428a7548c874ad3900951d5334a40d21a5"
BASE = f"https://raw.githubusercontent.com/PokeAPI/sprites/{COMMIT}/sprites/pokemon/versions/generation-viii/icons"


def build(dex):
    target = ROOT / "assets" / "party_icons" / f"{dex:04}.png"
    source = f"{BASE}/{dex}.png" if dex <= 898 else f"assets/dex/front/{dex:04}.png"
    if dex <= 898:
        for attempt in range(4):
            try:
                with urllib.request.urlopen(source, timeout=30) as response:
                    raw = response.read()
                break
            except Exception:
                if attempt == 3:
                    raise
                time.sleep(attempt + 1)
    else:
        raw = (ROOT / source).read_bytes()
    with Image.open(BytesIO(raw)) as loaded:
        art = loaded.convert("RGBA")
    bbox = art.getchannel("A").getbbox()
    if not bbox:
        raise ValueError(f"Empty source icon: {dex}")
    art = art.crop(bbox)
    art.thumbnail((16, 15), Image.Resampling.NEAREST)
    sheet = Image.new("RGBA", (16, 32))
    x = (16 - art.width) // 2
    y = 16 - art.height
    sheet.alpha_composite(art, (x, y))
    sheet.alpha_composite(art, (x, 16 + y - 1))
    sheet.save(target, optimize=True)
    return {"dex": dex, "source": source,
            "sha256": hashlib.sha256(target.read_bytes()).hexdigest()}


if __name__ == "__main__":
    (ROOT / "assets" / "party_icons").mkdir(parents=True, exist_ok=True)
    with ThreadPoolExecutor(max_workers=12) as pool:
        records = list(pool.map(build, range(1, 1026)))
    (ROOT / "PARTY_ICON_QA.json").write_text(json.dumps({
        "commit": COMMIT, "count": len(records), "modern_icons": 898,
        "miniature_front_fallbacks": 127, "dimensions": [16, 32],
        "records": records}, indent=2) + "\n", encoding="utf-8")
    print("Built 1,025 two-frame party icons (898 modern icons, 127 miniature fronts).")
