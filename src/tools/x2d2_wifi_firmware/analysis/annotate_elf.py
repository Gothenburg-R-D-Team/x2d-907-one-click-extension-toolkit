"""Local static-analysis helper. Does not run vendor code or contact devices."""
import re
import subprocess
import sys
from pathlib import Path
from elftools.elf.elffile import ELFFile
from capstone import Cs, CS_ARCH_ARM64, CS_MODE_LITTLE_ENDIAN
from capstone.arm64 import ARM64_OP_IMM, ARM64_OP_REG, ARM64_OP_MEM

path = Path(sys.argv[1])
start, end = (int(x, 0) for x in sys.argv[2:4])
stream = path.open('rb')
elf = ELFFile(stream)
segments = [s for s in elf.iter_segments() if s['p_type'] == 'PT_LOAD']
def read(addr, size=160):
    for s in segments:
        delta = addr-s['p_vaddr']
        if 0 <= delta < s['p_filesz']:
            stream.seek(s['p_offset']+delta)
            return stream.read(min(size,s['p_filesz']-delta))
    return b''
symbols = {}
for line in subprocess.check_output([__import__('os').environ.get('LLVM_OBJDUMP', 'llvm-objdump'),'--demangle','--syms',str(path)],text=True).splitlines():
    m=re.match(r'([0-9a-f]+)\s+.*?\t[0-9a-f]+\s+(.*)',line)
    if m: symbols[int(m[1],16)]=m[2]
plt=elf.get_section_by_name('.plt')
rela=elf.get_section_by_name('.rela.plt')
if plt and rela:
    dyn=elf.get_section(rela['sh_link'])
    for i,r in enumerate(rela.iter_relocations()):
        symbols[plt['sh_addr']+32+i*16]=dyn.get_symbol(r['r_info_sym']).name
def describe(addr):
    if addr in symbols: return symbols[addr]
    for delta in (8,16):
        if addr-delta in symbols and 'Json::' in symbols[addr-delta]:
            return symbols[addr-delta]+f'+{delta}'
    b=read(addr)
    for enc in ('utf-16le','ascii'):
        try:
            s=b[:len(b)//2*2].decode(enc).split('\0')[0] if enc=='utf-16le' else b.split(b'\0')[0].decode(enc)
        except UnicodeError: continue
        if 3<=len(s)<=120 and all(32<=ord(c)<127 for c in s): return repr(s)
    return ''
md=Cs(CS_ARCH_ARM64,CS_MODE_LITTLE_ENDIAN);md.detail=True
regs={}
for ins in md.disasm(read(start,end-start),start):
    note=[];ops=ins.operands
    def key(op):return ins.reg_name(op.reg)
    if ins.mnemonic in ('adr','adrp') and len(ops)==2:
        regs[key(ops[0])]=ops[1].imm
    elif ins.mnemonic=='add' and len(ops)==3 and ops[2].type==ARM64_OP_IMM and key(ops[1]) in regs:
        value=regs[key(ops[1])]+ops[2].imm
        regs[key(ops[0])]=value
        desc=describe(value)
        if desc:note.append(f'0x{value:x} {desc}')
    elif ins.mnemonic=='mov' and len(ops)==2:
        if ops[1].type==ARM64_OP_REG and key(ops[1]) in regs:regs[key(ops[0])]=regs[key(ops[1])]
        elif ops[1].type==ARM64_OP_IMM:regs[key(ops[0])]=ops[1].imm
        else:regs.pop(key(ops[0]),None)
    elif ins.mnemonic=='ldr' and len(ops)==2 and ops[1].type==ARM64_OP_MEM:
        src=ins.reg_name(ops[1].mem.base)
        value=regs.get(src)
        if value is not None:
            addr=value+ops[1].mem.disp
            desc=describe(addr)
            if desc:note.append(f'0x{addr:x} {desc}')
            b=read(addr,8)
            if len(b)==8:regs[key(ops[0])]=int.from_bytes(b,'little')
            else:regs.pop(key(ops[0]),None)
        else:regs.pop(key(ops[0]),None)
    elif ins.mnemonic in ('bl','b') and ops and ops[0].type==ARM64_OP_IMM:
        desc=describe(ops[0].imm)
        if desc:note.append(desc)
        if ins.mnemonic=='bl':
            for r in range(19):regs.pop('x'+str(r),None);regs.pop('w'+str(r),None)
    print(f'{ins.address:08x}: {ins.mnemonic:8} {ins.op_str:40}'+(' ; '+', '.join(note) if note else ''))
