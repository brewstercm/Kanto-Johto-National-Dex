"""Create a root-layout ZIP for Gen1Recomp's Import/Update/Versions menu."""
import argparse
import json
import re
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    manifest = json.loads((ROOT / "manifest.json").read_text(encoding="utf-8-sig"))
    assert manifest["github"] == "brewstercm/Kanto-Johto-National-Dex"
    assert re.fullmatch(r"[A-Za-z0-9_-]+", manifest["id"])
    assert re.fullmatch(r"\d+\.\d+\.\d+", manifest["version"])
    assert (ROOT / manifest["entry"]).is_file()
    args.output.mkdir(parents=True, exist_ok=True)
    archive = args.output / f"{manifest['id']}-{manifest['version']}.zip"
    excluded = {".git", ".github", "__pycache__", ".pytest_cache", ".venv"}
    files = [p for p in ROOT.rglob("*") if p.is_file()
             and not p.is_symlink() and not (set(p.relative_to(ROOT).parts) & excluded)
             and not any(part.startswith(".codex") for part in p.relative_to(ROOT).parts)
             and p.suffix not in {".zip", ".pyc"}]
    with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as out:
        for path in sorted(files):
            out.write(path, path.relative_to(ROOT).as_posix())
    with zipfile.ZipFile(archive) as out:
        assert out.testzip() is None
        assert "manifest.json" in out.namelist() and manifest["entry"] in out.namelist()
        assert json.loads(out.read("manifest.json")) == manifest
    print(archive)


if __name__ == "__main__":
    main()
