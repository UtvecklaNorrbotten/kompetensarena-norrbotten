import json, re, urllib.request, urllib.parse

URL="https://statistik-www.uka.se/export/?indicator=33"
req=urllib.request.Request(URL,headers={"User-Agent":"Mozilla/5.0"})
html=urllib.request.urlopen(req,timeout=60).read().decode("utf-8","replace")
print("HTML_BYTES",len(html))
scripts=re.findall(r'<script[^>]+src=["\\\']([^"\\\']+)',html,re.I)
print("SCRIPTS",json.dumps(scripts,ensure_ascii=False))
for src in scripts:
    full=urllib.parse.urljoin(URL,src)
    try:
        txt=urllib.request.urlopen(urllib.request.Request(full,headers={"User-Agent":"Mozilla/5.0"}),timeout=60).read().decode("utf-8","replace")
    except Exception as e:
        print("SCRIPT_ERROR",full,repr(e)); continue
    hits=[]
    for line in txt.splitlines():
        if re.search(r'(csv|export|download|ajax|fetch|api/)',line,re.I):
            hits.append(line[:1200])
    if hits:
        print("\n### SCRIPT",full,"BYTES",len(txt))
        for x in hits[:200]: print(x)

for pat in [r'<form[^>]*action=["\\\']([^"\\\']*)',r'url\s*[:=]\s*["\\\']([^"\\\']+)',r'https?://[^"\\\' ]+']:
    vals=re.findall(pat,html,re.I)
    if vals:
        print("HTML_PATTERN",pat,json.dumps(vals[:100],ensure_ascii=False))
