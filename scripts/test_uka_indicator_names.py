import json, urllib.request
for iid in range(80, 111):
    try:
        req=urllib.request.Request(f"https://statistik-api.uka.se/api/totals/{iid}/",headers={"User-Agent":"Kompetensarena-UKA-probe/1.0","Accept":"application/json"})
        with urllib.request.urlopen(req,timeout=20) as r:
            d=json.load(r)
        ind=d.get("indicator",{})
        print(json.dumps({"id":iid,"name":ind.get("name"),"measurement":ind.get("measurement"),"current_year":ind.get("current_year")},ensure_ascii=False))
    except Exception as e:
        print(json.dumps({"id":iid,"error":type(e).__name__},ensure_ascii=False))
