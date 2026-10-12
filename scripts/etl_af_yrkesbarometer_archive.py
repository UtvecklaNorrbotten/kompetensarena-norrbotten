#!/usr/bin/env python3
"""Read-only snapshot of AF Yrkesbarometern 2024 onward.

Outputs full source JSON files and a manifest. Never conflates the previous
2007-2023 prognostic methods with Yrkesbarometern. No database writes.
"""
import argparse
import datetime as dt
import hashlib
import json
import pathlib
import urllib.request

BASE = "https://data.arbetsformedlingen.se/prognoser/"
SOURCES = [
    ("historiska/yrkesbarometer_2024-1.json", "2024-1"),
    ("historiska/yrkesbarometer_2024-2.json", "2024-2"),
    ("historiska/yrkesbarometer_2025-1.json", "2025-1"),
    ("historiska/yrkesbarometer_2025-2.json", "2025-2"),
    ("yrkesbarometer.json", "current"),
]


def fetch(url):
    req = urllib.request.Request(url, headers={
        "User-Agent": "KompetensarenaNorrbotten-Yrkesbarometer/1.0",
        "Accept": "application/json"
    })
    with urllib.request.urlopen(req, timeout=120) as response:
        body = response.read(80 * 1024 * 1024 + 1)
        if len(body) > 80 * 1024 * 1024:
            raise ValueError("File exceeds 80 MB guard")
        return body, response.headers.get("Last-Modified"), response.headers.get("ETag")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", default="artifacts/af-yrkesbarometer")
    args = parser.parse_args()
    out = pathlib.Path(args.output)
    out.mkdir(parents=True, exist_ok=True)
    manifest = {"retrieved_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
                "source_collection": BASE, "series": "yrkesbarometer-2024-onward",
                "files": []}
    seen = set()
    for relative, edition in SOURCES:
        body, modified, etag = fetch(BASE + relative)
        value = json.loads(body)
        if not isinstance(value, (list, dict)) or not value:
            raise ValueError("Empty or unexpected JSON root in " + relative)
        filename = pathlib.Path(relative).name
        if filename in seen:
            raise ValueError("Duplicate filename " + filename)
        seen.add(filename)
        (out / filename).write_bytes(body)
        info = {"path": relative, "edition": edition, "filename": filename,
                "bytes": len(body), "sha256": hashlib.sha256(body).hexdigest(),
                "root_type": type(value).__name__, "last_modified": modified,
                "etag": etag}
        if isinstance(value, list):
            info["root_entries"] = len(value)
            if value and isinstance(value[0], dict):
                info["first_record_keys"] = sorted(value[0])
        else:
            info["root_keys"] = sorted(value)
        manifest["files"].append(info)
        print(edition, info["bytes"], info["sha256"], flush=True)
    (out / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("Complete:", len(manifest["files"]), "source files")


if __name__ == "__main__":
    main()
