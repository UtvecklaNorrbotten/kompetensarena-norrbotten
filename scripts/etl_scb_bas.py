#!/usr/bin/env python3
"""BAS: metadata-first monthly imports and resumable quarterly snapshots.

Uses SCB PxWeb API v2 and the existing authenticated ETL batch contract.
Only Python's standard library is required. No credentials in artifacts/logs.
"""
import argparse
from datetime import date, datetime
import hashlib
import itertools
import json
import math
import os
from pathlib import Path
import re
import time
import urllib.error
import urllib.parse
import urllib.request
from zoneinfo import ZoneInfo

SCB_API = "https://statistikdatabasen.scb.se/api/v2/tables"
CHUNK_ROWS = 5000
CHECK_FROM_DAY = 22
TARGETS = {
    "industry": {"table": "TAB3784", "indicator": "bas-sysselsatta-bransch",
                 "dimension": "SNI2007", "dimension_key": "sni2007",
                 "contents": {"0000054D": "arbetsstalle", "0000056A": "bostad"}},
    "sector": {"table": "TAB2597", "indicator": "bas-sysselsatta-sektor",
               "dimension": "ArbetsSektor", "dimension_key": "sektor",
               "contents": {"000005F4": "arbetsstalle", "000006OD": "bostad"}},
}
COUNTIES = "01 03 04 05 06 07 08 09 10 12 13 14 17 18 19 20 21 22 23 24 25".split()


def encode(value):
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"), allow_nan=False).encode()


def month_before(today, months):
    n = today.year * 12 + today.month - 1 - months
    return f"{n // 12:04d}M{n % 12 + 1:02d}"


def expected_period(today):
    # A new release normally contains reference month M-2. Before the
    # checking window, still pursue an overdue release from last month.
    return month_before(today, 2 if today.day >= CHECK_FROM_DAY else 3)


def should_check(today, state, manual=False):
    if manual or not state or not state.get("last_successful_at"):
        return True
    details = state.get("details") or {}
    return (state.get("last_status") in ("failed", "ready", "waiting")
            or bool(details.get("revision_pending"))
            or (state.get("latest_successful_period") or "") < expected_period(today))


def codes(dataset, variable):
    index = dataset["dimension"][variable]["category"]["index"]
    if isinstance(index, list):
        return index
    return sorted(index, key=index.get)


def selection(meta, target, sample=False):
    available = set(codes(meta, "Region"))
    # Verify the geographic levels, rather than using code length alone.
    if not {"00", *COUNTIES} <= available:
        raise ValueError("SCB saknar Riket eller något av de 21 länen")
    municipalities = sorted(x for x in available if re.fullmatch(r"\d{4}", x))
    if len(municipalities) != 290:
        raise ValueError("SCB:s kommunindelning har ändrats; kontrollera urvalet")
    regions = ["00", *COUNTIES, *municipalities]
    selected = {"Region": regions, "Kon": ["1", "2", "1+2"],
                target["dimension"]: codes(meta, target["dimension"]),
                "Fodelseregion": ["tot"], "ContentsCode": list(target["contents"])}
    if target["dimension"] == "ArbetsSektor":
        selected["Alder"] = ["15-74"]
    periods = codes(meta, "Tid")
    if any(not re.fullmatch(r"\d{4}M(0[1-9]|1[0-2])", x) for x in periods):
        raise ValueError("Ogiltig månadsdimension")
    periods = sorted(x for x in periods if x >= "2020M01")
    if not periods or periods[0] != "2020M01":
        raise ValueError("BAS-historik från 2020M01 saknas")
    first, last = periods[0], periods[-1]
    start = int(first[:4]) * 12 + int(first[-2:]) - 1
    end = int(last[:4]) * 12 + int(last[-2:]) - 1
    if len(periods) != end - start + 1:
        raise ValueError("BAS-månader saknas i metadata")
    for variable, values in selected.items():
        if not set(values) <= set(codes(meta, variable)):
            raise ValueError(f"SCB:s urval har ändrats: {variable}")
    if set(meta["id"]) != {*selected, "Tid"}:
        raise ValueError("SCB har ändrat tabellens dimensioner")
    if sample:
        selected["Region"] = ["00", "25", "2580"]
        periods = periods[-1:]
    return selected, periods


