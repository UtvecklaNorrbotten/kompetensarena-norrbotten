import html, json, re, urllib.parse, urllib.request
from html.parser import HTMLParser

BASE="https://statistik-www.uka.se/export"
API="https://statistik-api.uka.se/api/totals/{}/"
IDS=[31,33,90,91,92,93,94,95,96,97,98,99,108,136]

def fetch(url, data=None):
    headers={"User-Agent":"Mozilla/5.0","Accept":"*/*"}
    if data is not None:
        data=urllib.parse.urlencode(data, doseq=True).encode()
        headers["Content-Type"]="application/x-www-form-urlencoded; charset=UTF-8"
        headers["X-Requested-With"]="XMLHttpRequest"
    req=urllib.request.Request(url,data=data,headers=headers)
    with urllib.request.urlopen(req,timeout=120) as r:
        return r.geturl(),r.headers, r.read()

def strip_tags(s):
    return re.sub(r"\s+"," ",re.sub(r"<[^>]+>"," ",html.unescape(s))).strip()

def values(txt):
    opts=[]
    for m in re.finditer(r'<option([^>]*)>(.*?)</option>',txt,re.I|re.S):
        attrs, label=m.groups()
        vm=re.search(r'value=["\']([^"\']*)',attrs,re.I)
        opts.append(("option", vm.group(1) if vm else "", strip_tags(label)))
    for m in re.finditer(r'<input([^>]*)>',txt,re.I|re.S):
        attrs=m.group(1)
        vm=re.search(r'value=["\']([^"\']*)',attrs,re.I)
        nm=re.search(r'(?:name|id)=["\']([^"\']*)',attrs,re.I)
        if vm: opts.append(("input",vm.group(1), nm.group(1) if nm else ""))
    return opts

for iid in IDS:
    print("\n===== ID",iid,"=====")
    try:
        _,_,raw=fetch(API.format(iid))
        d=json.loads(raw)
        print("INDICATOR",json.dumps(d.get("indicator",{}),ensure_ascii=False))
    except Exception as e:
        print("TOTALS_ERROR",repr(e)); continue
    ind=json.dumps([str(iid)],ensure_ascii=False,separators=(",",":"))
    for ep in ["academic_term.php?direction=from","academic_term.php?direction=to","university.php","gender.php","age.php","group.php"]:
        sep="&" if "?" in ep else "?"
        url=f"{BASE}/filters/{ep}{sep}indicator="+urllib.parse.quote(ind)
        try:
            _,_,b=fetch(url); txt=b.decode("utf-8","replace")
            vv=values(txt)
            print("FILTER",ep,"bytes",len(b),"values",len(vv))
            print(json.dumps(vv[:120],ensure_ascii=False))
        except Exception as e:
            print("FILTER_ERROR",ep,repr(e))
