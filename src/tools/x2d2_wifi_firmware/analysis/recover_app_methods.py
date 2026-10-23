"""Recover analysis-only method bytes using the package's DGC2 relocation records."""
from pathlib import Path
import struct,hashlib,zlib,json
base=Path(__import__("os").environ["X2DII_ANALYSIS_WORKDIR"])
b=bytearray((base/'analysis-rebuilt.dex').read_bytes())
blob=0xa1f520
h=struct.unpack_from('>6I',b,blob)
assert h[1]==0xabbacddc and h[2]==24
n=(h[4]-h[2])//24
records=[]
for i in range(n):
 data_off,size,integrity,flag,patchoff,pad=struct.unpack_from('>6I',b,blob+h[2]+24*i)
 assert flag==0 and size<=pad
 pos=patchoff;old=0;shift=0
 for k in range(5):
  v=b[pos];pos+=1;old|=(v&127)<<shift;shift+=7
  if not v&128:break
 else:raise ValueError('invalid code offset')
 assert 0x23fe90<=old<0x8c7658
 new=blob+h[4]+data_off
 assert new+size<=len(b)
 # Original method register/input counts and instruction allocation match.
 assert b[old:old+4]==b[new:new+4]
 assert b[old+12:old+16]==b[new+12:new+16]
 assert old+pad<=0x8c7658
 records.append((old,new,size,pad))
assert len(set(o for o,_,_,_ in records))==n
s=sorted(records)
for (old,new,size,pad),(nextold,_,_,_) in zip(s,s[1:]):assert old+pad<=nextold
for old,new,size,pad in records:b[old:old+size]=b[new:new+size]
b[12:32]=hashlib.sha1(b[32:]).digest();struct.pack_into('<I',b,8,zlib.adler32(b[12:])&0xffffffff)
path=base/'analysis-methods-recovered.dex';path.write_bytes(b)
report={'recovered_method_count':n,'source_blob':'classes.dex.dgc2','relocation_record_size':24,'blob_offset':hex(blob),'output_sha256':hashlib.sha256(b).hexdigest(),'note':'Static analysis copy only; native App protection still exists and this is not a runnable app.'}
(base/'method-reconstruction.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
