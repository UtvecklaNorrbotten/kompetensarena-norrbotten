"""Public source diagnostic: no company identifiers or document names are logged."""
import io,json,zipfile,xml.etree.ElementTree as ET
from collections import Counter
from .source import archives,request,ROOT
from .ixbrl import parse,numeric,local,XBRLI
from .import_accounts import MEMBER
a=list(archives())[-1]
with request(ROOT+'/'+a['key']) as r: data=r.read(30000000)
examples=[]; units=Counter(); issues=Counter(); reports=0
with zipfile.ZipFile(io.BytesIO(data)) as outer:
 for member in outer.infolist():
  match=MEMBER.fullmatch(member.filename)
  if not match: continue
  with zipfile.ZipFile(io.BytesIO(outer.read(member))) as z:
   for f in z.infolist():
    if not f.filename.endswith(('.xhtml','.html')): continue
    xml=z.read(f)
    try: result=parse(xml,match[1],match[2])
    except (ValueError,ET.ParseError): continue
    reports+=1; issues.update(result['issues'])
    root=ET.fromstring(xml)
    contexts={c.get('id'):c for c in root.iter('{'+XBRLI+'}context')}
    unitmap={u.get('id'):[m.text for m in u.iter('{'+XBRLI+'}measure')] for u in root.iter('{'+XBRLI+'}unit')}
    rows=[]
    for fact in root.iter():
     concept=local(fact.get('name',''))
     c=contexts.get(fact.get('contextRef'))
     if c is None: continue
     end=c.findtext('.//{'+XBRLI+'}endDate') or c.findtext('.//{'+XBRLI+'}instant')
     start=c.findtext('.//{'+XBRLI+'}startDate')
     if end!=match[2] or (start and start!=result['period_start']): continue
     if concept=='MedelantaletAnstallda': units.update(['|'.join(unitmap.get(fact.get('unitRef'),[]))])
     if concept=='Nettoomsattning':
      try: value=numeric(fact)
      except ValueError: continue
      rows.append(dict(value=str(value),scale=fact.get('scale'),decimals=fact.get('decimals'),units=unitmap.get(fact.get('unitRef'))))
    if 'net_sales:conflicting_facts' in result['issues'] and len(examples)<12: examples.append(rows)
print(json.dumps(dict(reports=reports,issues=issues,employee_units=units,duplicate_examples=examples),ensure_ascii=False,indent=2))