def normalize(dataset, selected, target, period, version):
    if dataset.get("updated") != version:
        raise ValueError("SCB-versionen ändrades under datahämtningen")
    expected = {**selected, "Tid": [period]}
    if set(dataset["id"]) != set(expected):
        raise ValueError("SCB-svaret har oväntade dimensioner")
    axis = []
    for variable in dataset["id"]:
        values = codes(dataset, variable)
        if len(values) != len(expected[variable]) or set(values) != set(expected[variable]):
            raise ValueError(f"SCB-svaret har fel urval: {variable}")
        axis.append(values)
    size = [len(x) for x in axis]
    if size != dataset["size"]:
        raise ValueError("SCB-svarets dimensioner och storlekar stämmer inte")
    count = math.prod(size)
    values = dataset["value"]
    if isinstance(values, list) and len(values) != count:
        raise ValueError("SCB-svaret är ofullständigt")
    if isinstance(values, dict) and any(not str(k).isdigit() or int(k) >= count for k in values):
        raise ValueError("Ogiltiga index i SCB:s glesa värdelista")
    status = dataset.get("status", {})
    if isinstance(status, list) and len(status) != count:
        raise ValueError("SCB:s statuslista har fel storlek")
    observations = []
    for i, row in enumerate(itertools.product(*axis)):
        fields = dict(zip(dataset["id"], row))
        value = values[i] if isinstance(values, list) else values.get(str(i))
        if value is not None and (isinstance(value, bool) or not isinstance(value, (int, float))
                                  or not math.isfinite(value) or value < 0):
            raise ValueError("Ogiltigt antal sysselsatta")
        labels = lambda variable: dataset["dimension"][variable]["category"]["label"][fields[variable]]
        dim = target["dimension"]
        prefix = target["dimension_key"]
        dimensions = {
            "contents_code": fields["ContentsCode"], "contents_label": labels("ContentsCode"),
            "geografiskt_perspektiv_code": target["contents"][fields["ContentsCode"]],
            "kon_code": fields["Kon"], "kon_label": labels("Kon"),
            "alder_code": "15-74", "alder_label": "15–74 år",
            "fodelseregion_code": "tot", "fodelseregion_label": "totalt",
            f"{prefix}_code": fields[dim], f"{prefix}_label": labels(dim),
            "statistik_status": "preliminar",
        }
        flag = status[i] if isinstance(status, list) else status.get(str(i))
        if flag:
            dimensions["scb_status"] = flag
        observations.append({"geo_code": fields["Region"], "period": period,
                             "value": value, "dimensions": dimensions})
    observations.sort(key=lambda x: (x["geo_code"], x["dimensions"][f"{target['dimension_key']}_code"],
                                    x["dimensions"]["kon_code"], x["dimensions"]["contents_code"]))
    return observations


class Client:
    def __init__(self):
        self.base = os.environ.get("ETL_BASE_URL", "").rstrip("/")
        self.key = os.environ.get("ETL_PUBLISH_KEY", "")

    def request(self, url, body=None, authenticated=False, retry_safe=True):
        if authenticated and (not self.base or not self.key):
            raise ValueError("ETL_BASE_URL och ETL_PUBLISH_KEY krävs")
        headers = {"Accept": "application/json", "User-Agent": "Kompetensarena-BAS/1.0"}
        if body is not None:
            headers["Content-Type"] = "application/json"
        if authenticated:
            headers["Authorization"] = f"Bearer {self.key}"
        for attempt in range(6 if retry_safe else 1):
            try:
                req = urllib.request.Request(url, data=None if body is None else encode(body), headers=headers)
                with urllib.request.urlopen(req, timeout=180) as response:
                    return json.load(response)
            except urllib.error.HTTPError as error:
                if not retry_safe or error.code not in (408, 429, 500, 502, 503, 504) or attempt == 5:
                    # Never print response bodies or request headers with credentials.
                    raise RuntimeError(f"HTTP {error.code}: anropet misslyckades") from None
                delay = min(60, 5 * 2 ** attempt)
                retry_after = error.headers.get("Retry-After", "")
                if retry_after.isdigit():
                    delay = min(60, int(retry_after))
                time.sleep(delay)
            except (urllib.error.URLError, TimeoutError):
                if not retry_safe or attempt == 5:
                    raise RuntimeError("Nätverksfel vid datahämtning") from None
                time.sleep(min(60, 5 * 2 ** attempt))

    def scb_metadata(self, table):
        meta = self.request(f"{SCB_API}/{table}/metadata?lang=sv")
        if not meta.get("updated"):
            raise ValueError("SCB saknar versionsdatum")
        datetime.fromisoformat(meta["updated"].replace("Z", "+00:00"))
        return meta

    def scb_data(self, table, selected, period):
        query = {"selection": [{"variableCode": k, "valueCodes": v}
                                for k, v in {**selected, "Tid": [period]}.items()]}
        return self.request(f"{SCB_API}/{table}/data?lang=sv&outputFormat=json-stat2", query)

    def etl(self, path, body=None, retry_safe=True):
        return self.request(self.base + "/api/public/jobs/" + path, body,
                            authenticated=True, retry_safe=retry_safe)


