"""Offline release checks for the bundled native-layout icon set."""
from pathlib import Path
import hashlib
import json
import struct

ROOT = Path(__file__).resolve().parents[1]
qa = json.loads((ROOT / "PARTY_ICON_QA.json").read_text(encoding="utf-8"))
assert qa["count"] == 1025
assert sorted(row["dex"] for row in qa["records"]) == list(range(1, 1026))
hashes = set()
for row in qa["records"]:
    raw = (ROOT / "assets/party_icons" / f'{row["dex"]:04}.png').read_bytes()
    assert raw[:8] == b"\x89PNG\r\n\x1a\n"
    assert struct.unpack(">II", raw[16:24]) == (16, 32)
    digest = hashlib.sha256(raw).hexdigest()
    assert digest == row["sha256"], row["dex"]
    hashes.add(digest)
assert len(hashes) == 1025, "Icons must be distinct for all species"
print("PASS: 1,025 unique party icon sheets; dimensions and checksums verified")
