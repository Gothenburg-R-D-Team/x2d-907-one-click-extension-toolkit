from loguru import logger
logger.remove()
from androguard.core.dex import DEX
from pathlib import Path
import sys
base=Path(__import__("os").environ["X2DII_ANALYSIS_WORKDIR"])
d=DEX((base/'analysis-methods-recovered.dex').read_bytes())
selected=set(sys.argv[1:])
out=[]
for c in d.get_classes():
 if c.get_name() not in selected:continue
 for m in c.get_methods():
  out.append(f'\n{c.get_name()}->{m.get_name()}{m.get_descriptor()}')
  code=m.get_code()
  if code is None:out.append('[no code]');continue
  off=0
  try:
   for i in code.get_bc().get_instructions():
    out.append(f'{off:04x} {i.get_name():25} {i.get_output()}');off+=i.get_length()
  except Exception as e:out.append(f'[parse error {e}]')
print('\n'.join(out))