def assert_version(client, table, version):
    if client.scb_metadata(table)["updated"] != version:
        raise ValueError("SCB-versionen ändrades; börja om med aktuell version")


def publish(client, target, meta, selected, periods, full, budget_end):
    """Stream one month at a time; full snapshots resume by source version."""
    rows_per_period = math.prod(len(x) for x in selected.values())
    chunks_per_period = math.ceil(rows_per_period / CHUNK_ROWS)
    indicator = target["indicator"]
    version = meta["updated"]
    if full:
        spec = {"schema": "bas-v1", "indicator": indicator, "version": version,
                "selection": selected, "periods": periods, "chunk_rows": CHUNK_ROWS}
        import_key = hashlib.sha256(encode(spec)).hexdigest()
        resume = client.etl("etl-batch/resume-history?" + urllib.parse.urlencode(
            {"indicator_id": indicator, "import_key": import_key}))
        start = {"indicator_id": indicator, "source": "SCB",
                 "kalla_uppdaterad_datum": version[:10], "mode": "full", "import_key": import_key,
                 "expected_chunks": chunks_per_period * len(periods),
                 "expected_rows": rows_per_period * len(periods)}
        if start["expected_chunks"] > 10000:
            raise ValueError("BAS överskrider batchgränsen")
        if resume:
            if (resume["expected_chunks"] != start["expected_chunks"]
                    or resume["expected_rows"] != start["expected_rows"]):
                raise ValueError("Återstartens plan stämmer inte")
            client.etl("etl-batch/resume-history", {"batch_id": resume["id"]})
            batch_id, next_chunk = resume["id"], resume["next_chunk_index"]
        else:
            batch = client.etl("etl-batch/start", start, retry_safe=False)
            batch_id, next_chunk = batch["batch_id"], 0
    else:
        batch_id, next_chunk = None, 0
    try:
        for month_index, period in enumerate(periods):
            first_chunk = month_index * chunks_per_period if full else 0
            if full and first_chunk + chunks_per_period <= next_chunk:
                continue
            if time.monotonic() >= budget_end:
                raise TimeoutError("BAS tidsbudget slut; fortsätter nästa körning")
            assert_version(client, target["table"], version)
            data = client.scb_data(target["table"], selected, period)
            observations = normalize(data, selected, target, period, version)
            if not full:
                batch = client.etl("etl-batch/start", {
                    "indicator_id": indicator, "source": "SCB", "mode": "replace_period",
                    "replace_period": period, "kalla_uppdaterad_datum": version[:10],
                    "expected_rows": len(observations), "expected_chunks": chunks_per_period,
                }, retry_safe=False)
                batch_id = batch["batch_id"]
            for part in range(chunks_per_period):
                # Replay a partially stored month: existing chunk checksums
                # must match the data re-fetched from the same SCB version.
                chunk = observations[part * CHUNK_ROWS:(part + 1) * CHUNK_ROWS]
                client.etl("etl-batch/chunk", {"batch_id": batch_id, "indicator_id": indicator,
                                              "chunk_index": first_chunk + part, "observations": chunk})
            if not full:
                assert_version(client, target["table"], version)
                client.etl("etl-batch/finalize", {"batch_id": batch_id})
                batch_id = None
            print(f"{indicator}: {period}, {len(observations)} rader {'staged' if full else 'publicerade'}", flush=True)
        if full:
            assert_version(client, target["table"], version)
            client.etl("etl-batch/finalize", {"batch_id": batch_id})
            batch_id = None
    finally:
        if batch_id:
            try:
                client.etl("etl-batch/abort", {"batch_id": batch_id,
                    "reason": "BAS avbruten; full snapshot kan återupptas med samma importnyckel"})
            except Exception:
                print("Batch kunde inte avbrytas; opublicerad staging behålls", flush=True)


