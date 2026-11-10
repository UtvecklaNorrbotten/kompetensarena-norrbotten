"""Publish UKÄ indicator 33 (HST) from the verified offline package.

Reads only ``hst-collection/hst-full.sqlite`` from the extracted package
``UKA_HST_2016-17_2025-26_2026-11-09.zip``. Legacy reference/staging material
and pilot fixtures are never read. Nothing is fetched from UKÄ.

Steps, all before any write:
1. archive SHA-256/size and every file in ``README_filer.json`` are verified;
2. the SQLite binding (indicator 33, policy, periods, genders, ages) is checked;
3. rows are normalized to the server's compact format and chunked;
4. the locally built manifest must equal the server manifest bound to the
   import key exactly, including all chunk hashes (``--server-manifest`` file
   for an offline dry run, or read from the server).

With ``--publish`` the script re-binds via ``uka_verified_start`` (which
refuses any other manifest), reads ``received_indices`` from
``uka_verified_status`` and sends only chunks that are really missing, then
calls ``uka_verified_finalize``. It is safe to rerun after an interruption;
progress is appended to ``--log`` as JSON lines.

Normalization (identical to the import that created the server manifest):
* rows are read in ``observations.key`` order;
* university code -> metadata label (``uni:1`` -> ``Riket``);
* dimension keys Studieform/Ämnesområde/Ämnesdelområde/Ämnesgrupp ->
  studieform/amnesomrade/amnesdelomrade/amnesgrupp, full parent path kept;
  age -> ``aldersgrupp`` except the source Total, which has no key;
* gender Kvinnor/Män/source Total and value text are kept unchanged;
* dictionaries: periods as in the binding, universities sorted, dimensions in
  first-appearance order; rows ``[period, university, gender, dimension, value]``;
* chunks of 5000 rows serialized as compact UTF-8 JSON.
"""
from __future__ import annotations

import argparse
import collections
import hashlib
import json
import os
import re
import sqlite3
import sys
import time
from pathlib import Path

INDICATOR = "uka-hst"
POLICY = "hst-csv-year-university-study-root-controls-v1"
GENDERS = ["Kvinnor", "Män", "Total"]
AGES = ["-24", "25-34", "35-", "Total"]
STAGING = "hst-collection/hst-full.sqlite"
METADATA = "hst-collection/metadata.json"
FILE_LIST = "README_filer.json"
CHUNK_ROWS = 5000
DIM_KEYS = {"Studieform": "studieform", "Ämnesområde": "amnesomrade",
            "Ämnesdelområde": "amnesdelomrade", "Ämnesgrupp": "amnesgrupp"}
VALUE_TEXT = re.compile(r"^[0-9]+([.][0-9]+)?([Ee][+-]?[0-9]+)?$")
FORBIDDEN_PARTS = {"legacy-reference", "legacy-staging", "reference-99", "collection-99"}


class ManifestMismatch(Exception):
    """The locally rebuilt manifest differs from the server-bound manifest."""


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def verify_files(root: Path) -> int:
    listing = json.loads((root / FILE_LIST).read_text(encoding="utf-8"))
    files = listing["files"]
    paths = {f["path"] for f in files}
    if STAGING not in paths or METADATA not in paths:
        raise ValueError("README_filer.json saknar staging eller metadata")
    for f in files:
        rel = Path(f["path"])
        if rel.is_absolute() or ".." in rel.parts:
            raise ValueError(f"Otillåten sökväg: {rel}")
        p = root / rel
        if p.stat().st_size != f["bytes"] or sha256_file(p) != f["sha256"]:
            raise ValueError(f"Kontrollsumma/storlek avviker: {rel}")
    return len(files)


def university_names(metadata: dict) -> dict[str, str]:
    names = {}
    for o in metadata["universities"]:
        if not o["value"].startswith("uni:") or not o["label"].strip():
            raise ValueError(f"Ogiltigt lärosäte: {o}")
        names[o["value"].removeprefix("uni:")] = o["label"].strip()
    if names.get("1") != "Riket" or len(set(names.values())) != len(names):
        raise ValueError("Lärosätesmetadata ogiltig")
    return names


