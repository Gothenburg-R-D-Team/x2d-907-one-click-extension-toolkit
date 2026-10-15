"""Offline AArch64 build with exact first-generation stock library inputs."""
from pathlib import Path
import hashlib, io, json, os, subprocess, sys
root=Path(__file__).resolve().parents[1]
outer=Path(r'<LOCAL_USER_ROOT>\Desktop\x2d-907-extension-toolkit-Windows-x64-0.5.0-pixel-shift-test-3(1)')
sys.path.insert(0,str(outer/'firmware-analysis/audio-analysis-tools'))
from elftools.elf.elffile import ELFFile
research=root.parent/'shutter-sound-research'
zig=research/'compiler/zig-windows-x86_64-0.13.0/zig.exe'
inputs=[(outer/'firmware-analysis/x2d-4.2.0/system-root/lib64/libc.so','40e9ea6efccfe8757b4afac57972c9a5cce745224d2dcf34ecddf3dfc0a3f7a6'),
        (outer/'firmware-analysis/shutter-audio-study/x2d-4.2.0/lib64/libaudioclient.so','1a196a3f3c9095042999c429aaf38bcfa2e800f12d4121a6f465cbc4ca18000c')]
sha=lambda data:hashlib.sha256(data).hexdigest()
assert sha((research/'zig-0.13.0.zip').read_bytes())=='d859994725ef9402381e557c60bb57497215682e355204d754ee3df75ee3c158'
exports=set()
for path,digest in inputs:
    data=path.read_bytes();assert sha(data)==digest
    elf=ELFFile(io.BytesIO(data))
    exports.update(s.name for s in elf.get_section_by_name('.dynsym').iter_symbols() if s['st_shndx']!='SHN_UNDEF')
target=root/'native-package/libx2d_shutter_audio.so'
env=dict(os.environ,ZIG_LOCAL_CACHE_DIR=str(research/'zig-local'),ZIG_GLOBAL_CACHE_DIR=str(research/'zig-global'))
subprocess.run([str(zig),'cc','-target','aarch64-linux-gnu','-O2','-g0','-fPIC','-shared','-nostdlib',
               '-fno-stack-protector','-fno-builtin','-Wl,--strip-all','-Wl,--no-undefined','-Wl,-z,noexecstack',
               '-Wl,-soname,libx2d_shutter_audio.so',str(root/'development/shutter_audio_factory.c'),
               *[str(p) for p,_ in inputs],'-o',str(target)],env=env,check=True)
elf=ELFFile(io.BytesIO(target.read_bytes()))
imports={s.name for s in elf.get_section_by_name('.dynsym').iter_symbols() if s.name and s['st_shndx']=='SHN_UNDEF'}
assert imports<=exports,imports-exports
assert elf['e_machine']=='EM_AARCH64'
assert not any((s['p_flags']&3)==3 for s in elf.iter_segments())
needed=[t.needed for t in elf.get_section_by_name('.dynamic').iter_tags() if t.entry.d_tag=='DT_NEEDED']
assert set(needed)=={'libc.so','libaudioclient.so'},needed
assert not any('set_dev_volume' in s or s.startswith('pcm_') or s in ('socket','bind','listen') for s in imports)
report={'sha256':sha(target.read_bytes()),'machine':'AArch64','compiler':'Zig 0.13.0',
        'sourceSha256':sha((root/'development/shutter_audio_factory.c').read_bytes()),
        'inputs':[{'name':p.name,'sha256':d} for p,d in inputs],
        'imports':sorted(imports),'neededLibraries':needed,'writableExecutableSegments':False,
        'globalVolumeSetters':False,'cameraAccess':False,'physicalSpeakerPlaybackVerified':False}
(root/'development/validation-060-r1-audio-build.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
print(json.dumps(report))
