from loguru import logger
logger.remove()
from androguard.core.dex import DEX
from pathlib import Path
import re,json
base=Path(__import__("os").environ["X2DII_ANALYSIS_WORKDIR"]);d=DEX((base/'analysis-methods-recovered.dex').read_bytes());hits=[]
for c in d.get_classes():
 for m in c.get_methods():
  code=m.get_code()
  if not code:continue
  try:
   for ins in code.get_bc().get_instructions():
    n=ins.get_name()
    if n in ['iput','iput-object']:
     s=ins.get_output()
     if any(k in s for k in ['Lx6/H;->i I','Lx6/H;->j [B']):hits.append([c.get_name(),m.get_name(),m.get_descriptor(),s])
  except Exception:pass
print('client-id setters',hits)
for s in d.get_strings():
 if re.search(r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',s):print(s[:180])
(base/'app-field-xrefs.json').write_text(json.dumps(hits,indent=2))