def dimension_of(p: dict) -> dict:
    raw = p.get("dimensions") or {}
    if set(raw) - set(DIM_KEYS):
        raise ValueError(f"Oväntad dimension: {raw}")
    d = {}
    for k, v in raw.items():
        if not isinstance(v, str) or not v or v != v.strip() or v == "Total":
            raise ValueError(f"Ogiltigt dimensionsvärde: {raw}")
        d[DIM_KEYS[k]] = v
    if p.get("age") not in AGES:
        raise ValueError(f"Oväntad ålder: {p.get('age')}")
    if p["age"] != "Total":
        d["aldersgrupp"] = p["age"]
    return d


def normalize(staging: Path, metadata: dict) -> tuple[list[dict], list[str]]:
    if FORBIDDEN_PARTS & set(staging.parts) or staging.name != "hst-full.sqlite":
        raise ValueError("Endast hst-collection/hst-full.sqlite får läsas")
    names = university_names(metadata)
    db = sqlite3.connect(f"file:{staging}?mode=ro", uri=True)
    try:
        b = json.loads(db.execute("select binding from meta").fetchone()[0])
        if (b.get("indicator") != 33 or b.get("policy") != POLICY or b.get("genders") != GENDERS
                or b.get("ages") != AGES or b.get("metadata_hash") != metadata.get("metadata_hash")):
            raise ValueError("Stagingbindning matchar inte HST/metadata")
        periods = list(b["periods"])
        rows = []
        for period, payload in db.execute("select period, payload from observations order by key"):
            p = json.loads(payload)
            if p.get("indicator") != 33 or p.get("period") != period or period not in periods:
                raise ValueError(f"Fel indikator/period: {p}")
            if p.get("gender") not in GENDERS:
                raise ValueError(f"Oväntat kön: {p.get('gender')}")
            v = p.get("value")
            if not isinstance(v, str) or not VALUE_TEXT.match(v):
                raise ValueError(f"Värde är inte exakt numerisk text: {v!r}")
            if p.get("university") not in names:
                raise ValueError(f"Okänd lärosäteskod: {p.get('university')}")
            rows.append({"period": period, "university": names[p["university"]],
                         "gender": p["gender"], "dimensions": dimension_of(p), "value": v})
    finally:
        db.close()
    ident = collections.Counter(
        (r["period"], r["university"], r["gender"], json.dumps(r["dimensions"], sort_keys=True))
        for r in rows)
    if not rows or any(n > 1 for n in ident.values()):
        raise ValueError("Tom staging eller dubblett efter normalisering")
    for p in periods:
        if not any(r["period"] == p and r["university"] == "Riket" for r in rows):
            raise ValueError(f"Riket saknas {p}")
    return rows, periods


def dim_text(d: dict) -> str:
    return json.dumps(d, sort_keys=True, ensure_ascii=False)


