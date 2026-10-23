"""Rebuild an analysis-only DEX header and string IDs from clear map/string data.
Does not run the app, remove camera authentication, or change a firmware file.
"""
from pathlib import Path
import hashlib,struct,zlib,json
base=Path(__import__("os").environ["X2DII_ANALYSIS_WORKDIR"])
source=(base/'classes.dex').read_bytes()
container=source[23180:-8]
dex=bytearray(container[0x1000:])
map_off=0x15fd70
n=struct.unpack_from('<I',dex,map_off)[0]
items={}
for i in range(n):
 typ,unused,size,off=struct.unpack_from('<HHII',dex,map_off+4+12*i)
 items[typ]=(size,off)
assert n==18 and items[1]==(47751,112)
count,ids_off=items[1]
strcount,pos=items[0x2002]
assert count==strcount
starts=[]
for i in range(count):
 starts.append(pos)
 for j in range(5):
  v=dex[pos];pos+=1
  if not v&0x80:break
 else:raise ValueError('bad string length')
 end=dex.index(0,pos)
 pos=end+1
# All original pointers outside the protected prefix must agree exactly.
agree=0
for i,p in enumerate(starts):
 off=ids_off+4*i
 if off>=0x20000:
  old=struct.unpack_from('<I',dex,off)[0]
  if old!=p:raise ValueError(f'clear pointer mismatch at string {i}: {old:x}!={p:x}')
  agree+=1
 struct.pack_into('<I',dex,off,p)
header=bytearray(112);header[:8]=b'dex\n039\0'
values=[len(dex),112,0x12345678,0,0,map_off]
for typ in range(1,7):values.extend(items[typ])
values.extend([len(dex)-map_off,map_off])
struct.pack_into('<20I',header,32,*values)
dex[:112]=header
dex[12:32]=hashlib.sha1(dex[32:]).digest()
struct.pack_into('<I',dex,8,zlib.adler32(dex[12:])&0xffffffff)
path=base/'analysis-rebuilt.dex';path.write_bytes(dex)
report={'source_sha256':hashlib.sha256(source).hexdigest(),'original_container_offset':23180,'table_shift_removed':4096,'clear_string_pointers_matched':agree,'string_count':count,'size':len(dex),'rebuilt_sha256':hashlib.sha256(dex).hexdigest(),'note':'Analysis reconstruction, not a runnable or signed App; code items may remain protected.'}
(base/'dex-reconstruction.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
