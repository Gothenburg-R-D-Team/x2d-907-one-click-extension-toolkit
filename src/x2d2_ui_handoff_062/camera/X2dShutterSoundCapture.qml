import QtQuick
import com.hasselblad.proxies
import com.hasselblad.types
import "X2dShutterPolicy.js" as Policy
Item {
    id: root
    visible:false;width:0;height:0
    property alias controller: sound
    X2dShutterSoundController {id:sound}
    property int completedCount: -1
    property bool initialized: false
    property var pendingFrames: []
    property string sendingToken: ""
    property double sentAt: 0
    property var ackRequest: null
    property var writeRequest: null
    property var readinessRequest: null
    property bool uiPublished: false
    // Match the settings controller's bounded token contract (<= 40 bytes).
    property string session: String(Date.now())+"-"+Math.floor(Math.random()*1000000)+"-"+Math.floor(Math.random()*1000000)
    property int sequence: 0
    function publishReady() {
        if(!sound.ready || uiPublished || readinessRequest)return
        var req=new XMLHttpRequest();readinessRequest=req
        req.onreadystatechange=function(){if(req.readyState===XMLHttpRequest.DONE){
            readinessRequest=null
            // Qt file PUT can succeed with status 0; confirm through a GET.
            var check=new XMLHttpRequest();readinessRequest=check
            check.onreadystatechange=function(){if(check.readyState===XMLHttpRequest.DONE){
                readinessRequest=null;uiPublished=check.status===200 && check.responseText.trim()==="XS_SOUND_UI_READY_V1"
            }}
            check.open("GET","file:///tmp/x2d-shutter-sound/ui.ready");check.send()
        }}
        req.open("PUT","file:///tmp/x2d-shutter-sound/ui.ready")
        req.send("XS_SOUND_UI_READY_V1\n")
    }
    Connections {target:sound;function onReadyChanged(){if(!sound.ready)root.uiPublished=false;root.publishReady()}
        function onEffectiveChanged(){if(!sound.effective)root.clearPending()}}
    Timer {interval:1000;running:!root.uiPublished;repeat:true;onTriggered:root.publishReady()}
    function clearPending() {
        pendingFrames=[];sendingToken=""
        var write=writeRequest,ack=ackRequest
        writeRequest=null;ackRequest=null
        if(write)write.abort()
        if(ack)ack.abort()
    }
    function frameChanged() {
        if(!initialized)return
        var result=Policy.observe(completedCount,Camera.exposures_in_session,
            !!(Camera.exposure_status & HblmTypes.E_ExposureStatus_Failed),sound.effective,Camera.eshutter_current)
        completedCount=result.count
        for(var i=0;i<result.frames.length;i++)sendFrameSound(result.frames[i])
    }
    function sendFrameSound(frame) {
        if(!sound.effective)return
        if(pendingFrames.length>=32){console.warn("X2D_SOUND_QUEUE_FULL");return}
        pendingFrames.push({frame:frame,at:Date.now()});pump()
    }
    function pump() {
        if(sendingToken || writeRequest || !sound.effective || !pendingFrames.length)return
        var entry=pendingFrames.shift()
        if(Date.now()-entry.at>2000){console.warn("X2D_SOUND_STALE_FRAME");Qt.callLater(pump);return}
        sendingToken=session+"-"+(++sequence);sentAt=Date.now()
        var req=new XMLHttpRequest();writeRequest=req
        req.onreadystatechange=function(){if(req.readyState===XMLHttpRequest.DONE && writeRequest===req){writeRequest=null;Qt.callLater(root.pump)}}
        req.open("PUT","file:///tmp/x2d-shutter-sound/capture.request")
        req.send("XS1 "+sendingToken+" "+entry.frame+" 1 END\n")
    }
    function readAck(){
        if(ackRequest || !sendingToken)return
        var req=new XMLHttpRequest();ackRequest=req
        var expectedToken=sendingToken
        req.onreadystatechange=function(){if(req.readyState===XMLHttpRequest.DONE){
            if(ackRequest!==req)return
            ackRequest=null
            if(sendingToken!==expectedToken)return
            if(req.status===200 && req.responseText.trim()===sendingToken){sendingToken="";Qt.callLater(pump)}
            else if(Date.now()-sentAt>2000){console.warn("X2D_SOUND_ACK_TIMEOUT");sendingToken="";Qt.callLater(pump)}
        }}
        req.open("GET","file:///tmp/x2d-shutter-sound/capture.ack");req.send()
    }
    Timer {interval:10;running:root.sendingToken!=="";repeat:true;onTriggered:root.readAck()}
    Timer {interval:1000;running:root.writeRequest!==null;onTriggered:{var old=root.writeRequest;root.writeRequest=null;if(old)old.abort();Qt.callLater(root.pump)}}
    Timer {interval:500;running:root.ackRequest!==null;onTriggered:{var old=root.ackRequest;root.ackRequest=null;if(old)old.abort()}}
    Timer {interval:250;repeat:true;running:root.sendingToken!=="";onTriggered:{if(Date.now()-root.sentAt>2000){root.sendingToken="";Qt.callLater(root.pump)}}}
    Connections {
        target:Camera
        function onExposures_in_sessionChanged(){root.frameChanged()}
    }
    Component.onCompleted: {completedCount=Camera.exposures_in_session;initialized=true}
    Component.onDestruction: {if(writeRequest)writeRequest.abort();if(readinessRequest)readinessRequest.abort();if(ackRequest)ackRequest.abort()}
}
