import QtQuick
import com.hasselblad.proxies
QtObject {
    id: root
    property var afcMenu: null
    property var shutterSound: null
    readonly property bool shutterSoundInstalled: (featureMask & 128) !== 0
    property var subjectMenu: null
    property bool subjectMenuRequested: false
    property var subjectPreferenceWrite: null
    property bool subjectConfirmationPending: false
    property bool subjectPreferenceValue: false
    readonly property bool subjectMenuInstalled: (featureMask & 64) !== 0
    readonly property bool subjectMenuEnabled: subjectMenuInstalled && master && ready && !faulted && subjectMenuRequested
    function setSubjectMenu(value) {
        if (!subjectMenuInstalled || !master || !ready || faulted || busy ||
                !subjectMenu || subjectMenu.faulted) return false
        if (subjectPreferenceWrite || subjectConfirmationPending) return false
        var xhr = new XMLHttpRequest()
        subjectPreferenceWrite = xhr
        subjectPreferenceValue = !!value
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE || subjectPreferenceWrite !== xhr) return
            subjectPreferenceWrite = null
            // Qt local-file PUT can return status 0 after a successful write.
            // Only the worker's subsequent atomic commit/readback confirms it.
            subjectConfirmationPending = true
            modeReconcilePending = true; flushModeReconcile()
        }
        xhr.open("PUT", "file:///tmp/x2d-speed-buff/subject-menu.request")
        xhr.send(value ? "X2D_SUBJECT_MENU_ON_V1\n" : "X2D_SUBJECT_MENU_OFF_V1\n")
        return true
    }
    property int statusFailures: 0
    property bool ready: false
    property bool faulted: false
    property bool busy: false
    property bool inFlight: false
    property bool focusAreasInstalled: false
    property bool loaded: false
    property string speedLevel: "medium"
    signal speedSelectionConfirmed()
    property bool master: false
    property bool afcEnabled: false
    property bool aftReady: false
    property bool aftActive: false
    property bool aftSaved: false
    readonly property bool aftEnabled: aftActive || aftSaved
    property bool eyeReady: false
    property bool eyeActive: false
    property bool eyeSaved: false
    property bool eyeSuppressed: false
    readonly property bool eyeEnabled: eyeActive || eyeSaved
    property bool prankIbis: false
    property int featureMask: 0
    readonly property bool afcInstalled: (featureMask & 1) !== 0
    readonly property bool speedInstalled: (featureMask & 2) !== 0
    readonly property bool brightnessInstalled: (featureMask & 4) !== 0
    readonly property bool eyeInstalled: (featureMask & 8) !== 0
    readonly property bool aftInstalled: (featureMask & 16) !== 0
    property string statusMessage: "正在读取功能状态"
    property var currentRequest: null
    property bool modeReconcilePending: false
    function reconcileFocusMode() {
        if (!afcInstalled && !(aftInstalled && eyeInstalled)) return
        modeReconcilePending = true
        modeDebounce.restart()
    }
    function flushModeReconcile() {
        if (!modeReconcilePending || inFlight) return
        modeReconcilePending = false
        request("status")
    }
    function syncAfcMenu() {
        if (afcMenu !== null && afcMenu.ready && !afcMenu.focusPopoverOpen)
            afcMenu.setFeatures(afcInstalled && master && afcEnabled,
                               false)
    }
    function request(action) {
        if (inFlight) {
            if (action === "status" || busy) return false
            var previous = currentRequest
            currentRequest = null; requestDeadline.stop(); inFlight = false
            if (previous) previous.abort()
        }
        inFlight = true
        var confirmingSubject = action === "status" && subjectConfirmationPending
        // Quiet polling never changes the UI's operation spinner.
        busy = action !== "status"
        var xhr = new XMLHttpRequest()
        currentRequest = xhr
        requestDeadline.restart()
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE || currentRequest !== xhr) return
            requestDeadline.stop()
            currentRequest = null
            inFlight = false
            busy = false
            try {
                if (xhr.status !== 200) throw new Error("backend unavailable")
                var state = JSON.parse(xhr.responseText)
                if (state.ready === true) {
                    if(typeof state.focusAreasInstalled!=="boolean" || typeof state.subjectMenuRequested!=="boolean" || typeof state.aftReady!=="boolean")
                        throw new Error("incomplete capability snapshot")
                    if(featureMask && state.featureMask!==featureMask)throw new Error("changed installation mask")
                    statusFailures=0
                    focusAreasInstalled = state.focusAreasInstalled === true
                    var confirmedMask = state.featureMask === undefined ? (featureMask || 7) : state.featureMask
                    if (typeof confirmedMask !== "number" || !Number.isInteger(confirmedMask) || confirmedMask < 1 || confirmedMask > 255)
                        throw new Error("invalid installed features")
                    // A failed command's fallback has no installation record.
                    // Keep the last confirmed menu layout until a valid reply.
                    featureMask = confirmedMask
                    prankIbis = state.prankIbis === true
                    loaded = state.active === true
                    if (state.speedLevel === "low" || state.speedLevel === "medium" || state.speedLevel === "high")
                        speedLevel = state.speedLevel
                    subjectMenuRequested = state.subjectMenuRequested === true
                    master = state.master === true
                    afcEnabled = state.afc === true
                    aftReady=state.aftReady===true
                    aftActive=aftReady && state.aftActive===true
                    aftSaved=state.aftSaved===true
                    eyeReady = state.eyeReady === true
                    eyeActive = eyeReady && state.eyeActive === true
                    eyeSaved = state.eyeSaved === true
                    eyeSuppressed = state.eyeSuppressed === true
                }
                ready = state.ready === true
                faulted = !ready
                statusMessage = state.message
                if (ready && confirmingSubject) {
                    subjectConfirmationPending = false
                    if (state.subjectMenuRequested !== subjectPreferenceValue)
                        statusMessage = "主体菜单设置保存失败"
                }
                if (ready) syncAfcMenu()
                if (ready && action.indexOf("speed_") === 0 && state.speedLevel === action.substring(6))
                    speedSelectionConfirmed()
            } catch (e) {
                statusFailures++
                if(action==="status" && ready && statusFailures<3)return
                ready = false; faulted = true
                statusMessage = "服务未就绪；请检查连接或使用恢复原状"
            }
            if (modeReconcilePending) Qt.callLater(root.flushModeReconcile)
        }
        xhr.open(action === "status" ? "GET" : "POST", "http://127.0.0.1:18763/" + action)
        xhr.send()
        return true
    }
    function setEnabled(value) { return !value || speedInstalled ? request(value ? "enable" : "disable") : false }
    function setSpeedLevel(level) {
        if (!speedInstalled || !loaded || !master || !ready || faulted || busy ||
            (level !== "low" && level !== "medium" && level !== "high")) return false
        // A confirmed user choice takes precedence over a quiet status read.
        // Ignore that read's late callback; the worker still serializes actions
        // and checks fresh process state before changing the speed function.
        if (inFlight) {
            var pollRequest = currentRequest
            currentRequest = null; requestDeadline.stop(); inFlight = false
            if (pollRequest !== null) pollRequest.abort()
        }
        return request("speed_" + level)
    }
    function setAfc(value) { return !value || afcInstalled ? request(value ? "afc_on" : "afc_off") : false }
    function setMaster(value) { return request(value ? "master_on" : "master_off") }
    function setEye(value) { return eyeInstalled && master && (eyeReady || (!value && eyeSaved)) ? request(value ? "eye_on" : "eye_off") : false }
    function setAft(value) { return aftInstalled && master && (aftReady || (!value && aftSaved)) ? request(value ? "aft_on" : "aft_off") : false }
    property Timer modeDebounce: Timer { interval: 40; onTriggered: root.flushModeReconcile() }
    property Timer fastReconcile: Timer {
        interval: 250; repeat: true; property int remaining: 0
        onTriggered: {
            if (!root.inFlight) { root.modeReconcilePending = true; root.flushModeReconcile(); remaining-- }
            if (remaining <= 0) stop()
        }
    }
    property Timer poll: Timer { interval: 5000; running: true; repeat: true; onTriggered: root.request("status") }
    property Timer requestDeadline: Timer {
        interval: 15000
        onTriggered: {
            var xhr = root.currentRequest
            root.currentRequest = null; root.inFlight = false; root.busy = false
            if (xhr !== null) xhr.abort()
            root.ready = false; root.faulted = true
            root.statusMessage = "读取超时，尚未确认本次操作结果"
            if (root.modeReconcilePending) Qt.callLater(root.flushModeReconcile)
        }
    }
    property Connections afcChanges: Connections {
        target: root.afcMenu
        function onReadyChanged() { root.syncAfcMenu() }
        function onFocusPopoverOpenChanged() { root.syncAfcMenu() }
    }
    property Connections selectedModeChanges: Connections {
        target: Camera
        function onFocus_modeChanged() { root.reconcileFocusMode(); root.fastReconcile.remaining=4; root.fastReconcile.restart() }
        function onFace_detectionChanged() { root.reconcileFocusMode() }
        function onAf_statusChanged() { if (Camera.af_status === 1) root.reconcileFocusMode() }
        function onExposure_statusChanged() { if (Camera.exposure_status === 0) root.reconcileFocusMode() }
    }
    Component.onCompleted: request("status")
    Component.onDestruction: {
        if (currentRequest) currentRequest.abort()
        if (subjectPreferenceWrite) subjectPreferenceWrite.abort()
    }
}
