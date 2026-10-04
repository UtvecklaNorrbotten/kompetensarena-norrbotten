import json
import re
import sys
import urllib.parse
import urllib.request
from pathlib import Path

INDICATORS = {
    31: "Programnyborjare yrkesexamensprogram",
    33: "HST per studieform och amnesgrupp",
    99: "Soktryck yrkesexamensprogram",
    108: "Examinerade per lasar",
    136: "Andel etablerade",
}
BASE = "https://statistik-api.uka.se/api/totals/{id}/"
OUT = Path("uka_api_probe")
OUT.mkdir(exist_ok=True)

def get_json(url):
    req = urllib.request.Request(url, headers={
        "User-Agent": "Kompetensarena-Norrbotten-UKA-probe/1.0",
        "Accept": "application/json,text/plain,*/*",
    })
    with urllib.request.urlopen(req, timeout=60) as r:
        raw = r.read()
        ctype = r.headers.get("content-type", "")
        final_url = r.geturl()
    text = raw.decode("utf-8", errors="replace")
    return final_url, ctype, text, json.loads(text)

def walk(obj, path="$"):
    if isinstance(obj, dict):
        yield path, obj
        for k, v in obj.items():
            yield from walk(v, f"{path}.{k}")
    elif isinstance(obj, list):
        yield path, obj
        for i, v in enumerate(obj[:2000]):
            yield from walk(v, f"{path}[{i}]")

def scalar_values(obj):
    vals = []
    if isinstance(obj, dict):
        for v in obj.values():
            vals.extend(scalar_values(v))
    elif isinstance(obj, list):
        for v in obj[:10000]:
            vals.extend(scalar_values(v))
    elif isinstance(obj, (str, int, float)) or obj is None:
        vals.append(obj)
    return vals

def summarize(obj):
    top = {"type": type(obj).__name__}
    if isinstance(obj, dict):
        top["keys"] = list(obj.keys())
        top["key_types"] = {k: type(v).__name__ for k,v in obj.items()}
        top["key_lengths"] = {k: len(v) for k,v in obj.items() if isinstance(v,(list,dict))}
    elif isinstance(obj, list):
        top["length"] = len(obj)
        if obj and isinstance(obj[0], dict):
            top["first_keys"] = list(obj[0].keys())
    years = set()
    urls = set()
    possible_row_arrays = []
    for path, node in walk(obj):
        if isinstance(node, list):
            if node and all(isinstance(x, dict) for x in node[:min(20,len(node))]):
                possible_row_arrays.append((path, len(node), sorted(set().union(*(x.keys() for x in node[:20])))))
        elif isinstance(node, dict):
            for k,v in node.items():
                if isinstance(v, str):
                    if re.fullmatch(r"(19|20)\d{2}(?:[/\-](?:\d{2}|\d{4}))?", v.strip()):
                        years.add(v.strip())
                    if v.startswith("http"):
                        urls.add(v)
                elif isinstance(v, int) and 1900 <= v <= 2100:
                    years.add(str(v))
    top["years_detected"] = sorted(years)
    top["url_count"] = len(urls)
    top["sample_urls"] = sorted(urls)[:30]
    top["candidate_row_arrays"] = sorted(possible_row_arrays, key=lambda x: x[1], reverse=True)[:20]
    return top

all_summary = {}
failed = False
for iid, name in INDICATORS.items():
    url = BASE.format(id=iid)
    print(f"\n===== INDICATOR {iid}: {name} =====")
    print("GET", url)
    try:
        final_url, ctype, raw, data = get_json(url)
        (OUT / f"{iid}.json").write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
        summary = summarize(data)
        summary["http_content_type"] = ctype
        summary["final_url"] = final_url
        summary["raw_bytes"] = len(raw.encode("utf-8"))
        all_summary[str(iid)] = summary
        print(json.dumps(summary, ensure_ascii=False, indent=2))
        print("\nTOP SAMPLE:")
        if isinstance(data, dict):
            sample={k:(v[:3] if isinstance(v,list) else v) for k,v in list(data.items())[:20]}
        elif isinstance(data,list):
            sample=data[:3]
        else:
            sample=data
        print(json.dumps(sample, ensure_ascii=False, indent=2)[:15000])
    except Exception as e:
        failed = True
        all_summary[str(iid)]={"error":repr(e)}
        print("ERROR", repr(e), file=sys.stderr)

(OUT / "summary.json").write_text(json.dumps(all_summary, ensure_ascii=False, indent=2), encoding="utf-8")
print("\n===== COMBINED SUMMARY =====")
print(json.dumps(all_summary, ensure_ascii=False, indent=2))
if failed:
    sys.exit(2)
