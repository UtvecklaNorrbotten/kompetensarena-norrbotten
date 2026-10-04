import json,re,urllib.parse,urllib.request,html
BASE="https://statistik-www.uka.se/export"
iid=33
ind=json.dumps([str(iid)],separators=(",",":"))
for ep in ["academic_term.php?direction=from","academic_term.php?direction=to","university.php","gender.php","age.php","group.php"]:
    sep="&" if "?" in ep else "?"
    url=f"{BASE}/filters/{ep}{sep}indicator="+urllib.parse.quote(ind)
    req=urllib.request.Request(url,headers={"User-Agent":"Mozilla/5.0"})
    txt=urllib.request.urlopen(req,timeout=30).read().decode("utf-8","replace")
    print("\n###",ep,"###")
    print(txt[:30000])
