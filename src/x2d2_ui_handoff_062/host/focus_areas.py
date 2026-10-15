"""Exact, opt-in area loader and reversible camera-service init configuration."""
RC='/system/etc/init/camera-service.rc'
STOCK_RC='2aa2c06efcc2d7fac690f7fe5db324e12f02748fb7d368ee5f726c3d5b24f2a9'
LIB='/system/lib64/libx2d_focus_area.so'
TARGETS=(LIB,'/system/etc/X2dFocusAreaController.qml')
ROOT='/blackbox/.x2d-play-software'
RECEIPT=ROOT+'/focus-areas-installed'
OWNED=(RECEIPT,)
PREVIOUS_SPECS = ({'format': 1, 'kind': 'experimental-afs-region-policy', 'serviceRc': '/system/etc/init/camera-service.rc', 'stockServiceRc': '2aa2c06efcc2d7fac690f7fe5db324e12f02748fb7d368ee5f726c3d5b24f2a9', 'library': '/system/lib64/libx2d_focus_area.so', 'librarySha256': '401074f8db4ebe82288a4a92d62085b206146784d2f3d0ef78f346dd52d6a743', 'token': 'acbf933fe7e8dc5b4bca8d164da7ee9a', 'scope': 'XCD-AF-S-face-off-uncropped-back-screen', 'heartbeatMs': 1000, 'nativeCoreFilesChanged': False, 'modes': ['spot-plus-one-retry', 'custom-rectangle-aggregate'], 'matrixAutoSelection': False},)
SPEC = {'format': 1, 'kind': 'experimental-afs-region-policy', 'serviceRc': '/system/etc/init/camera-service.rc', 'stockServiceRc': '2aa2c06efcc2d7fac690f7fe5db324e12f02748fb7d368ee5f726c3d5b24f2a9', 'library': '/system/lib64/libx2d_focus_area.so', 'librarySha256': 'b3cc4da6fcfa3640f20c9542bdccaf8e64fba6c87446dddb18693ca1ce7d72ce', 'token': 'acbf933fe7e8dc5b4bca8d164da7ee9a', 'scope': 'XCD-AF-S-face-off-uncropped-back-screen', 'heartbeatMs': 1000, 'nativeCoreFilesChanged': False, 'modes': ['spot-plus-one-retry', 'custom-rectangle-aggregate'], 'matrixAutoSelection': False}
def select(manifest,enabled=False):
    selected=dict(manifest)
    if enabled:
        if 'focus-point-menu' not in selected.get('selectedFeatures',[]):
            raise RuntimeError('扩展点/自定义需要同时安装二代样式对焦点菜单')
        if selected.get('focusAreas') not in (SPEC,)+PREVIOUS_SPECS:raise RuntimeError('对焦区域载荷不符合当前版本')
    else:
        selected.pop('focusAreas',None)
        selected['files']=[e for e in selected['files'] if e['target'] not in TARGETS]
        selected['uiLanguages']={lang:[e for e in rows if e['target'] not in TARGETS] for lang,rows in selected.get('uiLanguages',{}).items()}
    return selected
def validate(manifest):
    if manifest.get('focusAreas')!=SPEC:raise RuntimeError('对焦区域安装包校验失败')
    if not set(TARGETS)<={e['target'] for e in manifest['files']}:raise RuntimeError('对焦区域文件缺失')
    if not any(e['target']==LIB and e['sha256']==SPEC['librarySha256'] for e in manifest['files']):
        raise RuntimeError('对焦区域原生模块校验失败')
def init_service(raw,spec=None):
    import hashlib,re
    spec=SPEC if spec is None else spec
    if spec.get('stockServiceRc')!=STOCK_RC or spec.get('library')!=LIB or not re.fullmatch('[0-9a-f]{32}',spec.get('token','')):
        raise RuntimeError('对焦区域服务启动记录不匹配')
    if hashlib.sha256(raw).hexdigest()!=STOCK_RC:raise RuntimeError('相机服务启动配置不是已核验的原厂4.2.0版本')
    first=b'service camera-service /system/bin/camera-service\n'
    if raw.count(first)!=1:raise RuntimeError('相机服务启动入口不匹配')
    return raw.replace(first,first+('    setenv LD_PRELOAD '+LIB+'\n    setenv X2D_FOCUS_AREAS 1\n    setenv X2D_AREA_TOKEN '+spec['token']+'\n').encode(),1)
