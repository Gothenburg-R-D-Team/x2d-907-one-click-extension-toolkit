"""Static handoff validation. Does not import a camera backend or touch USB."""
from pathlib import Path
import ast,hashlib,json,re
R=Path(__file__).resolve().parents[1]; M=R/'src/x2d2_ui_handoff_062'; C=M/'camera'
checks=[]
def check(name,value):
 assert value,name
 checks.append(name)
index=json.loads((M/'asset-index.json').read_text(encoding='utf-8'))
sources=json.loads((M/'source-provenance.json').read_text(encoding='utf-8'))
for entry in sources:
 path=R/entry['path']; raw=path.read_bytes()
 check('hash '+entry['path'],hashlib.sha256(raw).hexdigest()==entry['exportSha256'])
 check('no binary '+entry['path'],not raw.startswith((b'\x7fELF',b'MZ')))
 text=raw.decode('utf-8')
 check('no personal path '+entry['path'],not re.search(r'[A-Za-z]:[\\/]+Users[\\/]',text))
 check('no active area token '+entry['path'],not re.search(r'property string token\s*:\s*"[0-9a-f]{32}"',text))
 if path.suffix=='.py':ast.parse(text,filename=str(path))
for suffix,label in (('','连接'),('.en','Connections'),('.zh-Hant','連線')):
 control=(C/('X2dConnectionMenu'+suffix+'.qml')).read_text(encoding='utf-8')
 boot=(C/('X2dNativeMenuBootstrap'+suffix+'.qml')).read_text(encoding='utf-8')
 check('language '+suffix,'property string connectionLabel: "'+label+'"' in control)
 check('stock route '+suffix,'wifiMenu' in control and 'RestoreBindingOrValue' in control)
 check('presentation only '+suffix,'Camera.' not in control and 'XMLHttpRequest' not in control)
 check('shared menu switch '+suffix,'active: root.attached && afcController.subjectMenuEnabled' in boot and 'X2dConnectionMenu {' in boot)
check('icon bytes',hashlib.sha256((C/'X2dConnectionMenuIcon.svg').read_bytes()).hexdigest()==index['connectionIcon']['sha256'])
for e in index['assets']:
 if e['publicSource']:check('asset indexed '+e['source'],(R/e['publicSource']).is_file())
for name in ('X2dNativeMenuModel.qml','X2dNativeMenuRoute.qml','X2dNativeMenuHost.qml','X2dAfcMenuController.qml','X2dSubjectDetectionController.qml','X2dSubjectDetectionPopup.qml','X2dSubjectPolicy.js','X2dFocusModePopup.qml'):
 check('dependency '+name,(C/name).is_file())
loader=(M/'loader-reference/native_menu_preload.c').read_text(encoding='utf-8')
check('loader reference has no host exit',not re.search(r'\b(?:_exit|exit|alarm|signal)\s*\(',loader))
check('constructor disclosed','__attribute__((constructor))' in loader and '/proc/self/mem' in loader)
host=(M/'host/x2d_play_software.py').read_text(encoding='utf-8')
check('restore retained','def restore(' in host and 'stockservicerc' in host and 'recognized_bundle' in host)
check('failure records retained','保留恢复记录' in host)
check('qualification honest',not index['deploymentQualified'] and not index['recoveryFailureQualificationComplete'])
print(json.dumps({'passed':len(checks),'cameraAccess':False,'hardwareValidated':False,'recoveryFailureQualified':False},ensure_ascii=False))
