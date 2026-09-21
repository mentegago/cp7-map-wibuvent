#!/usr/bin/env python3
"""Convert Cardinal's circle API response to the app's catalog v1 schema."""

import argparse
import hashlib
import json
import urllib.request
from pathlib import Path
from urllib.parse import urlparse


DEFAULT_SOURCE = "https://cardinal.wibuvent.com/api/v1/events/comipara-7/circles"
DATA_DIR = Path(__file__).parent.parent / "data"


def read_json(source: str) -> dict:
    if source.startswith(("http://", "https://")):
        request = urllib.request.Request(
            source, headers={"User-Agent": "cp7-map-cardinal-converter"}
        )
        with urllib.request.urlopen(request) as response:
            return json.loads(response.read().decode("utf-8"))
    return json.loads(Path(source).read_text(encoding="utf-8"))


def stable_id(value: str, used: set[int]) -> int:
    candidate = int(hashlib.sha256(value.encode("utf-8")).hexdigest()[:8], 16)
    candidate &= 0x7FFFFFFF
    candidate = candidate or 1
    while candidate in used:
        candidate = candidate + 1 if candidate < 0x7FFFFFFF else 1
    used.add(candidate)
    return candidate


def normalize_url(value: str) -> str:
    url = value.strip()
    if url and not urlparse(url).scheme:
        return f"https://{url}"
    return url


def link_type(value: str) -> str:
    host = urlparse(normalize_url(value)).netloc.lower().removeprefix("www.")
    if host == "facebook.com" or host.endswith(".facebook.com"):
        return "facebook"
    if host in {"instagram.com", "instagr.am"} or host.endswith(".instagram.com"):
        return "instagram"
    if host in {"x.com", "twitter.com", "t.co"} or host.endswith(".twitter.com"):
        return "twitter"
    marketplace_hosts = (
        "shopee.", "tokopedia.", "booth.pm", "gumroad.com", "ko-fi.com",
        "karyakarsa.com", "trakteer.id", "sociabuzz.com", "etsy.com",
    )
    if any(host == domain or host.endswith(domain) for domain in marketplace_hosts):
        return "marketplace"
    return "other"


def convert(document: dict) -> tuple[dict, dict]:
    circles = document.get("data")
    if not isinstance(circles, list):
        raise ValueError("Cardinal response does not contain a data list")

    fandom_names: dict[str, str] = {}
    for circle in circles:
        for name in circle.get("fandoms") or []:
            label = str(name).strip()
            if label:
                fandom_names.setdefault(label.casefold(), label)

    fandom_id_by_key = {
        key: index for index, key in enumerate(sorted(fandom_names), start=1)
    }
    fandom_registry = {
        "schemaVersion": "1.0.0",
        "source": {"url": DEFAULT_SOURCE, "schemaVersion": "cardinal-circles"},
        "fandoms": [
            {
                "id": fandom_id_by_key[key],
                "name": fandom_names[key],
                "kind": "event_tag",
                "parentId": None,
                "alternateNames": [],
            }
            for key in sorted(fandom_names)
        ],
    }

    used_ids: set[int] = set()
    exhibitors = []
    for circle in circles:
        uuid = str(circle.get("id", ""))
        fandom_ids = [
            fandom_id_by_key[str(name).strip().casefold()]
            for name in circle.get("fandoms") or []
            if str(name).strip().casefold() in fandom_id_by_key
        ]
        links = [
            {
                "type": link_type(str(link.get("url", ""))),
                "url": normalize_url(str(link.get("url", ""))),
            }
            for link in circle.get("urls") or []
            if isinstance(link, dict) and normalize_url(str(link.get("url", "")))
        ]
        exhibitors.append(
            {
                "id": str(stable_id(uuid, used_ids)),
                "name": str(circle.get("name") or "Unnamed circle"),
                "spaces": [
                    {"code": str(code), "type": "booth"}
                    for code in circle.get("booth_locations") or []
                    if str(code).strip()
                ],
                "attendanceDates": [str(day) for day in circle.get("day") or []],
                "contentRating": None,
                "offerings": [str(value) for value in circle.get("works_type") or []],
                "assets": {
                    "thumbnail": circle.get("circle_cut"),
                    "gallery": [str(url) for url in circle.get("photoworks") or []],
                },
                "links": links,
                "fandomIds": fandom_ids,
            }
        )

    catalog = {
        "schemaVersion": "1.0.0",
        "sources": {"cardinal": {"url": DEFAULT_SOURCE}},
        "event": {
            "id": "comipara-7",
            "name": "Comipara 7",
            "series": {"id": "comipara", "name": "Comipara"},
            "edition": 7,
            "days": [
                {"id": "2026-10-17", "label": "Saturday"},
                {"id": "2026-10-18", "label": "Sunday"},
            ],
        },
        "stats": {
            "exhibitors": len(exhibitors),
            "fandomsReferenced": len(fandom_registry["fandoms"]),
        },
        "exhibitors": exhibitors,
    }
    return catalog, fandom_registry


def write_json(name: str, value: dict) -> None:
    path = DATA_DIR / name
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Saved {path}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", default=DEFAULT_SOURCE)
    args = parser.parse_args()
    catalog, fandoms = convert(read_json(args.source))
    write_json("catalog-initial.json", catalog)
    write_json("fandoms-initial.json", fandoms)
    write_json(
        "last-updated-initial.json",
        {
            "current_version": 1,
            "release_notes": "Initial Comipara 7 creator catalog.",
            "creator_data_version": 1,
            "lastUpdated": "2026-09-21T00:00:00Z",
        },
    )


if __name__ == "__main__":
    main()