def run_target(client, name, mode, scheduled, today, budget_end, report):
    target = TARGETS[name]
    source_id = "scb-bas-" + name
    state = None
    details = {}
    try:
        if mode != "validate":
            state = client.etl("source-state?" + urllib.parse.urlencode({"source_id": source_id}))["state"]
            details = dict((state or {}).get("details") or {})
            if mode == "check" and not should_check(today, state, manual=not scheduled):
                report[name] = {"status": "outside_window_or_already_loaded"}
                return
        meta = client.scb_metadata(target["table"])
        selected, periods = selection(meta, target, sample=mode == "validate")
        latest = periods[-1]
        report[name] = {"table": target["table"], "updated": meta["updated"],
                        "latest_period": latest, "rows_per_period": math.prod(map(len, selected.values()))}
        if mode == "validate":
            data = client.scb_data(target["table"], selected, latest)
            observations = normalize(data, selected, target, latest, meta["updated"])
            report[name].update(status="validated", sample_rows=len(observations))
            return
        full = mode == "full" or not (state or {}).get("last_successful_at") or details.get("revision_pending", False)
        successful = (state or {}).get("latest_successful_period") or ""
        pending = periods if full else [p for p in periods if p > successful]
        details.update(table_id=target["table"], available_updated=meta["updated"],
                       expected_period=expected_period(today))
        if full:
            details["revision_pending"] = True
        if not pending:
            status = "waiting" if latest < expected_period(today) else "no_change"
            client.etl("source-state", {"source_id": source_id, "status": status,
                                       "latest_available_period": latest, "details": details}, retry_safe=False)
            report[name].update(status=status, periods_to_fetch=0)
            return
        client.etl("source-state", {"source_id": source_id, "status": "ready",
                                   "latest_available_period": latest, "details": details}, retry_safe=False)
        publish(client, target, meta, selected, pending, full, budget_end)
        details.update(published_updated=meta["updated"], revision_pending=False,
                       last_import_mode="full" if full else "incremental")
        if full:
            details["last_full_successful_at"] = datetime.now(ZoneInfo("Europe/Stockholm")).isoformat()
        client.etl("source-state", {"source_id": source_id, "status": "succeeded",
                                   "latest_available_period": latest, "latest_successful_period": latest,
                                   "details": details}, retry_safe=False)
        report[name].update(status="succeeded", periods_fetched=len(pending), full=full)
    except Exception as error:
        report.setdefault(name, {}).update(status="failed", error=str(error))
        if mode != "validate":
            try:
                client.etl("source-state", {"source_id": source_id, "status": "failed",
                                           "error_message": str(error)[:1000], "details": details}, retry_safe=False)
            except Exception:
                print("Källstatus kunde inte sparas; kontrollera BAS-registreringen och ETL-backend", flush=True)
        raise


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=("check", "full", "validate"), default="check")
    parser.add_argument("--scheduled", action="store_true")
    parser.add_argument("--target", choices=("all", *TARGETS), default="all")
    parser.add_argument("--report", default="artifacts/bas/report.json")
    args = parser.parse_args()
    today = datetime.now(ZoneInfo("Europe/Stockholm")).date()
    report = {"checked_at": datetime.now(ZoneInfo("Europe/Stockholm")).isoformat(), "mode": args.mode}
    failures = []
    budget_end = time.monotonic() + float(os.environ.get("BAS_RUN_BUDGET_SECONDS", "14400"))
    client = Client()
    try:
        for name in TARGETS if args.target == "all" else [args.target]:
            try:
                run_target(client, name, args.mode, args.scheduled, today, budget_end, report)
            except Exception as error:
                failures.append(name)
                print(f"BAS {name}: {error}", flush=True)
    finally:
        path = Path(args.report)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(encode(report))
        summary = os.environ.get("GITHUB_STEP_SUMMARY")
        if summary:
            with open(summary, "a", encoding="utf-8") as output:
                output.write("### BAS\n\n```json\n" + json.dumps(report, ensure_ascii=False, indent=2) + "\n```\n")
    if failures:
        raise SystemExit("BAS misslyckades: " + ", ".join(failures))


if __name__ == "__main__":
    main()
