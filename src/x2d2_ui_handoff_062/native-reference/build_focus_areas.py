"""Build the system-path variant of the separately researched area prototype."""
from pathlib import Path
import hashlib,io,json,os,secrets,subprocess,sys,re
root=Path(__file__).resolve().parents[1];p=root/'native-package';research=root.parent/'focus-area-demo'
outer=Path(r'<LOCAL_USER_ROOT>\Desktop\x2d-907-extension-toolkit-Windows-x64-0.5.0-pixel-shift-test-3(1)\firmware-analysis')
sys.path.insert(0,str(outer/'audio-analysis-tools'))
from elftools.elf.elffile import ELFFile
source=(research/'area_service.c').read_text(encoding='utf-8')
source=source.replace('X2D_AREA_DEMO','X2D_FOCUS_AREAS').replace('/tmp/xdemo1/backend.ready','/tmp/x2d-focus-area/backend.ready')
source=source.replace('static u32 consumed_retry,expanded,inside_retry;','static u32 consumed_retry,expanded,inside_retry,area_owned;')
source=source.replace('current=r;applied_request=c.id;applied_mode=c.mode;','current=r;applied_request=c.id;applied_mode=c.mode;area_owned=1;')
source=source.replace('if(ch==0 && ready && has_origin && real_raw) {','if(ch==0 && ready && has_origin && real_raw && (((c.allow&1)&&c.mode)||area_owned)) {')
source=source.replace('(void)real_raw(ch,&r);','(void)real_raw(ch,&r);if(!(c.allow&1)||!c.mode)area_owned=0;',1)
# The marker is diagnostic only; the HTTP response is the runtime API receipt.
source=source.replace('static void *serve(void *unused)', 'struct wait_fd {int fd;short events,revents;}; extern int poll(struct wait_fd *,unsigned long,int);\nstatic void refresh_api(void){if(!real_run)real_run=(fn0)next("dji_af_run");if(!real_manager)real_manager=(fn0)next("af_roi_manager_run");if(!real_start)real_start=(fn0)next("hybrid_af_start");if(!real_result)real_result=(fn0)next("hybrid_af_get_result");if(!real_raw)real_raw=(fnroi)next("af_set_raw_roi");if(!real_hybrid)real_hybrid=(fnroi)next("hybrid_af_set_roi");ready=real_run&&real_manager&&real_start&&real_result&&real_raw&&real_hybrid;}\nstatic void *serve(void *unused)',1)
source=source.replace('static void *serve(void *unused)', 'extern int mkdir(const char *,unsigned),openat(int,const char *,int,...);\nstatic void *serve(void *unused)',1)
source=source.replace(' int marker=open(', ' (void)mkdir("/tmp/x2d-focus-area",0700);\n int marker=open(',1)
source=source.replace('int marker=open("/tmp/x2d-focus-area/backend.ready",1|64|512|0x8000,0600);',
    'int directory=open("/tmp/x2d-focus-area",0x4000|0x8000);\n int marker=directory>=0?openat(directory,"backend.ready",1|64|512|0x8000,0600):-1;\n if(directory>=0)close(directory);')
start=source.index(' ready=real_run&&real_manager&&real_start&&real_result&&real_raw&&real_hybrid;')
end=source.index('  struct timeval tv=',start)
source=source[:start]+''' unsigned last_ready=2;
 for(;;){refresh_api();
  if(last_ready!=ready){
   (void)mkdir("/tmp/x2d-focus-area",0700);
   int directory=open("/tmp/x2d-focus-area",0x4000|0x8000);
   int marker=directory>=0?openat(directory,"backend.ready",1|64|512|0x8000,0600):-1;
   if(directory>=0)close(directory);
   if(marker>=0){const char *value=ready?"READY\\n":"API_MISSING\\n";(void)write(marker,value,ready?6:12);close(marker);last_ready=ready;}
  }
  struct wait_fd pending={s,1,0};if(poll(&pending,1,250)<=0)continue;
  int fd=accept(s,0,0);if(fd<0)continue;
'''+source[end:]
file=root/'development/focus_area_service.c';file.write_bytes(source.encode())
zig=root.parent/'shutter-sound-research/compiler/zig-windows-x86_64-0.13.0/zig.exe'
env=dict(os.environ,ZIG_LOCAL_CACHE_DIR=str(root.parent/'shutter-sound-research/zig-local'),ZIG_GLOBAL_CACHE_DIR=str(root.parent/'shutter-sound-research/zig-global'))
target=p/'libx2d_focus_area.so'
libs=[outer/'x2d-4.2.0/system-root/lib64'/name for name in ('libc.so','libdl.so')]
subprocess.run([str(zig),'cc','-target','aarch64-linux-gnu','-O2','-std=c11','-fPIC','-shared','-nostdlib',
    '-fno-stack-protector','-fno-builtin','-mno-outline-atomics','-Wl,--no-undefined','-Wl,-z,noexecstack',
    '-Wl,-soname,libx2d_focus_area.so',str(file),*[str(x) for x in libs],'-o',str(target)],env=env,check=True)
sha=lambda data:hashlib.sha256(data).hexdigest()
elf=ELFFile(io.BytesIO(target.read_bytes()));assert elf['e_machine']=='EM_AARCH64'
assert not any((s['p_flags']&3)==3 for s in elf.iter_segments())
exports={s.name for s in elf.get_section_by_name('.dynsym').iter_symbols() if s['st_shndx']!='SHN_UNDEF'}
needed={'dji_af_run','af_roi_manager_run','hybrid_af_start','hybrid_af_get_result','af_set_raw_roi','hybrid_af_set_roi'}
provider=outer/'x2d-4.2.0/system-root/lib64/libaaa.so'
data=provider.read_bytes();assert sha(data)=='feef8a8dc3a27395e47232c2b25a5da7a7ab335922fbb527e637c439e35bcec7'
provider_elf=ELFFile(io.BytesIO(data));symbols={s.name for s in provider_elf.get_section_by_name('.dynsym').iter_symbols() if s['st_shndx']!='SHN_UNDEF'}
assert needed<=symbols,needed-symbols
assert needed-{'hybrid_af_get_result'}<=exports
token_file=root/'development/focus-area-token.txt'
if not token_file.exists():token_file.write_text(secrets.token_hex(16),encoding='ascii')
token=token_file.read_text().strip()
spec=dict(format=1,kind='experimental-afs-region-policy',serviceRc='/system/etc/init/camera-service.rc',
    stockServiceRc='2aa2c06efcc2d7fac690f7fe5db324e12f02748fb7d368ee5f726c3d5b24f2a9',
    library='/system/lib64/libx2d_focus_area.so',librarySha256=sha(target.read_bytes()),token=token,
    scope='XCD-AF-S-face-off-uncropped-back-screen',heartbeatMs=1000,nativeCoreFilesChanged=False,
    modes=['spot-plus-one-retry','custom-rectangle-aggregate'],matrixAutoSelection=False)
module=root/'focus_areas.py';text=re.sub(r'^SPEC(?:=None.*| = .*)$', 'SPEC = '+repr(spec),module.read_text(encoding='utf-8'),flags=re.M)
module.write_bytes(text.encode())
report={'architecture':'AArch64','providerSymbolsVerified':sorted(needed),'moduleSha256':spec['librarySha256'],
    'sourceSha256':sha(file.read_bytes()),'writableExecutableSegments':False,'cameraAccess':False,'hardwareROIValidated':False}
(root/'development/validation-062-area-build.json').write_bytes((json.dumps(report,indent=2)+'\n').encode())
print(json.dumps(report))
