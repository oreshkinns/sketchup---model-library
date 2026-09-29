#!/usr/bin/env python3
"""Build a read-only cloud catalog from cloud-library/models/<section>/*.skp."""

import argparse
import hashlib
import json
from pathlib import Path
from urllib.parse import quote


def asset_url(base_url: str, relative: Path) -> str:
    return base_url.rstrip("/") + "/" + "/".join(quote(part) for part in relative.parts)


def build(root: Path, base_url: str) -> dict:
    models = []
    for path in sorted((root / "models").glob("*/*.skp")):
        relative = path.relative_to(root)
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        entry = {
            "id": hashlib.sha256(str(relative).encode("utf-8")).hexdigest()[:20],
            "name": path.stem.replace("_", " "),
            "category": path.parent.name,
            "version": 1,
            "skp_url": asset_url(base_url, relative),
            "sha256": digest,
            "file_size_bytes": path.stat().st_size,
        }
        details_path = path.with_suffix('.json')
        if details_path.is_file():
            details = json.loads(details_path.read_text(encoding='utf-8'))
            if not isinstance(details, dict):
                raise ValueError(f"Expected metadata object: {details_path}")
            for key in ('version', 'tags', 'bbox_mm', 'faces_count', 'edges_count', 'materials_count'):
                if key in details:
                    entry[key] = details[key]
            if not isinstance(entry['version'], int) or isinstance(entry['version'], bool) or entry['version'] < 1:
                raise ValueError(f"Expected positive integer version: {details_path}")
        for extension in ("png", "jpg", "webp"):
            image = root / "thumbnails" / path.parent.name / f"{path.stem}.{extension}"
            if image.is_file():
                entry["thumbnail_url"] = asset_url(base_url, image.relative_to(root))
                break
        models.append(entry)
    return {"version": 1, "models": models}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path("cloud-library"))
    parser.add_argument(
        "--base-url",
        default="https://raw.githubusercontent.com/oreshkinns/sketchup---model-library/main/cloud-library",
    )
    args = parser.parse_args()
    root = args.root.resolve()
    root.mkdir(parents=True, exist_ok=True)
    manifest = build(root, args.base_url)
    (root / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"{len(manifest['models'])} models → {root / 'manifest.json'}")


if __name__ == "__main__":
    main()
