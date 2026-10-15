import QtQuick
import com.hasselblad.proxies
import com.hasselblad.uiproxies
import "NativePixelTrace.js" as Trace

Item {
    id: root
    objectName: "NativePixelControlBridge"
    property var controlScreen: null
    property var driveControl: null
    property real stockSymbolScale: 1.0
    property var countdown: null
    property var countdownComponent: null
    property var audioRequest: null
    property int audioSequence: 0
    property int initialDelayMs: 0
    property var initialRead: null
    function readInitial() {
        if (initialRead) return
        var request=new XMLHttpRequest(); initialRead=request
        request.onreadystatechange=function() {
            if(request.readyState !== XMLHttpRequest.DONE) return
            root.initialRead=null
            if(request.status !== 200) return
            var text=request.responseText.trim()
            if(!/^(0|[2-9][0-9]{3}|[1-5][0-9]{4}|60000)$/.test(text)) return
            var value=Number(text)
            if(value===0 || (value>=2000 && value<=60000 && value%1000===0)) root.initialDelayMs=value
        }
        request.open("GET","file:///tmp/x2d-native-multishot/initial-delay.current")
        request.send()
    }
    Timer { interval:500; repeat:true; running:true; onTriggered:root.readInitial() }
    Component.onCompleted: readInitial()
    Component.onDestruction: {
        if(initialRead) initialRead.abort()
        if(audioRequest) audioRequest.abort()
        if(countdown) countdown.destroy()
        if(driveControl) {
            driveControl.symbolScale=stockSymbolScale
            var originalModel=controlScreen.viewModel
            driveControl.symbol=Qt.binding(function() { return originalModel.driveModeIcon })
        }
    }
    function attachCountdown() {
        if (countdown) return
        var scene=controlScreen
        var chain=[]
        if (!scene) { Trace.record("bridge", "missing-control-screen"); return }
        chain.push(scene.objectName)
        while (scene.parent && scene.objectName !== "content_container") { scene=scene.parent; chain.push(scene.objectName) }
        Trace.record("bridge", "scene", {parents:chain})
        countdownComponent=Qt.createComponent("file:///system/etc/x2d-multishot/NativePixelCountdownController.qml")
        Trace.record("bridge", "controller-component", {status:countdownComponent.status, error:countdownComponent.errorString()})
        if (countdownComponent.status !== Component.Ready) return
        countdown=countdownComponent.createObject(scene, {sceneRoot:scene,
            initialDelayMs:Qt.binding(function() { return root.initialDelayMs })})
        if (countdown) { countdown.reminder.connect(sendReminder); Trace.record("bridge", "controller-created") }
        else console.warn("PIXEL_COUNTDOWN_CONTROLLER",countdownComponent.errorString())
    }
    function sendReminder(kind, level) {
        Trace.record("bridge", "reminder", {kind:kind,level:level,busy:!!audioRequest})
        if (audioRequest || (kind !== "short" && kind !== "long") || level < 1 || level > 3) return
        var req=new XMLHttpRequest()
        audioRequest=req
        req.onreadystatechange=function() {
            if (req.readyState === XMLHttpRequest.DONE) root.audioRequest=null
        }
        req.open("PUT", "file:///tmp/x2d-native-multishot/countdown-audio.request")
        req.send("NPA1 "+(++audioSequence)+" "+kind+" "+level+" END\n")
    }
    readonly property string icon: Camera.drive_mode === 6 ?
        (CameraUI.canChangeDriveMode ? "file:///system/etc/x2d-multishot/ic_drive_mode_multishot.svg" :
                                      "file:///system/etc/x2d-multishot/ic_drive_mode_multishot_disable.svg") :
        controlScreen.viewModel.driveModeIcon
    function returnLiveview() {
        controlScreen.viewModel.setMainState("")
        // Use the original liveview signal; its state machine waits for the camera.
        controlScreen.viewModel.setLiveView(true)
    }
    function attach(control) {
        attachCountdown()
        driveControl = control
        stockSymbolScale = control.symbolScale
        // Stock controlscreen SVGs are 44 units; file SVGs honour ScaledImage's
        // requested 100-unit canvas, unlike the native image provider.
        driveControl.symbolScale = Qt.binding(function() {
            return Camera.drive_mode === 6 ? 44 / 100 : root.stockSymbolScale
        })
        driveControl.symbol = Qt.binding(function() { return root.icon })
    }
}
