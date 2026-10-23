from loguru import logger
logger.remove()
from androguard.core.dex import DEX
from pathlib import Path
import json
base=Path(__import__("os").environ["X2DII_ANALYSIS_WORKDIR"]);d=DEX((base/'analysis-methods-recovered.dex').read_bytes())
rows=[];hits=[];guarded=0;plain=0
need=['X-Phocus-Client-Id','X-Phocus-Upload-Info','whitelist','Whitelist','WlTcp','startConnectAndAuth','HELLO','AuthInfo','authInfo','clientId','ClientId']
for c in d.get_classes():
 idx=c.get_source_file_idx()
 src=d.get_cm_string(idx) if idx!=0xffffffff else ''
 if any(x in str(src).lower() for x in ['ble','wl','wifi','tcp','auth','upgrade','terminal','protocol','packet']):rows.append([c.get_name(),str(src)])
 for m in c.get_methods():
  code=m.get_code()
  if code is None:continue
  bc=code.get_bc().get_raw()
  if bc[:8]==b'\0\0\x14\0\0\0\0\0':guarded+=1;continue
  plain+=1
  try:
   for i in code.get_bc().get_instructions():
    if i.get_name().startswith('const-string'):
     out=i.get_output()
     if any(x in out for x in need):hits.append([c.get_name(),m.get_name(),m.get_descriptor(),out])
  except Exception:pass
report={'classes_with_relevant_source':rows,'literal_hits':hits,'placeholder_methods':guarded,'other_methods':plain}
(base/'app-index.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
print('guarded',guarded,'others',plain)
for r in rows[:100]:print(*r)
print('hits',len(hits))
for r in hits[:70]:print(*r)
