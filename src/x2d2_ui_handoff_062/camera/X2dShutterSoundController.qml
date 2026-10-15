import QtQuick
QtObject {
    id: root
    property bool ready: false
    property bool master: false
    property bool menuPreference: false
    property bool enabledPreference: false
    readonly property bool menuAvailable: ready && master && menuPreference
    readonly property bool effective: menuAvailable && enabledPreference
    property bool busy: false
    property string ack: ""
    property string expected: ""
    // Session + separator + a 10-digit sequence must fit worker's 40-byte limit.
    property string session: String(Date.now())+"-"+Math.floor(Math.random()*1000000)+"-"+Math.floor(Math.random()*1000000)
    property int sequence: 0
    property var reading: null
    property var writing: null
    function pollState() {
        if (reading) return
        var req=new XMLHttpRequest();reading=req
        req.onreadystatechange=function() {
            if(req.readyState!==XMLHttpRequest.DONE || reading!==req)return
            reading=null
            try {
                var state=JSON.parse(req.responseText)
                ready=req.status===200 && state.ready===true
                if(ready && (typeof state.master!=="boolean" || typeof state.menu!=="boolean" || typeof state.enabled!=="boolean"))throw new Error("incomplete sound snapshot")
                if(ready){master=state.master;menuPreference=state.menu;enabledPreference=state.enabled}
                ack=state.ack || ""
                if(busy && ack===expected) {busy=false;deadline.stop()}
            } catch(e) {ready=false}
        }
        req.open("GET","file:///tmp/x2d-shutter-sound/state.json");req.send()
    }
    function request(setting,value) {
        if(setting!=="menu" && setting!=="sound")return false
        if(value && (!ready || !master || busy || writing || (setting==="sound" && !menuAvailable)))return false
        if(!value && writing){var old=writing;writing=null;old.abort()}
        expected=session+"-"+(++sequence);busy=true;deadline.restart()
        var req=new XMLHttpRequest();writing=req
        req.onreadystatechange=function() {
            if(req.readyState!==XMLHttpRequest.DONE || writing!==req)return
            writing=null;pollState()
        }
        req.open("PUT","file:///tmp/x2d-shutter-sound/settings.request")
        req.send("XS1 "+expected+" "+setting+" "+(value?"1":"0")+" END\n")
        return true
    }
    function setMenu(value) {return request("menu",value)}
    function setSound(value) {return request("sound",value)}
    property Timer poll: Timer {interval:200;running:true;repeat:true;onTriggered:root.pollState()}
    property Timer readBound: Timer {interval:1000;running:root.reading!==null;onTriggered:{var old=root.reading;root.reading=null;if(old)old.abort();root.ready=false}}
    property Timer deadline: Timer {interval:3000;onTriggered:{var old=root.writing;root.writing=null;if(old)old.abort();root.busy=false;root.ready=false;root.pollState()}}
    Component.onCompleted: pollState()
    Component.onDestruction: {if(reading)reading.abort();if(writing)writing.abort()}
}
