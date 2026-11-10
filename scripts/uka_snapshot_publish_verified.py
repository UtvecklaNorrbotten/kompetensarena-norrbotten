"""Publish one of the eight CSV-staged UKÄ indicators through the shared
manifest-bound snapshot import (``uka_snapshot_*``, see
``drizzle/uka_snapshot_verified_import.applied.sql``).

Indicators: API 13, 31, 97, 108, 136, 77, 134, 135. HST (33) and 99 keep their
own publishers and are refused by the server for this path.

Input is a *frozen* manifest computed independently and locally from the
frozen CSV staging package (e.g. ``docs/data/uka-snapshot-2026-11-10-all-pilot-13.json``).
It contains only non-reversible per-period SHA-256 fingerprints and coverage
counts; no raw observations are read or transferred by this script.

Canonical fingerprint (identical in SQL and here):
    line  = jsonb_build_array(period, university, gender, dimensions, value_text)::text
    value_text = fixed decimal text, trailing decimal zeros removed
    period hash = sha256(join("\\n", sorted(lines, bytewise)))   -- no final newline

Modes (default is a check, which never writes):
* (default)     compare the frozen manifest with the currently active batch via
                ``uka_snapshot_verify_batch`` (read-only).
* ``--copy``    bind the manifest (``uka_snapshot_start`` mode=copy; the server
                re-verifies the source batch and computes a chunk plan of at most
                5000 rows), copy only chunks the server reports as missing
                (``received_indices`` may be sparse), finalize atomically (the
                server re-verifies the staging copy *and* the source batch), then
                re-read every stored value through the same fingerprint.
* ``--upload FILE`` send canonical lines (one per row, any order) in chunks of
                5000 bound by SHA-256 in the manifest; same finalize/read-back.

Safe to rerun after any interruption: the import key is stable, the server
refuses another manifest for the key, and published imports are immutable.
Progress is appended to ``--log`` as JSON lines.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import time
from decimal import Decimal
from pathlib import Path

INDICATORS = {
    13: "uka-forstahandssokande-yrkesprogram",
    31: "uka-nyborjare-yrkesprogram",
    97: "uka-antagna-yrkesprogram",
    108: "uka-examinerade",
    136: "uka-etablering",
    77: "uka-kvarvaro-hogskolenyborjare",
    134: "uka-kvarvaro-program",
    135: "uka-examensfrekvens",
}
POLICY = "csv-all-universities-partitions-every-root-v1"
CANONICALIZATION = ("jsonb-array(period,university,gender,dimensions,numeric-text-fixed); "
                    "bytewise order; newline separator without final newline")
CHUNK_ROWS = 5000
DEFAULT_BASIS = (
    "Användargodkänd publicering 2026-11-10: den aktiva batchen återanvänds inom databasen efter "
    "exakt matchning av samtliga per-periodfingeravtryck och täckningsantal mot ett oberoende, "
    "lokalt beräknat fryst CSV-manifest. Ingen källrevision eller full källtäckning är verifierad."
)


class ManifestMismatch(Exception):
    """Frozen manifest and server data (or the server-bound manifest) differ."""


# ---------- canonical form (mirror of uka_snapshot_line) ----------

def value_text(v) -> str | None:
    if v is None:
        return None
    d = Decimal(str(v))
    if not d.is_finite():
        raise ValueError(f"Ogiltigt värde {v!r}")
    t = format(d, "f")
    if "." in t:
        t = t.rstrip("0").rstrip(".")
    return "0" if t in ("-0", "") else t


def jsonb_text(v) -> str:
    """PostgreSQL jsonb::text rendering (object keys by byte length, then bytes)."""
    if isinstance(v, dict):
        keys = sorted(v, key=lambda k: (len(k.encode()), k.encode()))
        return "{" + ", ".join(json.dumps(k, ensure_ascii=False) + ": " + jsonb_text(v[k])
                               for k in keys) + "}"
    if isinstance(v, list):
        return "[" + ", ".join(jsonb_text(x) for x in v) + "]"
    return json.dumps(v, ensure_ascii=False)


def canonical_line(period: str, university: str, gender: str, dimensions: dict, value) -> str:
    return jsonb_text([period, university, gender, dimensions, value_text(value)])


def period_hashes(lines: list[str]) -> list[dict]:
    """Per-period fingerprints of canonical lines (period is element 0)."""
    by: dict[str, list[bytes]] = {}
    for line in lines:
        by.setdefault(json.loads(line)[0], []).append(line.encode("utf-8"))
    out = []
    for p in sorted(by, key=lambda s: s.encode()):
        rows = sorted(by[p])
        out.append({"period": p, "rows": len(rows),
                    "sha256": hashlib.sha256(b"\n".join(rows)).hexdigest()})
    return out


def upload_chunks(lines: list[str]) -> tuple[list[dict], list[str]]:
    ordered = sorted(lines, key=lambda s: s.encode("utf-8"))
    chunks, payloads = [], []
    for index, start in enumerate(range(0, len(ordered), CHUNK_ROWS)):
        part = ordered[start:start + CHUNK_ROWS]
        text = "\n".join(part)
        payloads.append(text)
        chunks.append({"index": index, "rows": len(part),
                       "sha256": hashlib.sha256(text.encode("utf-8")).hexdigest()})
    return chunks, payloads


# ---------- manifests ----------

def load_frozen(path: Path, api_id: int) -> tuple[dict, dict]:
    frozen = json.loads(path.read_text(encoding="utf-8"))
    if frozen.get("policy") != POLICY or frozen.get("canonicalization") != CANONICALIZATION:
        raise ManifestMismatch("Fryst manifest har annan policy eller kanonisering")
    hits = [e for e in frozen.get("indicators", []) if e.get("api_id") == api_id]
    if len(hits) != 1:
        raise ManifestMismatch(f"Fryst manifest saknar (eller dubblerar) API {api_id}")
    entry = hits[0]
    if INDICATORS.get(api_id) != entry.get("indicator"):
        raise ManifestMismatch("API-id och indikator hör inte ihop")
    if sum(p["rows"] for p in entry["periods"]) != entry["rows"]:
        raise ManifestMismatch("Periodernas radantal summerar inte till rows")
    for p in entry["periods"]:
        if sum(c["rows"] for c in entry["coverage"] if c["period"] == p["period"]) != p["rows"]:
            raise ManifestMismatch(f"Täckningen summerar inte för {p['period']}")
    return frozen, entry


def import_key(frozen: dict, api_id: int) -> str:
    return f"uka-{api_id}-snapshot-{frozen['snapshot']}-{frozen['archive_sha256'][:12]}"


def build_manifest(frozen: dict, entry: dict, *, mode: str, basis: str,
                   source_batch_id: str | None = None, chunks: list[dict] | None = None) -> dict:
    m = {
        "version": "1", "mode": mode, "policy": frozen["policy"], "snapshot": frozen["snapshot"],
        "archive_sha256": frozen["archive_sha256"], "canonicalization": frozen["canonicalization"],
        "api_id": entry["api_id"], "indicator": entry["indicator"], "rows": entry["rows"],
        "periods": sorted(entry["periods"], key=lambda p: p["period"].encode()),
        "coverage": sorted(entry["coverage"], key=lambda c: (c["period"].encode(), c["gender"].encode(),
                                                             c["age"].encode())),
        "source_release_verified": False, "full_source_coverage_verified": False,
        "publication_basis": basis,
    }
    if mode == "copy":
        m["source_batch_id"] = source_batch_id
    else:
        m["chunks"] = chunks
    return m


FROZEN_FIELDS = ("policy", "snapshot", "archive_sha256", "canonicalization", "api_id",
                 "indicator", "rows", "periods", "coverage")


def compare_bound(local: dict, server: dict) -> None:
    """The server-bound manifest must carry exactly the frozen content."""
    for f in FROZEN_FIELDS:
        a, b = local[f], server.get(f)
        if f in ("periods", "coverage"):
            key = (lambda x: json.dumps(x, sort_keys=True))
            a, b = sorted(map(key, a)), sorted(map(key, b or []))
        if a != b:
            raise ManifestMismatch(f"Servermanifestets fält {f} avviker från det frysta manifestet")
    for f in ("source_release_verified", "full_source_coverage_verified"):
        if server.get(f) is not False:
            raise ManifestMismatch(f"{f} måste vara false")


def compare_periods(expected: list[dict], actual: list[dict]) -> list[dict]:
    e = {p["period"]: p for p in expected}
    a = {p["period"]: p for p in actual}
    bad = []
    for p in sorted(set(e) | set(a)):
        x, y = e.get(p), a.get(p)
        if not x or not y or x["rows"] != y["rows"] or x["sha256"] != y["sha256"]:
            bad.append({"period": p, "expected_rows": x and x["rows"], "actual_rows": y and y["rows"],
                        "sha256_match": bool(x and y and x["sha256"] == y["sha256"])})
    return bad


def missing_chunks(status: dict, planned: int) -> list[int]:
    """Indices the server does not have yet. Received indices need not be contiguous."""
    received = status.get("received_indices") or []
    if any(not isinstance(i, int) or i < 0 or i >= planned for i in received):
        raise ValueError("Servern rapporterar chunkindex utanför planen")
    got = set(received)
    return [i for i in range(planned) if i not in got]


# ---------- server ----------

class Rpc:
    def __init__(self, url: str, key: str):
        import requests
        self.s = requests.Session()
        self.base = url.rstrip("/") + "/rest/v1/"
        self.s.headers.update({"apikey": key, "Content-Type": "application/json"})
        if not key.startswith("sb_"):
            self.s.headers["Authorization"] = f"Bearer {key}"

    def __call__(self, name: str, body: dict, timeout: int = 300, retries: int = 5):
        err = ""
        for attempt in range(retries):
            try:
                r = self.s.post(self.base + "rpc/" + name, json=body, timeout=timeout)
            except Exception as e:  # network hiccup: retry, every call is idempotent
                err = str(e)
            else:
                if r.status_code < 300:
                    return r.json()
                err = f"HTTP {r.status_code}: {r.text[:800]}"
                if r.status_code < 500 and r.status_code != 429:
                    break
            time.sleep(5 * (attempt + 1))
        raise RuntimeError(f"{name}: {err}")

    def get(self, table: str, params: dict) -> list[dict]:
        r = self.s.get(self.base + table, params=params, timeout=120)
        r.raise_for_status()
        return r.json()

    def active_batch(self, indicator: str) -> str:
        rows = self.get("uka_active_batches", {"indicator_id": f"eq.{indicator}", "select": "active_batch_id"})
        if len(rows) != 1:
            raise RuntimeError(f"Ingen aktiv batch för {indicator}")
        return rows[0]["active_batch_id"]

    def bound(self, key: str) -> dict | None:
        rows = self.get("uka_verified_imports", {"import_key": f"eq.{key}",
                                                 "select": "manifest,manifest_hash,batch_id,previous_batch_id,published_at"})
        return rows[0] if rows else None


def log(path: Path | None, event: dict) -> None:
    event = {"t": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), **event}
    line = json.dumps(event, ensure_ascii=False)
    print(line, flush=True)
    if path:
        with path.open("a", encoding="utf-8") as f:
            f.write(line + "\n")


def brief(chk: dict) -> dict:
    return {k: chk.get(k) for k in ("ok", "batch_id", "periods_checked", "rows_checked",
                                    "period_mismatches", "coverage_mismatches", "integrity")}


def resolve_manifest(rpc, frozen, entry, key, mode, basis, chunks=None) -> tuple[dict, dict | None]:
    """Return (manifest to bind, existing bound row). Reuses the stored manifest on resume."""
    existing = rpc.bound(key)
    if existing:
        compare_bound(build_manifest(frozen, entry, mode=mode, basis=basis,
                                     source_batch_id="x", chunks=chunks or []), existing["manifest"])
        if existing["manifest"].get("mode") != mode:
            raise ManifestMismatch("Importnyckeln är bunden till ett annat läge")
        if mode == "upload" and existing["manifest"].get("chunks") != chunks:
            raise ManifestMismatch("Chunkmanifestet avviker från det bundna")
        return existing["manifest"], existing
    src = rpc.active_batch(entry["indicator"]) if mode == "copy" else None
    return build_manifest(frozen, entry, mode=mode, basis=basis, source_batch_id=src, chunks=chunks), None


def run(rpc, frozen: dict, entry: dict, *, mode: str, key: str, basis: str, logp: Path | None,
        payloads: list[str] | None = None, chunks: list[dict] | None = None) -> dict:
    manifest, existing = resolve_manifest(rpc, frozen, entry, key, mode, basis, chunks)
    if not (existing and existing.get("published_at")) and mode == "copy":
        pre = rpc("uka_snapshot_verify_batch", {"p_batch_id": manifest["source_batch_id"], "p_manifest": manifest})
        log(logp, {"precheck_source": brief(pre)})
        if not pre.get("ok"):
            raise ManifestMismatch("Den aktiva batchen matchar inte det frysta manifestet; inget skrivet")
    started = rpc("uka_snapshot_start", {"p_import_key": key, "p_manifest": manifest})
    log(logp, {"start": {k: v for k, v in started.items() if k != "source_check"}})
    planned = int(started["planned_chunks"] if mode == "copy" else len(chunks))
    status = rpc("uka_snapshot_status", {"p_import_key": key})
    if not status.get("published_at"):
        todo = missing_chunks(status, planned)
        log(logp, {"received": status.get("received_indices"), "missing": todo})
        for i in todo:
            if mode == "copy":
                res = rpc("uka_snapshot_copy_chunk", {"p_import_key": key, "p_index": i}, timeout=240)
            else:
                res = rpc("uka_snapshot_chunk", {"p_import_key": key, "p_index": i, "p_payload": payloads[i]},
                          timeout=240)
            log(logp, {"chunk": i, "result": res})
        status = rpc("uka_snapshot_status", {"p_import_key": key})
        if missing_chunks(status, planned) or status.get("received_rows") != manifest["rows"]:
            raise RuntimeError("Ofullständig import efter kopiering/uppladdning")
        result = rpc("uka_snapshot_finalize", {"p_import_key": key}, timeout=1500, retries=1)
        log(logp, {"finalize": {"status": result.get("status"), "published_at": result.get("published_at"),
                                "staging_check": brief(result.get("staging_check") or {}),
                                "source_check": brief(result.get("source_check") or {}),
                                "aggregate_refresh": result.get("aggregate_refresh"),
                                "previous_batch_retained": result.get("previous_batch_retained")}})
        status = rpc("uka_snapshot_status", {"p_import_key": key})
    batch = status["batch_id"]
    active = rpc.active_batch(entry["indicator"])
    readback = rpc("uka_snapshot_period_hashes", {"p_batch_id": batch})
    bad = compare_periods(entry["periods"], readback)
    summary = {"import_key": key, "batch_id": batch, "active": active == batch,
               "previous_batch_retained": status.get("previous_batch_id"),
               "readback_periods": len(readback), "readback_rows": sum(p["rows"] for p in readback),
               "readback_mismatches": bad, "published_at": status.get("published_at")}
    log(logp, {"readback": summary})
    if bad or active != batch:
        raise ManifestMismatch("Återläsningen av publicerade värden matchar inte det frysta manifestet")
    return summary


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--frozen", required=True, type=Path)
    ap.add_argument("--api-id", required=True, type=int, choices=sorted(INDICATORS))
    ap.add_argument("--import-key", help="Standard: uka-<api>-snapshot-<snapshot>-<arkiv12>")
    ap.add_argument("--basis", default=DEFAULT_BASIS)
    ap.add_argument("--log", type=Path)
    g = ap.add_mutually_exclusive_group()
    g.add_argument("--copy", action="store_true")
    g.add_argument("--upload", type=Path, help="Fil med kanoniska rader, en per observation")
    a = ap.parse_args(argv)

    frozen, entry = load_frozen(a.frozen, a.api_id)
    key = a.import_key or import_key(frozen, a.api_id)
    rpc = Rpc(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_ROLE_KEY"])
    if a.upload:
        lines = [ln for ln in a.upload.read_text(encoding="utf-8").split("\n") if ln]
        bad = compare_periods(entry["periods"], period_hashes(lines))
        if bad:
            raise ManifestMismatch(f"Lokala rader matchar inte det frysta manifestet: {bad[:3]}")
        chunks, payloads = upload_chunks(lines)
        run(rpc, frozen, entry, mode="upload", key=key, basis=a.basis, logp=a.log,
            payloads=payloads, chunks=chunks)
        return 0
    if a.copy:
        run(rpc, frozen, entry, mode="copy", key=key, basis=a.basis, logp=a.log)
        return 0
    src = rpc.active_batch(entry["indicator"])
    m = build_manifest(frozen, entry, mode="copy", basis=a.basis, source_batch_id=src)
    chk = rpc("uka_snapshot_verify_batch", {"p_batch_id": src, "p_manifest": m})
    log(a.log, {"check": brief(chk), "import_key": key, "indicator": entry["indicator"]})
    return 0 if chk.get("ok") else 2


if __name__ == "__main__":
    sys.exit(main())
