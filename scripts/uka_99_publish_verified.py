"""Publish UKÄ indicator 99 (Söktryck) from a verified offline staging package.

Reads only ``collection-99/99-full.sqlite`` from an extracted package. The
older ``reference-99`` material is never read or added. Nothing is fetched
from UKÄ. Without ``--publish`` the script only verifies and prints a summary.

Publishing uses the server-side ``uka99_verified_*`` functions: the manifest
is bound to an import key, every chunk is checked against its manifest hash,
and activation happens atomically only after full coverage is verified. The
previously active batch is retained for rollback.
"""
from __future__ import annotations

import argparse
import collections
import hashlib
import json
import os
import sqlite3
import sys
from decimal import Decimal
from pathlib import Path

INDICATOR = "uka-soktryck-yrkesprogram"
POLICY = "99-csv-term-university-program-root-controls-v1"
GENDERS = ["Kvinnor", "Män", "Total"]
STAGING = "collection-99/99-full.sqlite"
METADATA = "collection-99/metadata/99.json"
CHUNK_ROWS = 5000
VALUE_TEXT = __import__("re").compile(r"^[0-9]+(\.[0-9]+)?$")


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def verify_checksums(root: Path) -> int:
    """Every file listed in checksums.json must exist with the listed hash."""
    listed = json.loads((root / "checksums.json").read_text(encoding="utf-8"))
    if STAGING not in listed or METADATA not in listed:
        raise ValueError("checksums.json saknar staging eller metadata")
    for rel, expected in listed.items():
        if Path(rel).is_absolute() or ".." in Path(rel).parts:
            raise ValueError(f"Otillåten sökväg i checksums.json: {rel}")
        if sha256_file(root / rel) != expected:
            raise ValueError(f"Kontrollsumma avviker: {rel}")
    return len(listed)


def university_names(metadata: dict) -> dict[str, str]:
    names: dict[str, str] = {}
    for option in metadata["universities"]:
        value, label = option["value"], option["label"].strip()
        if not value.startswith("uni:") or not label:
            raise ValueError(f"Ogiltigt lärosätesalternativ: {option}")
        names[value.removeprefix("uni:")] = label
    if names.get("1") != "Riket":
        raise ValueError("uni:1 måste vara Riket")
    if len(set(names.values())) != len(names):
        raise ValueError("Två lärosäteskoder har samma namn")
    return names