def build_manifest(rows: list[dict], periods: list[str], archive_sha: str,
                   snapshot: str) -> tuple[dict, list[str]]:
    universities = sorted({r["university"] for r in rows})
    dims: dict[str, int] = {}
    for r in rows:
        dims.setdefault(dim_text(r["dimensions"]), len(dims))
    pi = {p: i for i, p in enumerate(periods)}
    ui = {u: i for i, u in enumerate(universities)}
    gi = {g: i for i, g in enumerate(GENDERS)}
    compact = [[pi[r["period"]], ui[r["university"]], gi[r["gender"]],
                dims[dim_text(r["dimensions"])], r["value"]] for r in rows]
    payloads, chunks = [], []
    for index, start in enumerate(range(0, len(compact), CHUNK_ROWS)):
        part = compact[start:start + CHUNK_ROWS]
        text = json.dumps(part, ensure_ascii=False, separators=(",", ":"))
        payloads.append(text)
        chunks.append({"index": index, "rows": len(part),
                       "sha256": hashlib.sha256(text.encode("utf-8")).hexdigest()})
    counts = collections.Counter(
        (r["period"], r["gender"], r["dimensions"].get("aldersgrupp", "Total")) for r in rows)
    coverage = [{"period": p, "gender": g, "age": a, "rows": counts[(p, g, a)]}
                for p in sorted(periods) for g in GENDERS for a in AGES if counts[(p, g, a)]]
    manifest = {
        "indicator": INDICATOR, "version": "1", "policy": POLICY, "archive_sha256": archive_sha,
        "snapshot": snapshot, "rows": len(rows), "periods": periods,
        "universities": universities, "genders": GENDERS,
        "dimensions": [json.loads(d) for d in dims], "coverage": coverage, "chunks": chunks,
    }
    return manifest, payloads


def jsonb_text(v) -> str:
    """PostgreSQL jsonb::text rendering (keys ordered by length, then bytes)."""
    if isinstance(v, dict):
        keys = sorted(v, key=lambda k: (len(k.encode()), k.encode()))
        return "{" + ", ".join(json.dumps(k, ensure_ascii=False) + ": " + jsonb_text(v[k])
                               for k in keys) + "}"
    if isinstance(v, list):
        return "[" + ", ".join(jsonb_text(x) for x in v) + "]"
    return json.dumps(v, ensure_ascii=False)


def compare_manifest(local: dict, server: dict) -> None:
    """Raise ManifestMismatch on any difference; chunk hashes are checked one by one."""
    lc, sc = local.get("chunks", []), server.get("chunks", [])
    if len(lc) != len(sc):
        raise ManifestMismatch(f"Antal chunkar {len(lc)} ≠ server {len(sc)}")
    bad = [c["index"] for c, s in zip(lc, sc) if c != s]
    if bad:
        raise ManifestMismatch(f"{len(bad)} chunkar avviker från servermanifestet, första {bad[:10]}")
    for key in sorted(set(local) | set(server)):
        if local.get(key) != server.get(key):
            raise ManifestMismatch(f"Manifestfältet {key} avviker från servern")


def missing_chunks(status: dict, total: int) -> list[int]:
    """Indices not yet stored on the server. Received indices need not be contiguous."""
    received = set(status.get("received_indices") or [])
    if any(not isinstance(i, int) or i < 0 or i >= total for i in received):
        raise ValueError("Servern rapporterar chunkindex utanför manifestet")
    return [i for i in range(total) if i not in received]


class Rpc:
    def __init__(self, url: str, key: str):
        import requests
        self.s = requests.Session()
        self.base = url.rstrip("/") + "/rest/v1/"
        self.s.headers.update({"apikey": key, "Content-Type": "application/json"})
        if not key.startswith("sb_"):
            self.s.headers["Authorization"] = f"Bearer {key}"

    def __call__(self, name: str, body: dict, timeout: int = 300):
        for attempt in range(5):
            try:
                r = self.s.post(self.base + "rpc/" + name, json=body, timeout=timeout)
            except Exception as e:  # network hiccup: retry, the calls are idempotent
                err = str(e)
            else:
                if r.status_code < 300:
                    return r.json()
                err = f"HTTP {r.status_code}: {r.text[:500]}"
                if r.status_code < 500 and r.status_code != 429:
                    break
            time.sleep(5 * (attempt + 1))
        raise RuntimeError(f"{name}: {err}")

    def server_manifest(self, import_key: str) -> dict:
        r = self.s.get(self.base + "uka_verified_imports",
                       params={"import_key": f"eq.{import_key}", "select": "manifest,manifest_hash"},
                       timeout=120)
        r.raise_for_status()
        data = r.json()
        if len(data) != 1:
            raise ManifestMismatch("Import key saknar servermanifest")
        return data[0]


