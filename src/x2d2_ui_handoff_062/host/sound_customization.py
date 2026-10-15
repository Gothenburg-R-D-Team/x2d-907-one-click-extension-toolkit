"""Local WAV authoring and exact recovery catalogs. No camera connection."""
from pathlib import Path
import array, hashlib, io, json, math, os, runpy, shutil, tarfile, wave

D = Path(__file__).resolve().parent
sha = lambda data: hashlib.sha256(data).hexdigest()
TARGET = '/system/etc/x2d-shutter-sound/custom.wav'
PIN = 'sound_profile_pins.py'

def pins(root=D):
    file = Path(root)/PIN
    return runpy.run_path(str(file)) if file.exists() else {'HISTORY': (), 'CURRENT_AUDIO': None}

def local_sound_history():
    return pins()['HISTORY']

def audio_record_matches(actual, expected):
    return actual.get('shutterAudio') == expected.get('shutterAudio')

def validate_audio(manifest):
    expected = pins()['CURRENT_AUDIO']
    if manifest.get('shutterAudio') != expected:
        raise RuntimeError('自定义快门音清单校验失败，请重新解压完整安装包')
    if expected and not any(e['target']==TARGET and e['sha256']==expected['sha256']
                            for e in manifest['files']):
        raise RuntimeError('自定义快门音文件校验失败')

def canonical_wav(source):
    """Trim exact digital silence; keep quiet attack/decay, resample, limit peaks.

    The persistent player submits all samples without an authored silence tail.
    """
    data = Path(source).read_bytes()
    if len(data)>2_000_000: raise ValueError('WAV 文件不能超过 2 MB')
    with wave.open(io.BytesIO(data), 'rb') as w:
        rate, channels, frames = w.getframerate(), w.getnchannels(), w.getnframes()
        if w.getsampwidth()!=2 or channels not in (1,2) or not 8000<=rate<=96000:
            raise ValueError('请选择 16 位 PCM WAV，单声道或双声道，8–96 kHz')
        if not 0.08<=frames/rate<=1.5:
            raise ValueError('快门音长度需要在 0.08–1.5 秒之间')
        values = array.array('h',w.readframes(frames))
        if len(values)!=frames*channels: raise ValueError('WAV 音频数据不完整')
    active = [i for i in range(frames)
              if any(values[i*channels+c] != 0 for c in range(channels))]
    if not active: raise ValueError('WAV 音量过低或全为静音')
    first, last = active[0], active[-1]+1
    values = values[first*channels:last*channels]
    frames = last-first
    if frames/rate < 0.08: raise ValueError('去除静音后的快门音不能短于 0.08 秒')
    count = round(frames*48000/rate)
    stereo=[]
    for i in range(count):
        pos=i*rate/48000;left=min(int(pos),frames-1);right=min(left+1,frames-1);weight=pos-left
        for c in range(2):
            channel=c if channels==2 else 0
            stereo.append(values[left*channels+channel]*(1-weight)+values[right*channels+channel]*weight)
    peak=max((abs(v) for v in stereo),default=0)
    if peak<8: raise ValueError('WAV 音量过低或全为静音')
    gain=min(1,26200/peak)
    pcm=array.array('h',(round(v*gain) for v in stereo))
    out=io.BytesIO()
    with wave.open(out,'wb') as w:
        w.setnchannels(2);w.setsampwidth(2);w.setframerate(48000);w.writeframes(pcm.tobytes())
    return out.getvalue(), round(count/48)