def normalize(staging: Path, metadata: dict) -> tuple[list[dict], dict]:
    """Map the package rows to the existing normalize_uka convention.

    * university code -> metadata label, uni:1 -> "Riket"
    * gender Kvinnor/Män/source Total kept as-is
    * program dimension key ``program``; the source program Total has no key
    * age is the technical Total only and is never stored
    * value text is kept exactly (no rounding, no zeros for absence)
    """
    if "reference-99" in staging.parts:
        raise ValueError("reference-99 får aldrig publiceras")
    names = university_names(metadata)
    db = sqlite3.connect(f"file:{staging}?mode=ro", uri=True)
    try:
        binding = json.loads(db.execute("select binding from meta").fetchone()[0])
        if (binding.get("indicator") != 99 or binding.get("policy") != POLICY
                or binding.get("genders") != GENDERS or binding.get("ages") != ["Total"]
                or binding.get("metadata_hash") != metadata.get("metadata_hash")):
            raise ValueError("Stagingbindning matchar inte indikator 99/metadata")
        periods = list(binding["periods"])
        rows = []
        for period, payload in db.execute("select period, payload from observations"):
            p = json.loads(payload)
            if p.get("indicator") != 99 or p.get("period") != period or period not in periods:
                raise ValueError(f"Fel indikator/period: {p}")
            if p.get("age") != "Total":
                raise ValueError("Oväntad åldersuppdelning")
            if p.get("gender") not in GENDERS:
                raise ValueError(f"Oväntat kön: {p.get('gender')}")
            dims = p.get("dimensions") or {}
            if set(dims) - {"Program"}:
                raise ValueError(f"Oväntad dimension: {dims}")
            program = dims.get("Program")
            if program is not None and (program in ("", "Total") or program.strip() != program):
                raise ValueError(f"Ogiltigt program: {program!r}")
            value = p.get("value")
            if not isinstance(value, str) or not VALUE_TEXT.match(value):
                raise ValueError(f"Värde är inte exakt numerisk text: {value!r}")
            if Decimal(repr(float(value))) != Decimal(value):
                raise ValueError(f"Värdet kan inte lagras exakt: {value}")
            code = p.get("university")
            if code not in names:
                raise ValueError(f"Okänd lärosäteskod: {code}")
            rows.append({
                "period": period,
                "university": names[code],
                "gender": p["gender"],
                "dimensions": {} if program is None else {"program": program},
                "value": value,
            })
        summaries = {
            period: json.loads(summary)
            for period, summary in db.execute("select period, summary from years")
        }
    finally:
        db.close()
    if not rows:
        raise ValueError("Tom staging")
    identity = collections.Counter(
        (r["period"], r["university"], r["gender"], json.dumps(r["dimensions"], sort_keys=True))
        for r in rows
    )
    if any(n > 1 for n in identity.values()):
        raise ValueError("Dubblett efter normalisering")
    if set(summaries) != set(periods):
        raise ValueError("Terminssammanfattningar saknas")
    expected = {
        (period, c["gender"]): c["observations"]
        for period, s in summaries.items() for c in s["coverage"]
    }
    actual = collections.Counter((r["period"], r["gender"]) for r in rows)
    if dict(actual) != expected:
        raise ValueError("Radantal per termin/kön avviker från terminssammanfattningarna")
    by_period = collections.defaultdict(set)
    for r in rows:
        by_period[r["period"]].add(r["university"])
    if any("Riket" not in by_period[p] for p in periods):
        raise ValueError("Riket saknas för en termin")
    return rows, {"periods": periods, "coverage": expected}


def build_manifest(rows: list[dict], info: dict, archive_sha: str, staging_sha: str,
                   snapshot: str, review: dict, basis: str) -> tuple[dict, list[str]]:
    periods = info["periods"]
    universities = sorted({r["university"] for r in rows}, key=lambda s: (s != "Riket", s))
    dims = sorted({json.dumps(r["dimensions"], sort_keys=True, ensure_ascii=False) for r in rows})
    pi = {p: i for i, p in enumerate(periods)}
    ui = {u: i for i, u in enumerate(universities)}
    gi = {g: i for i, g in enumerate(GENDERS)}
    di = {d: i for i, d in enumerate(dims)}
    compact = sorted(
        [pi[r["period"]], ui[r["university"]], gi[r["gender"]],
         di[json.dumps(r["dimensions"], sort_keys=True, ensure_ascii=False)], r["value"]]
        for r in rows
    )
    payloads, chunks = [], []
    for index, start in enumerate(range(0, len(compact), CHUNK_ROWS)):
        part = compact[start:start + CHUNK_ROWS]
        text = json.dumps(part, ensure_ascii=False, separators=(",", ":"))
        payloads.append(text)
        chunks.append({"index": index, "rows": len(part),
                       "sha256": hashlib.sha256(text.encode("utf-8")).hexdigest()})
    coverage = [
        {"period": p, "gender": g, "rows": info["coverage"][(p, g)]}
        for p in periods for g in GENDERS if (p, g) in info["coverage"]
    ]
    manifest = {
        "indicator": INDICATOR,
        "version": "1",
        "policy": POLICY,
        "archive_sha256": archive_sha,
        "staging_sha256": staging_sha,
        "snapshot": snapshot,
        "rows": len(rows),
        "periods": periods,
        "universities": universities,
        "genders": GENDERS,
        "ages": ["Total"],
        "dimensions": [json.loads(d) for d in dims],
        "coverage": coverage,
        "chunks": chunks,
        "review": review,
        "publication_basis": basis,
    }
    return manifest, payloads


