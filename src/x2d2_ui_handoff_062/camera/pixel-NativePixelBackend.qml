import QtQuick

Item {
    id: root
    objectName: "NativePixelBackend"
    property bool polling: false
    property bool ready: false
    property bool busy: false
    property int mode: 0
    property int frames: 0
    property int waitMs: 0
    property int initialMs: 0
    property int soundLevel: 0
    property int suStatus: 0
    property string sequence: ""
    property string pendingKind: ""
    property int pendingValue: 0
    property int rounds: 0
    property bool reading: false
    property var writeRequest: null
    property var readRequest: null
    property string queuedKind: ""
    property int queuedValue: 0
    signal completed(string kind, int value, bool okay, string reason)
    function request(kind, value) {
        if (["refresh", "mode", "wait", "initial", "sound"].indexOf(kind) < 0) return false
        if (kind === "mode" && [0,1,2,3].indexOf(value) < 0) return false
        if (kind === "wait" && [0,500,1000,2000,5000].indexOf(value) < 0) return false
        if (kind === "initial" && !(value === 0 || (Number.isInteger(value) && value >= 2000 && value <= 60000 && value % 1000 === 0))) return false
        if (kind === "refresh" && value !== 0) return false
        if (kind === "sound" && [0,1,2,3].indexOf(value) < 0) return false
        if (busy) {
            if (pendingKind !== "refresh" || kind === "refresh" || queuedKind !== "") return false
            queuedKind = kind; queuedValue = value; return true
        }
        sequence = String(Math.max(Date.now(), Number(sequence) + 1))
        pendingKind = kind; pendingValue = value; rounds = 0; busy = true
        var req = new XMLHttpRequest(); writeRequest = req
        req.onreadystatechange = function() {
            if (req !== root.writeRequest || req.readyState !== XMLHttpRequest.DONE || !root.busy) return
            // Qt file PUT does not provide an HTTP success code. The matching
            // worker sequence and readback below are the write acknowledgment.
            root.readState()
        }
        req.open("PUT", "file:///tmp/x2d-native-multishot/parameters.request")
        deadline.start()
        req.send(sequence + "|" + kind + "|" + value + "\n")
        return true
    }
    function finish(okay, reason) {
        var kind = pendingKind, value = pendingValue
        deadline.stop(); busy = false; pendingKind = ""; reading = false
        var writer=writeRequest, reader=readRequest
        writeRequest=null;readRequest=null
        if(writer) writer.abort()
        if(reader) reader.abort()
        completed(kind, value, okay, reason)
        if (queuedKind !== "") {
            var nextKind = queuedKind, nextValue = queuedValue; queuedKind = ""
            Qt.callLater(function() { root.request(nextKind, nextValue) })
        }
    }
    function readState() {
        if (!busy || reading) return
        reading = true
        var req = new XMLHttpRequest(); readRequest = req
        req.onreadystatechange = function() {
            if (req !== root.readRequest || req.readyState !== XMLHttpRequest.DONE) return
            root.readRequest=null
            root.reading = false
            if (!root.busy || req.status !== 200) return
            var state
            try { state = JSON.parse(req.responseText) } catch (error) { return }
            if (state.seq !== root.sequence) return
            if (!state.ready) { root.ready = false; root.finish(false, "read_failed"); return }
            for (var key of ["mode", "frames", "wait", "initial", "sound", "suStatus", "canChange", "exposureStatus"]) {
                if (typeof state[key] !== "number" || !isFinite(state[key]) || state[key] < 0 ||
                    state[key] !== Math.floor(state[key])) { root.ready = false; root.finish(false, "read_failed"); return }
            }
            if (state.sound > 3) { root.ready = false; root.finish(false, "read_failed"); return }
            root.mode = state.mode; root.frames = state.frames; root.waitMs = state.wait; root.suStatus = state.suStatus
            root.initialMs = state.initial
            root.soundLevel = state.sound
            root.ready = true
            var actual = root.pendingKind === "mode" ? state.mode : root.pendingKind === "initial" ? state.initial :
                         root.pendingKind === "sound" ? state.sound : state.wait
            var expectedFrames=root.pendingValue===1?4:root.pendingValue===2?6:16
            var okay = state.ok === true && (root.pendingKind === "refresh" || actual === root.pendingValue) &&
                       (root.pendingKind !== "mode" || root.pendingValue === 0 || state.frames === expectedFrames)
            root.finish(okay, state.reason)
        }
        req.open("GET", "file:///tmp/x2d-native-multishot/parameters.state")
        req.send()
    }
    Timer {
        id: deadline; interval: 100; repeat: true
        onTriggered: {
            if (++root.rounds >= 300) {
                root.ready = false; root.finish(false, "timeout")
            } else root.readState()
        }
    }
    Timer {
        interval: 1000; repeat: true; running: root.polling && !root.busy
        onTriggered: root.request("refresh", 0)
    }
    Component.onCompleted: request("refresh", 0)
    Component.onDestruction: {
        deadline.stop()
        busy = false
        if (writeRequest) writeRequest.abort()
        if (readRequest) readRequest.abort()
    }
}
