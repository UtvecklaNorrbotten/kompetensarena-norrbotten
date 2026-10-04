import csv, io, json, re, urllib.parse, urllib.request
from pathlib import Path

BASE="https://statistik-www.uka.se/export"
INDICATORS=[31,33,97,99,108,136]
OUT=Path("uka_core_export_summary"); OUT.mkdir(exist_ok=True)

def req(url,data=None,timeout=300):
    headers={"User-Agent":"Kompetensarena-Norrbotten-UKA-probe/1.0","Accept":"*/*"}
    if data is not None:
        data=urllib.parse.urlencode(data,doseq=True).encode("utf-8")
        headers["Content-Type"]="application/x-www-form-urlencoded; charset=UTF-8"
        headers["X-Requested-With"]="XMLHttpRequest"
    return urllib.request.urlopen(urllib.request.Request(url,data=data,headers=headers),timeout=timeout)

def get_text(url,timeout=120):
    with req(url,timeout=timeout) as r:
        return r.read().decode("utf-8","replace")

def vals(txt,prefix):
    return [v for v in re.findall(r'value=["\']([^"\']+)["\']',txt,re.I) if v.startswith(prefix)]

def filter_html(iid,ep):
    ind=json.dumps([str(iid)],separators=(",",":"))
    sep="&" if "?" in ep else "?"
    return get_text(f"{BASE}/filters/{ep}{sep}indicator="+urllib.parse.quote(ind))

def dynamic_filters(group_html):
    marks=list(re.finditer(r'dynamic-filter-index["\']>\s*([^<]+)',group_html,re.I))
    out=[]; summary=[]
    for i,m in enumerate(marks):
        idx=m.group(1).strip()
        start=group_html.rfind('<div class="groupTitles',0,m.start())
        end=group_html.rfind('<div class="groupTitles',0,marks[i+1].start()) if i+1<len(marks) else len(group_html)
        if start < 0: start=m.start()
        if i+1<len(marks):
            next_start=group_html.rfind('<div class="groupTitles',0,marks[i+1].start())
            if next_start>start: end=next_start
        block=group_html[start:end]
        vv=vals(block,"dynamic:")
        out.extend([idx+v for v in vv])
        title=""
        tm=re.search(r'dynamic-filter-index["\']>\s*[^<]+</span>\s*([^<]+)',block,re.I)
        if tm: title=tm.group(1).strip()
        summary.append({"index":idx,"title":title,"count":len(vv),"sample":vv[:4]})
    return out,summary

# Find exact indicator id for the numerator to search pressure if exposed in export UI.
try:
    page=get_text(BASE+"/")
    matches=[]
    for m in re.finditer(r'<option[^>]*value=["\']([^"\']+)["\'][^>]*>(.*?)</option>',page,re.I|re.S):
        label=re.sub(r'\s+',' ',re.sub(r'<[^>]+>',' ',m.group(2))).strip()
        if "förstahandssökande" in label.lower() and "yrkes" in label.lower():
            matches.append({"value":m.group(1),"label":label})
    print("FIRST_CHOICE_INDICATOR_OPTIONS",json.dumps(matches,ensure_ascii=False))
except Exception as e:
    print("FIRST_CHOICE_DISCOVERY_ERROR",repr(e))

summaries=[]
for iid in INDICATORS:
    print(f"\n===== FULL EXPORT {iid} =====",flush=True)
    # metadata
    with req(f"https://statistik-api.uka.se/api/totals/{iid}/",timeout=60) as r:
        meta=json.load(r)["indicator"]

    fh=filter_html(iid,"academic_term.php?direction=from")
    th=filter_html(iid,"academic_term.php?direction=to")
    uh=filter_html(iid,"university.php")
    gh=filter_html(iid,"gender.php")
    ah=filter_html(iid,"age.php")
    dh=filter_html(iid,"group.php")

    froms=vals(fh,"from:"); tos=vals(th,"to:"); unis=vals(uh,"uni:")
    genders=vals(gh,"gender:"); ages=vals(ah,"age:")
    dyn,dyn_summary=dynamic_filters(dh)

    earliest=froms[-1]; latest_to=tos[0]
    filters=[earliest,latest_to]+unis+genders+ages+dyn
    print("META",json.dumps(meta,ensure_ascii=False),flush=True)
    print("PERIOD_ENDPOINTS",earliest,latest_to,"N_FROM",len(froms),"N_TO",len(tos),flush=True)
    print("FILTER_COUNTS",json.dumps({"universities":len(unis),"genders":len(genders),"ages":len(ages),"dynamic":len(dyn),"total_filters":len(filters)},ensure_ascii=False),flush=True)
    print("DYNAMIC_GROUPS",json.dumps(dyn_summary,ensure_ascii=False),flush=True)

    with req(f"{BASE}/api/index.php",{"indicator":str(iid),"filters[]":filters},timeout=300) as r:
        j=json.load(r)
    file_url=j["fileUrl"]
    print("FILE_URL",file_url,flush=True)

    # Stream CSV, count rows and distinct values without retaining the large file.
    with req(file_url,timeout=600) as r:
        tw=io.TextIOWrapper(r,encoding="utf-8-sig",errors="replace",newline="")
        reader=csv.reader(tw,delimiter=";")
        header=next(reader)
        row_count=0
        periods=set(); institutions=set()
        genders_seen=set(); ages_seen=set()
        for row in reader:
            row_count += 1
            if row:
                periods.add(row[0])
            if "Lärosäte" in header:
                institutions.add(row[header.index("Lärosäte")])
            if "Kön" in header:
                genders_seen.add(row[header.index("Kön")])
            if "Åldersgrupp" in header:
                ages_seen.add(row[header.index("Åldersgrupp")])
    summary={
        "id":iid,"name":meta.get("name"),"measurement":meta.get("measurement"),
        "current_year":meta.get("current_year"),
        "earliest_filter":earliest,"latest_filter":latest_to,
        "period_count":len(periods),"rows":row_count,
        "columns":header,"filter_universities":len(unis),
        "distinct_institution_cells":len(institutions),
        "distinct_nonblank_institutions":len([x for x in institutions if x.strip()]),
        "genders":sorted(genders_seen),"ages":sorted(ages_seen),
        "dynamic_groups":dyn_summary
    }
    summaries.append(summary)
    print("SUMMARY",json.dumps(summary,ensure_ascii=False),flush=True)

(OUT/"summary.json").write_text(json.dumps(summaries,ensure_ascii=False,indent=2),encoding="utf-8")
print("\n===== ALL SUMMARIES =====")
print(json.dumps(summaries,ensure_ascii=False,indent=2))
