"""Fixed optional capture-only targets; no camera access at import or build time."""
FILES=('NativeDriveMode.qml','NativePixelSettings.qml','NativePixelDropdown.qml','NativePixelSelector.qml',
       'NativePixelBackend.qml','pixel-parameters.sh','NativePixelControlBridge.qml','NativePixelControl.js',
       'pixel-initial-delay.sh','NativePixelCountdown.qml','NativePixelCountdownController.qml','NativePixelTrace.js',
       'pixel-stock-countdown-audio.sh','ic_drive_mode_multishot.svg','ic_drive_mode_multishot_disable.svg')
BASE='/system/etc/x2d-multishot'
TARGETS=tuple(BASE+'/'+n for n in FILES+('service','assets.sha256','assets.list'))
ROOT='/blackbox/.x2d-play-software'
OWNED=tuple(ROOT+'/pixel-'+n for n in ('restoring','baseline','baseline.next','initial','initial.next'))
SPEC=dict(format=1,serviceSha256='fbcf828f73bca13f0c8b95e7dd0b95ac483ae36954ec06179098c8a1a65f9f82',
          availability='installed-selection',cameraSwitch=False,captureOnly=True,frames=[4,6,16],
          initialSeconds=[0]+list(range(2,61)),waitMilliseconds=[0,500,1000,2000,5000],soundLevels=[0,1,2,3],
          serviceRamBytes=168,restoreStockParameters=True)

COPY = {
    "请选择张数": ("Select frame count", "請選擇張數"),
    "读取失败，正在重试…": ("Read failed. Retrying…", "讀取失敗，正在重試…"),
    "拍摄倒计时": ("Capture Countdown", "拍攝倒計時"),
    "像素位移": ("Pixel Shift", "像素位移"),
    "拍摄张数": ("Frames", "拍攝張數"),
    "初始延迟": ("Initial Delay", "初始延遲"),
    "帧间等待": ("Frame Interval", "幀間等待"),
    "关闭": ("Off", "關閉"),
    "任意按键退出": ("Press any key to cancel", "任意按鍵退出"),
    "参数已保存": ("Parameters saved", "參數已儲存"),
    "正在保存…": ("Saving…", "正在儲存…"),
    "正在读取参数…": ("Reading parameters…", "正在讀取參數…"),
    "读取中…": ("Reading…", "讀取中…"),
    "未能保存，请重新选择": ("Could not save. Select again", "未能儲存，請重新選擇"),
    "未能启用，请重新选择": ("Could not enable. Select again", "未能啟用，請重新選擇"),
    "相机忙，请稍后选择": ("Camera busy. Try again later", "相機忙，請稍後選擇"),
    "未能启用，请检查 RAW 和本机存储": ("Check RAW format and local storage", "未能啟用，請檢查 RAW 和本機儲存"),
    "正在设置 RAW 和本机保存…": ("Setting RAW and local storage…", "正在設定 RAW 和本機儲存…"),
    "RAW 序列保存到相机，按机身快门开始拍摄": ("RAW sequence saved to camera. Press the shutter to capture", "RAW 序列儲存到相機，按機身快門開始拍攝"),
    "请退出 USB 磁盘导出后再拍摄": ("Exit USB storage export before capture", "請退出 USB 磁碟匯出後再拍攝"),
    "请使用三脚架": ("Use a tripod", "請使用三腳架"),
    "请使用三脚架\\n保持相机与被摄物静止": ("Use a tripod\\nKeep camera and subject still", "請使用三腳架\\n保持相機與被攝物靜止"),
    "保存原始 RAW 序列，请在电脑合成": ("Save the original RAW sequence; merge on a computer", "儲存原始 RAW 序列，請在電腦合成"),
    "保存原始 RAW 序列，请在电脑合成\\n请使用三脚架，保持相机与被摄物静止": ("Save original RAWs; merge on a computer\\nUse a tripod and keep camera and subject still", "儲存原始 RAW 序列，請在電腦合成\\n請使用三腳架，保持相機與被攝物靜止"),
}
def localize(text,language):
    index=0 if language=='en' else 1
    for before,values in COPY.items(): text=text.replace('"'+before+'"','"'+values[index]+'"')
    for n in (0,0.5,1,2,5):text=text.replace('"'+str(n)+' 秒"','"'+str(n)+(' s' if language=='en' else ' 秒')+'"')
    for n in (4,6,16):text=text.replace('"'+str(n)+' 张"','"'+str(n)+(' frames' if language=='en' else ' 張')+'"')
    text=text.replace('" 张"','" frames"' if language=='en' else '" 張"').replace('" 秒"','" s"' if language=='en' else '" 秒"')
    return text