class Rpc:
    def __init__(self, url: str, key: str):
        import requests
        self.session = requests.Session()
        self.url = url.rstrip("/") + "/rest/v1/rpc/"
        self.session.headers.update({"apikey": key, "Content-Type": "application/json"})
        if not key.startswith("sb_"):
            self.session.headers["Authorization"] = f"Bearer {key}"

    def __call__(self, name: str, body: dict, timeout: int = 300):
        r = self.session.post(self.url + name, json=body, timeout=timeout)
        if r.status_code >= 300:
            raise RuntimeError(f"{name}: HTTP {r.status_code}: {r.text[:500]}")
        return r.json()


def publish(manifest: dict, payloads: list[str], import_key: str) -> dict:
    rpc = Rpc(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_ROLE_KEY"])
    started = rpc("uka99_verified_start", {"p_import_key": import_key, "p_manifest": manifest})
    print(json.dumps({"start": started}, ensure_ascii=False))
    status = rpc("uka_verified_status", {"p_import_key": import_key})
    received = set(status.get("received_indices") or [])
    for chunk, text in zip(manifest["chunks"], payloads):
        if chunk["index"] in received:
            continue
        result = rpc("uka99_verified_chunk",
                     {"p_import_key": import_key, "p_index": chunk["index"], "p_payload": text})
        print(json.dumps({"chunk": result}, ensure_ascii=False))
    status = rpc("uka_verified_status", {"p_import_key": import_key})
    if status["received_chunks"] != len(payloads) or status["received_rows"] != manifest["rows"]:
        raise RuntimeError(f"Ofullständig uppladdning: {status}")
    return rpc("uka99_verified_finalize", {"p_import_key": import_key}, timeout=900)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True, type=Path, help="Uppackat paket")
    ap.add_argument("--archive", required=True, type=Path, help="Ursprunglig ZIP")
    ap.add_argument("--archive-sha256", required=True)
    ap.add_argument("--archive-bytes", required=True, type=int)
    ap.add_argument("--expected-rows", required=True, type=int)
    ap.add_argument("--publish", action="store_true")
    args = ap.parse_args(argv)

    if sha256_file(args.archive) != args.archive_sha256 or args.archive.stat().st_size != args.archive_bytes:
        raise SystemExit("Paketets SHA-256 eller storlek avviker från godkänt paket")
    verified_files = verify_checksums(args.root)
    metadata = json.loads((args.root / METADATA).read_text(encoding="utf-8"))
    staging = args.root / STAGING
    rows, info = normalize(staging, metadata)
    if len(rows) != args.expected_rows:
        raise SystemExit(f"Radantal {len(rows)} avviker från godkända {args.expected_rows}")
    review = {"full_source_coverage_verified": False, "source_release_verified": False,
              "package_publish_allowed": False, "user_approved_publication": True}
    basis = ("Användargodkänd publicering 2026-11-10 av filbaserad staging (100 CSV-exporter, "
             "80 JSON-rotkontroller). Rot-/partitionskontroller passerar; varje historisk "
             "detaljcell, sekretessemantik och officiell källrevision är inte oberoende verifierade.")
    manifest, payloads = build_manifest(rows, info, args.archive_sha256, sha256_file(staging),
                                        metadata["snapshot"], review, basis)
    gender_counts = collections.Counter(r["gender"] for r in rows)
    print(json.dumps({
        "verified_files": verified_files, "rows": len(rows), "periods": len(info["periods"]),
        "universities": len(manifest["universities"]), "dimensions": len(manifest["dimensions"]),
        "genders": dict(gender_counts), "chunks": [c["rows"] for c in manifest["chunks"]],
        "manifest_sha256": hashlib.sha256(
            json.dumps(manifest, sort_keys=True, ensure_ascii=False).encode()).hexdigest(),
    }, ensure_ascii=False))
    if not args.publish:
        return 0
    import_key = f"uka-99-{metadata['snapshot']}-{args.archive_sha256[:12]}"
    result = publish(manifest, payloads, import_key)
    print(json.dumps({"import_key": import_key, "finalize": result}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
