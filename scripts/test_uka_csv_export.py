import csv, html, json, re, urllib.parse, urllib.request
from pathlib import Path

BASE="https://statistik-www.uka.se/export"
INDICATOR="33"
OUT=Path("uka_export_test"); OUT.mkdir(exist_ok=True)

def req(url,data=None):
    headers={"User-Agent":"Mozilla/5.0","Accept":"*/*"}
    if data is not None:
        data=urllib.parse.urlencode(data, doseq=True).encode("utf-8")
        headers["Content-Type"]="application/x-www-form-urlencoded; charset=UTF-8"
        headers["X-Requested-With"]="XMLHttpRequest"
    with urllib.request.urlopen(urllib.request.Request(url,data=data,headers=headers),timeout=180) as r:
        return r.geturl(),dict(r.headers),r.read()

ind=json.dumps([INDICATOR],separators=(",",":"))

def get_filter(ep):
    sep="&" if "?" in ep else "?"
    return req(f"{BASE}/filters/{ep}{sep}indicator="+urllib.parse.quote(ind))[2].decode("utf-8","replace")

def input_values(txt,prefix):
    return [v for v in re.findall(r'value=["\\\']([^"\\\']+)["\\\']',txt,re.I) if v.startswith(prefix)]

from_html=get_filter("academic_term.php?direction=from")
to_html=get_filter("academic_term.php?direction=to")
gender_html=get_filter("gender.php")
age_html=get_filter("age.php")
group_html=get_filter("group.php")

froms=input_values(from_html,"from:")
tos=input_values(to_html,"to:")
latest=froms[0]
assert latest.replace("from:","to:",1) in tos

filters=[latest, latest.replace("from:","to:",1), "uni:1"]
filters += input_values(gender_html,"gender:")
filters += input_values(age_html,"age:")

p1=group_html.find("groupTitles Studieform")
p2=group_html.find("groupTitles Ämnesområde")
assert p1 >= 0 and p2 > p1, (p1,p2,len(group_html))
study_block=group_html[p1:p2]
subject_block=group_html[p2:]
study_vals=input_values(study_block,"dynamic:")
subject_vals=input_values(subject_block,"dynamic:")
dyn_summary=[
    {"index":"6.","n":len(study_vals),"sample":study_vals[:5]},
    {"index":"7.","n":len(subject_vals),"sample":subject_vals[:5]},
]
filters += ["6."+v for v in study_vals]
filters += ["7."+v for v in subject_vals]

print("LATEST",latest)
print("FILTERS",len(filters))
print("DYNAMIC",json.dumps(dyn_summary,ensure_ascii=False))

url,headers,raw=req(f"{BASE}/api/index.php",{"indicator":INDICATOR,"filters":filters})
print("POST_RESPONSE",raw.decode("utf-8","replace")[:4000])
j=json.loads(raw)
file_url=j["fileUrl"]
final_url,h,csvraw=req(file_url)
(OUT/"indicator33_latest_riket.csv").write_bytes(csvraw)
text=csvraw.decode("utf-8-sig","replace")
rows=list(csv.reader(text.splitlines(),delimiter=";"))
print("CSV_URL",final_url)
print("CSV_BYTES",len(csvraw))
print("CSV_ROWS_INCL_HEADER",len(rows))
print("CSV_COLUMNS",json.dumps(rows[0] if rows else [],ensure_ascii=False))
print("CSV_FIRST_ROWS",json.dumps(rows[1:6],ensure_ascii=False))
