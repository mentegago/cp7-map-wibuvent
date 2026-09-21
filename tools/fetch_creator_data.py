#!/usr/bin/env python3
import argparse
import json
import urllib.request
from pathlib import Path
from urllib.parse import urljoin

BASE_URL = "https://cp7-config.wibuvent.com/"
DATA_DIR = Path(__file__).parent.parent / "data"


def read_json(location: str) -> dict:
    if location.startswith(("http://", "https://")):
        request = urllib.request.Request(
            location, headers={"User-Agent": "cp7-map-data-fetcher"}
        )
        with urllib.request.urlopen(request) as response:
            return json.loads(response.read().decode())
    return json.loads(Path(location).read_text(encoding="utf-8"))


def write_json(name: str, value: dict) -> None:
    output = DATA_DIR / name
    output.write_text(
        json.dumps(value, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Saved {output}")


def resolve(base: str, relative: str) -> str:
    if base.startswith(("http://", "https://")):
        return urljoin(base, relative)
    return str(Path(base) / Path(relative))


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Refresh the bundled fallback from the v1 catalog API."
    )
    parser.add_argument(
        "--source",
        default=BASE_URL,
        help="Site base URL or local config public directory",
    )
    parser.add_argument(
        "--allow-unversioned",
        action="store_true",
        help="Keep the bundled semantic version if deployed metadata lacks one",
    )
    args = parser.parse_args()

    manifest = read_json(resolve(args.source, "manifest.json"))
    version = read_json(resolve(args.source, "last-updated.json"))
    catalog = read_json(resolve(args.source, manifest["catalog"]))
    fandoms = read_json(resolve(args.source, manifest["fandomRegistry"]))

    for name, document in (
        ("manifest", manifest),
        ("catalog", catalog),
        ("fandom registry", fandoms),
    ):
        if not str(document.get("schemaVersion", "")).startswith("1."):
            raise ValueError(f"Unsupported {name} schema")
    if not isinstance(version.get("creator_data_version"), int):
        if not args.allow_unversioned:
            raise ValueError("last-updated.json has no creator_data_version")
        bundled_version_path = DATA_DIR / "last-updated-initial.json"
        bundled_version = json.loads(bundled_version_path.read_text(encoding="utf-8"))
        creator_data_version = bundled_version.get("creator_data_version")
        if not isinstance(creator_data_version, int):
            raise ValueError("No bundled creator_data_version to preserve")
        print(
            "Warning: deployed metadata is unversioned; preserving bundled "
            f"creator_data_version {creator_data_version}"
        )
        version = {**bundled_version, **version}

    write_json("last-updated-initial.json", version)
    write_json("catalog-initial.json", catalog)
    write_json("fandoms-initial.json", fandoms)


if __name__ == "__main__":
    main()