def reseal(root, manifest):
    p=Path(root)/'native-package'
    for entry in manifest['files']+sum(manifest['uiLanguages'].values(),[]):
        data=(p/entry['source']).read_bytes()
        entry.update(bytes=len(data),sha256=sha(data))
    content=(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n').encode()
    (p/'speed-bundle.json').write_bytes(content)
    with tarfile.open(p/'speed-bundle.tar.gz','w:gz') as archive:
        for name in sorted({e['source'] for e in manifest['files']+sum(manifest['uiLanguages'].values(),[])}):
            archive.add(p/name,arcname=name,recursive=False)
    file_catalog(root)

def file_catalog(root):
    # Seal desktop/runtime inputs independently of camera payload validation.
    rows=[]
    for file in sorted(Path(root).rglob('*')):
        if (not file.is_file() or any(part in ('development','__pycache__','previews') for part in file.relative_to(root).parts)
                or file.name in ('FILES-SHA256.txt','.sound-editing')): continue
        rows.append(sha(file.read_bytes())+'  '+file.relative_to(root).as_posix())
    Path(root,'FILES-SHA256.txt').write_bytes(('\n'.join(rows)+'\n').encode())

def install_audio(root, audio, duration, label, preserve=True, tail_ms=0):
    root=Path(root);p=root/'native-package'
    if (root/'.sound-editing').exists(): raise RuntimeError('快门音更新未完成，请重新解压安装包')
    m=json.loads((p/'speed-bundle.json').read_bytes());catalog=pins(root)
    history=list(catalog['HISTORY'])
    if preserve:
        olddata=(p/'speed-bundle.json').read_bytes();digest=sha(olddata)
        name='previous-local-audio-'+digest+'.json'
        (p/name).write_bytes(olddata)
        for e in m['files']+sum(m['uiLanguages'].values(),[]):
            data=(p/e['source']).read_bytes()
            if sha(data)!=e['sha256']:raise RuntimeError('现有安装包校验失败，未替换快门音')
            dest=p/'previous-payloads'/e['sha256']
            if not dest.exists():dest.write_bytes(data)
        if (name,digest) not in history:history.append((name,digest))
    entry={'source':'X2dShutter-custom.wav','target':TARGET,'bytes':len(audio),'sha256':sha(audio)}
    m['files']=[e for e in m['files'] if e['target']!=TARGET]+[entry]
    info={'format':1,'sha256':sha(audio),'rate':48000,'bits':16,'channels':2,
          'durationMs':duration,'tailMs':tail_ms,'label':label,'deviceVolumeChanged':False}
    m['shutterAudio']=info
    worker=(p/'X2dShutter-worker').read_text(encoding='utf-8')
    import re
    worker=worker.replace('WAV=/system/etc/x2d-shutter-sound/exposure_finished.wav','WAV='+TARGET)
    worker=re.sub(r'^WAV_SHA=.*$', 'WAV_SHA='+sha(audio),worker,flags=re.M)
    worker=re.sub(r'^CACHE_SHA=.*$', 'CACHE_SHA='+sha(audio),worker,flags=re.M)
    begin=worker.index(' # Preserve the byte-exact stock WAV.') if ' # Preserve the byte-exact stock WAV.' in worker else worker.index(' # Copy the validated, authored PCM buffer.')
    end=worker.index(' [ "$(sha256sum "$CACHE.next"',begin)
    worker=worker[:begin]+''' # Copy the validated, authored PCM buffer. Trim and resampling are prepared
 # offline; playback never rewrites stock audio, camera parameters or volume.
 (umask 077; cat "$WAV" >"$CACHE.next") || return 1
'''+worker[end:]
    changes={p/'X2dShutter-worker':worker.encode(),p/entry['source']:audio,
             root/PIN:('CURRENT_AUDIO = '+repr(info)+'\nHISTORY = '+repr(tuple(history))+'\n').encode()}
    version_report=root/'版本与校验.json'
    protected=[*changes,p/'speed-bundle.json',p/'speed-bundle.tar.gz',root/'FILES-SHA256.txt',version_report]
    previous={file:file.read_bytes() if file.exists() else None for file in protected}
    with (root/'.sound-editing').open('x') as marker:marker.write('LOCAL_WAV_UPDATE_V1\n')
    try:
        for file,data in changes.items():file.write_bytes(data)
        reseal(root,m)
        if version_report.exists():
            report=json.loads(version_report.read_bytes())
            report.setdefault('validatedDeliveryManifestSha256',report.get('manifestSha256'))
            report['manifestSha256']=sha((p/'speed-bundle.json').read_bytes())
            report['localAudioChange']={'audio':info,'requiresCameraReinstall':True,
                                        'cameraAccess':False,'hardwarePlaybackVerified':False,
                                        'existingReportsDescribeBaseDelivery':True}
            version_report.write_bytes((json.dumps(report,ensure_ascii=False,indent=2)+'\n').encode())
            file_catalog(root)
    except BaseException:
        for file,data in previous.items():
            if data is not None:file.write_bytes(data)
            elif file.exists():file.unlink()
        raise
    finally:(root/'.sound-editing').unlink()
    return info

def import_wav(root, source):
    audio,duration=canonical_wav(source)
    return install_audio(root,audio,duration,Path(source).name,tail_ms=0)

def preview(root=D):
    import winsound
    winsound.PlaySound(str(Path(root)/'native-package/X2dShutter-custom.wav'),winsound.SND_FILENAME|winsound.SND_ASYNC)

def choose_wav(owner=0):
    import ctypes as C
    from ctypes import wintypes as W
    class OPENFILENAMEW(C.Structure):
        _fields_=[('lStructSize',W.DWORD),('hwndOwner',W.HWND),('hInstance',W.HINSTANCE),
          ('lpstrFilter',W.LPCWSTR),('lpstrCustomFilter',W.LPWSTR),('nMaxCustFilter',W.DWORD),
          ('nFilterIndex',W.DWORD),('lpstrFile',W.LPWSTR),('nMaxFile',W.DWORD),
          ('lpstrFileTitle',W.LPWSTR),('nMaxFileTitle',W.DWORD),('lpstrInitialDir',W.LPCWSTR),
          ('lpstrTitle',W.LPCWSTR),('Flags',W.DWORD),('nFileOffset',W.WORD),('nFileExtension',W.WORD),
          ('lpstrDefExt',W.LPCWSTR),('lCustData',C.c_ssize_t),('lpfnHook',C.c_void_p),
          ('lpTemplateName',W.LPCWSTR),('pvReserved',C.c_void_p),('dwReserved',W.DWORD),('FlagsEx',W.DWORD)]
    buffer=C.create_unicode_buffer(32768);request=OPENFILENAMEW()
    request.lStructSize=C.sizeof(request);request.hwndOwner=owner
    request.lpstrFilter='PCM WAV (*.wav)\0*.wav\0\0';request.lpstrFile=C.cast(buffer,W.LPWSTR)
    request.nMaxFile=len(buffer);request.lpstrTitle='选择自定义快门音（16 位 PCM WAV）'
    request.Flags=0x80000|0x1000|0x800|0x8 # explorer, existing file/path, retain cwd
    choose=C.WinDLL('comdlg32',use_last_error=True).GetOpenFileNameW
    choose.argtypes=[C.POINTER(OPENFILENAMEW)];choose.restype=W.BOOL
    if choose(C.byref(request)): return buffer.value
    return None
