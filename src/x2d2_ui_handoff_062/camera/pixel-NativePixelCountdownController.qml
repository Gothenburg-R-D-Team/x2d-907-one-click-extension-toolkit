import QtQuick
import QtQuick.Window
import com.hasselblad.proxies
import com.hasselblad.hblsystemtime
import "NativePixelTrace.js" as Trace

// This observes native timing only. It never initiates an exposure or delays it.
Item {
    id: root
    objectName: "NativePixelCountdownController"
    property var sceneRoot: null
    property var screen: null
    property var screenComponent: null
    property int initialDelayMs: 0
    property int sessionFrameBaseline: 0
    property real deadline: 0
    property real now: 0
    property real nextBeep: 0
    property bool sessionActive: false
    property bool timerConsumed: false
    property bool cancelled: false
    property string lastDiagnostic: ""
    readonly property bool nativeActive: Camera.drive_mode === 6 && (Camera.exposure_status & 1024) !== 0
    // Keep the original 200 ms position settling time without showing a sixth
    // second when the user selected five. The native timer still owns capture.
    readonly property int remainingSeconds: deadline > now ?
        Math.min(Math.max(1, Math.ceil(initialDelayMs / 1000)), Math.ceil((deadline - now) / 1000)) : 0
    readonly property bool countdownActive: nativeActive && !cancelled && deadline > 0 &&
                                          Number(Camera.timer_end_time) === deadline && remainingSeconds > 0
    onCountdownActiveChanged: {
        if (countdownActive && screen) Qt.callLater(function() {
            if (root.countdownActive && root.screen) root.screen.forceActiveFocus()
        })
    }
    signal reminder(string kind, int level)
    readonly property var displayWindow: sceneRoot ? sceneRoot.Window.window : null
    Connections {
        target: root.displayWindow
        function onActiveFocusItemChanged() {
            if (root.countdownActive && root.screen && !root.screen.activeFocus) Qt.callLater(function() {
                if (root.countdownActive && root.screen) root.screen.forceActiveFocus()
            })
        }
    }
    onNativeActiveChanged: update()
    Connections {
        target: Camera
        function onTimer_end_timeChanged() { root.update() }
        function onExposures_in_sessionChanged() { root.update() }
    }
    function find(item, name) {
        if (!item) return null
        if (item.objectName === name) return item
        for (var i=0; i<item.children.length; ++i) {
            var found=find(item.children[i], name)
            if (found) return found
        }
        return null
    }
    function attachScreen() {
        if (screen || !sceneRoot) return
        // Main's original loader already owns the actual display model even
        // while its asynchronously created exposure page does not exist.
        var loader=find(sceneRoot, "exposing_loader")
        var container=find(sceneRoot, "content_container")
        if (!loader || !container || !loader.arguments || !loader.arguments.viewModel) {
            var diagnostic=JSON.stringify({loader:!!loader,container:!!container,model:!!(loader && loader.arguments && loader.arguments.viewModel)})
            if (lastDiagnostic !== diagnostic) { lastDiagnostic=diagnostic; Trace.record("controller", "waiting-for-scene", JSON.parse(diagnostic)) }
            return
        }
        if (!screenComponent) screenComponent=Qt.createComponent("file:///system/etc/x2d-multishot/NativePixelCountdown.qml")
        if (screenComponent.status !== Component.Ready) {
            if (screenComponent.status === Component.Error) {
                console.warn("PIXEL_COUNTDOWN_COMPONENT",screenComponent.errorString())
                if (lastDiagnostic !== screenComponent.errorString()) { lastDiagnostic=screenComponent.errorString(); Trace.record("controller", "page-error", {error:lastDiagnostic}) }
            }
            return
        }
        screen=screenComponent.createObject(container, {controller:root, viewModel:loader.arguments.viewModel, z:1000})
        if (!screen) { Trace.record("controller", "page-create-failed", {error:screenComponent.errorString()}); return }
        screen.anchors.fill=container
        screen.visible=Qt.binding(function() { return root.countdownActive })
        screen.focus=Qt.binding(function() { return root.countdownActive })
        screen.loaded=true
        console.info("PIXEL_COUNTDOWN_READY")
        Trace.record("controller", "page-ready", {parent:container.objectName,loaded:screen.loaded,width:screen.width,height:screen.height})
    }
    function beep(kind) {
        var level=Camera.selftimer_sound_level
        if (level >= 1 && level <= 3) reminder(kind, level)
    }
    function update() {
        now=Number(SystemTime.currentBootTime())
        attachScreen()
        if (!nativeActive) {
            sessionActive=false; timerConsumed=false; deadline=0; nextBeep=0; cancelled=false
            return
        }
        if (!sessionActive) {
            sessionActive=true; timerConsumed=false; deadline=0; nextBeep=0; cancelled=false
            sessionFrameBaseline=Camera.exposures_in_session
            // A zero-delay sequence must never promote its first frame wait.
            if (initialDelayMs === 0) timerConsumed=true
        }
        if (!timerConsumed && Camera.exposures_in_session === 0) sessionFrameBaseline=0
        // A previous group's count may arrive before its reset. Only new
        // progress, not a stale positive count, disqualifies the initial timer.
        if (!timerConsumed && Camera.exposures_in_session > 0 &&
            Camera.exposures_in_session !== sessionFrameBaseline) timerConsumed=true
        if (!timerConsumed && Number(Camera.timer_end_time) > now) {
            timerConsumed=true
            deadline=Number(Camera.timer_end_time)
            nextBeep=now+1000
            console.info("PIXEL_COUNTDOWN_START",deadline,initialDelayMs,Camera.exposures_in_session)
            Trace.record("controller", "start", snapshot())
        }
        if (deadline <= 0 || cancelled) return
        if (now >= deadline) {
            if (nextBeep > 0) beep("long")
            nextBeep=0
        } else if (Number(Camera.timer_end_time) !== deadline) {
            // Native cancellation or an early phase exit must not emit a completion beep.
            nextBeep=0; deadline=0
        } else if (nextBeep > 0 && now >= nextBeep) {
            // Factory cadence: last 10 seconds beep; last 3 seconds use 300 ms.
            if (remainingSeconds <= 10) beep("short")
            nextBeep=now+(remainingSeconds <= 3 ? 300 : 1000)
        }
    }
    function cancelCountdown() {
        if (!countdownActive || cancelled) return
        cancelled=true; nextBeep=0
        console.info("PIXEL_COUNTDOWN_CANCEL")
        Trace.record("controller", "cancel", snapshot())
        // Factory stopExposing clears the session and posts CaptureFinish to InitialDelay.
        Camera.doStop_exposing()
    }
    Timer { interval:50; repeat:true; running:root.nativeActive; onTriggered:root.update() }
    function snapshot() {
        return {drive:Camera.drive_mode,status:Camera.exposure_status,timer:Number(Camera.timer_end_time),
            clock:Number(SystemTime.currentBootTime()),frames:Camera.exposures_in_session,initial:initialDelayMs,
            active:nativeActive,consumed:timerConsumed,deadline:deadline,remaining:remainingSeconds,
            page:!!screen,visible:!!(screen && screen.visible),focus:!!(screen && screen.activeFocus)}
    }
    Timer { interval:1000; repeat:true; running:true; onTriggered:{ root.attachScreen(); Trace.record("runtime", "snapshot", root.snapshot()) } }
    Component.onCompleted: { Trace.record("controller", "created", {scene:sceneRoot ? sceneRoot.objectName : ""}); update() }
}