def log(path: Path | None, event: dict) -> None:
    event = {"t": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), **event}
    line = json.dumps(event, ensure_ascii=False)
    print(line, flush=True)
    if path:
        with path.open("a", encoding="utf-8") as f:
            f.write(line + "\n")


def publish(rpc, manifest: dict, payloads: list[str], import_key: str, logp) -> dict:
    started = rpc("uka_verified_start", {"p_import_key": import_key, "p_manifest": manifest})
    log(logp, {"start": started})
    if not started.get("resumed"):
        raise RuntimeError("Förväntade återstart av befintlig import, fick ny import")
    status = rpc("uka_verified_status", {"p_import_key": import_key})
    todo = missing_chunks(status, len(payloads))
    log(logp, {"received": status["received_chunks"], "missing": todo})
    for i in todo:
        res = rpc("uka_verified_chunk", {"p_import_key": import_key, "p_index": i,
                                         "p_payload": payloads[i]})
        log(logp, {"chunk": i, "result": res})
    status = rpc("uka_verified_status", {"p_import_key": import_key})
    if (missing_chunks(status, len(payloads)) or status["received_rows"] != manifest["rows"]
            or status["status"] != "ready"):
        raise RuntimeError(f"Ofullständig uppladdning: { {k: v for k, v in status.items() if k != 'received_indices'} }")
    result = rpc("uka_verified_finalize", {"p_import_key": import_key}, timeout=900)
    log(logp, {"finalize": result})
    return result


def main(argv=None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True, type=Path)
    ap.add_argument("--archive", required=True, type=Path)
    ap.add_argument("--archive-sha256", required=True)
    ap.add_argument("--archive-bytes", required=True, type=int)
    ap.add_argument("--expected-rows", required=True, type=int)
    ap.add_argument("--import-key", required=True)
    ap.add_argument("--manifest-hash", required=True, help="Förväntad server-manifest_hash")
    ap.add_argument("--server-manifest", type=Path, help="Offline torrkörning mot sparat manifest")
    ap.add_argument("--log", type=Path)
    ap.add_argument("--publish", action="store_true")
    a = ap.parse_args(argv)

    if a.archive.stat().st_size != a.archive_bytes or sha256_file(a.archive) != a.archive_sha256:
        raise SystemExit("Paketets SHA-256 eller storlek avviker")
    n_files = verify_files(a.root)
    metadata = json.loads((a.root / METADATA).read_text(encoding="utf-8"))
    rows, periods = normalize(a.root / STAGING, metadata)
    if len(rows) != a.expected_rows:
        raise SystemExit(f"Radantal {len(rows)} ≠ {a.expected_rows}")
    manifest, payloads = build_manifest(rows, periods, a.archive_sha256, metadata["snapshot"])
    local_hash = hashlib.sha256(jsonb_text(manifest).encode()).hexdigest()

    rpc = None
    if a.server_manifest:
        server = json.loads(a.server_manifest.read_text(encoding="utf-8"))
        server_hash = a.manifest_hash
    else:
        rpc = Rpc(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_ROLE_KEY"])
        got = rpc.server_manifest(a.import_key)
        server, server_hash = got["manifest"], got["manifest_hash"]
    if server_hash != a.manifest_hash:
        raise ManifestMismatch("Serverns manifest_hash avviker från godkänd")
    compare_manifest(manifest, server)
    log(a.log, {"verified_files": n_files, "rows": len(rows), "chunks": len(payloads),
                "chunk_hashes_match": len(payloads), "dimensions": len(manifest["dimensions"]),
                "universities": len(manifest["universities"]),
                "local_jsonb_manifest_sha256": local_hash,
                "manifest_hash_reproduced": local_hash == a.manifest_hash})
    if not a.publish:
        return 0
    rpc = rpc or Rpc(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_ROLE_KEY"])
    publish(rpc, manifest, payloads, a.import_key, a.log)
    return 0


if __name__ == "__main__":
    sys.exit(main())
