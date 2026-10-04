import csv, io, json, os, re, urllib.parse, urllib.request
iid=int(os.environ["UKA_INDICATOR"])
BASE="https://statistik-www.uka.se/export"

def req(url,data=None,timeout=300):
    headers={"User-Agent":"Kompetensarena-Norrbotten-UKA-probe/1.0","Accept":"*/*"}
    if data is not None:
        data=urllib.parse.urlencode(data,doseq=True).encode()
        headers["Content-Type"]="application/x-www-form-urlencoded; charset=UTF-8"
        headers["X-Requested-With"]="XMLHttpRequest"
    return urllib.request.urlopen(urllib.request.Request(url,data=data,headers=headers),timeout=timeout)

def text(url):
    with req(url,timeout=90) as r: return r.read().decode("utf-8","replace")

def vals(s,p):
    return [v for v in re.findall(r'value=["\']([^"\']+)["\']',s,re.I) if v.startswith(p)]

ind=json.dumps([str(iid)],separators=(",",":"))
def filt(ep):
    sep="&" if "?" in ep else "?"
    return text(f"{BASE}/filters/{ep}{sep}indicator="+urllib.parse.quote(ind))

froms=vals(filt("academic_term.php?direction=from"),"from:")
tos=vals(filt("academic_term.php?direction=to"),"to:")
unis=vals(filt("university.php"),"uni:")
genders=vals(filt("gender.php"),"gender:")
ages=vals(filt("age.php"),"age:")
gh=filt("group.php")
marks=list(re.finditer(r'dynamic-filter-index["\']>\s*([^<]+)',gh,re.I))
dyn=[]; dyninfo=[]
for i,m in enumerate(marks):
    idx=m.group(1).strip()
    st=gh.rfind('<div class="groupTitles',0,m.start())
    if i+1<len(marks):
        en=gh.rfind('<div class="groupTitles',0,marks[i+1].start())
    else: en=len(gh)
    block=gh[max(0,st):en]
    vv=vals(block,"dynamic:")
    dyn += [idx+v for v in vv]
    title=""
    tm=re.search(r'dynamic-filter-index["\']>\s*[^<]+</span>\s*([^<]+)',block,re.I)
    if tm:title=tm.group(1).strip()
    dyninfo.append({"index":idx,"title":title,"count":len(vv)})

latest_from=froms[0]; latest_to=tos[0]
filters=[latest_from,latest_to]+unis+genders+ages+dyn
with req(f"{BASE}/api/index.php",{"indicator":str(iid),"filters[]":filters},timeout=300) as r:
    j=json.load(r)
with req(j["fileUrl"],timeout=600) as r:
    reader=csv.reader(io.TextIOWrapper(r,encoding="utf-8-sig",errors="replace",newline=""),delimiter=";")
    header=next(reader); n=0; periods=set(); institutions=set()
    li=header.index("Lärosäte") if "Lärosäte" in header else None
    for row in reader:
        n+=1
        if row: periods.add(row[0])
        if li is not None: institutions.add(row[li])

with req(f"https://statistik-api.uka.se/api/totals/{iid}/",timeout=60) as r:
    meta=json.load(r)["indicator"]
print(json.dumps({
    "id":iid,"name":meta.get("name"),"measurement":meta.get("measurement"),
    "current_year":meta.get("current_year"),"latest_from":latest_from,"latest_to":latest_to,
    "available_periods":len(froms),"earliest":froms[-1] if froms else None,
    "university_filter_ids":len(unis),"latest_rows_all_sweden":n,
    "latest_distinct_nonblank_institutions":len([x for x in institutions if x.strip()]),
    "columns":header,"gender_filters":len(genders),"age_filters":len(ages),
    "dynamic_groups":dyninfo
},ensure_ascii=False))
