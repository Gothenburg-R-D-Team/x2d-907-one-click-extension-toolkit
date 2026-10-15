import QtQuick
import com.hasselblad.types
import com.hasselblad.constants

Item {
 id: root
 visible: false; width: 0; height: 0
 property var uiRoot: null
 property var subject: null
 property bool areaEnabled: false
 property var views: []
 property var live: null
 property int mode: 0
 property int areaWidth: 1800
 property int areaHeight: 1400
 property int requestId: 1
 property int retryEpoch: 0
 property bool retried: false
 property bool sawRunning: false
 property bool ready: false
 property bool busy: false
 property var request: null
 property var backend: ({})
 property string token: "HANDOFF_TOKEN_NOT_CONFIGURED"
 property string notice: "实验区域 · 点为原厂模式"
 readonly property var vm: live ? live.viewModel : null
 readonly property bool eligible: areaEnabled && vm !== null && live.visible && vm.screenBack &&
   vm.focusMode === HblmTypes.E_FocusModes_Afs && vm.faceDetection === HblmTypes.E_FaceDetection_Off &&
   vm.attachedLens === HblmTypes.E_LensType_XcLens && !vm.exposing && !vm.isZoomed &&
   vm.cropFactors.width === 0 && vm.cropFactors.height === 0 && !live.overlayOff && !live.popupActive
 readonly property bool applied: eligible && ready && backend.appliedMode === mode && backend.appliedId === requestId
 function findLive(item) {
  if (!item) return
  if (item.objectName === "LiveViewOverlay_root" && item.viewModel) {
   for (var i=0;i<views.length;i++) if(views[i].host===item) return
   var overlay=overlayFactory.createObject(item,{host:item})
   if(overlay) views.push(overlay)
   return
  }
  for(var j=0;j<item.children.length;j++)findLive(item.children[j])
 }
 function discover() {
  findLive(uiRoot)
  live=null
  for(var i=0;i<views.length;i++)if(views[i] && views[i].host && views[i].host.visible && views[i].host.viewModel.screenBack){live=views[i].host;break}
 }
 Component.onCompleted: {discover();if(areaEnabled)send()}
 onAreaEnabledChanged: {if(areaEnabled){discover();send()}else{mode=0;send()}}
 onEligibleChanged: send()
 function select(index) {
  if(index<0 || index>2)return false
  if(index && (!areaEnabled || !ready)){notice="后端尚未就绪，请稍候；未启用区域功能";return false}
  mode=index;requestId++;retried=false;sawRunning=false;retryEpoch=0
  console.info("X2D_AREA_DEMO_SELECT",mode,requestId)
  if(subject)subject.selectedFocusIndex=index
  notice=index===0?"点 · 已回到原厂区域":index===1?"扩展点 实验 · 中心失败后扩展一次": "自定义 实验 · 拖动框移动，双指缩放"
  send();return true
 }
 function resize(w,h) {
  if(vm && vm.inSession)return
  w=Math.max(400,Math.min(3500,Math.round(w/100)*100));h=Math.max(400,Math.min(3500,Math.round(h/100)*100))
  if(w*h>9000000)return
  areaWidth=w;areaHeight=h;requestId++;send()
 }
 function updateSession() {
  if(!eligible || mode!==1){sawRunning=false;retried=false;retryEpoch=0;return}
  if(!vm.inSession){sawRunning=false;retried=false;retryEpoch=0;return}
  if(vm.afStatus===HblmTypes.E_AutoFocusStatus_Running)sawRunning=true
  if(sawRunning && !retried && vm.afResult===HblmTypes.E_AutoFocusResult_Failed){
   retried=true;retryEpoch=requestId+1;requestId++
   console.info("X2D_AREA_DEMO_CENTER_FAILED",requestId,vm.inSession)
   notice="中心点失败，已请求一次邻域扩展";send()
  }
 }
 function send() {
  if(busy)return
  var flags=eligible && mode?1:0
  if(flags && mode===1 && vm.inSession && retried && vm.afResult===HblmTypes.E_AutoFocusResult_Failed)flags|=2
  busy=true
  var xhr=new XMLHttpRequest();request=xhr
  xhr.onreadystatechange=function(){
   if(xhr.readyState!==XMLHttpRequest.DONE || request!==xhr)return
   request=null;busy=false
   if(xhr.status!==200){ready=false;return}
   try{var state=JSON.parse(xhr.responseText);backend=state;ready=!!state.ready && !!state.accepted}
   catch(e){ready=false}
  }
  xhr.open("GET","http://127.0.0.1:56123/state?token="+token+"&mode="+mode+"&w="+areaWidth+"&h="+areaHeight+"&allow="+flags+"&retry="+retryEpoch+"&id="+requestId)
  xhr.send()
 }
 Timer {interval:1500;repeat:true;running:root.areaEnabled;onTriggered:root.discover()}
 Timer {interval:250;repeat:true;running:root.areaEnabled;onTriggered:{root.updateSession();root.send()}}
 Timer {interval:700;running:root.busy;onTriggered:{var old=root.request;root.request=null;root.busy=false;root.ready=false;if(old)old.abort()}}
 Component.onDestruction:{if(request)request.abort();for(var i=0;i<views.length;i++)if(views[i])views[i].destroy()}
 Connections {
  target:root.vm;ignoreUnknownSignals:true
  function onAfResultChanged(){root.updateSession();root.send()}
  function onAfStatusChanged(){root.updateSession()}
  function onInSessionChanged(){root.updateSession();root.send()}
  function onExposingChanged(){root.send()}
 }
 Component {
  id:overlayFactory
  Item {
   id:visual
   property var host:null
   readonly property var model:host?host.viewModel:null
   readonly property bool selected:root.live===host
   width:parent.width/parent.height>4/3?parent.height*4/3:parent.width
   height:width*3/4;anchors.centerIn:parent;z:80
   visible:selected && root.eligible && root.mode!==0 && !model.screenEVF
   Rectangle {
    id:box
    objectName:"X2dAreaFocusFrame"
    readonly property point center:model?model.focusRegionCentrePoint:Qt.point(.5,.5)
    readonly property bool actual:root.applied
    width:(root.mode===2?root.areaWidth/10000:root.backend.w>0 && actual?root.backend.w:0.12)*visual.width
    height:(root.mode===2?root.areaHeight/10000:root.backend.h>0 && actual?root.backend.h:0.12)*visual.height
    x:Math.max(0,Math.min(visual.width-width,center.x*visual.width-width/2))
    y:Math.max(0,Math.min(visual.height-height,center.y*visual.height-height/2))
    color:"transparent";border.width:2*Constants.scaleFactor
    readonly property bool focusSuccess:actual && model.inSession && (model.afResult===HblmTypes.E_AutoFocusResult_Success || model.afResult===HblmTypes.E_AutoFocusResult_SuccessCont)
    readonly property bool focusFailure:actual && model.inSession && (model.afResult===HblmTypes.E_AutoFocusResult_Failed || model.afResult===HblmTypes.E_AutoFocusResult_FailedCont)
    border.color:!actual?"#ffb347":focusFailure?Constants.afFailedColor:focusSuccess?Constants.afSuccessColor:"white"
    PinchArea {
     anchors.fill:parent;enabled:root.mode===2 && !model.inSession && model.touchInputAllowed
     property int initialW:0;property int initialH:0
     pinch.target:Item{}
     onPinchStarted:{initialW=root.areaWidth;initialH=root.areaHeight}
     onPinchUpdated:(pinch)=>{root.resize(initialW*pinch.scale,initialH*pinch.scale)}
     MouseArea {
      anchors.fill:parent
      property point initialMouse:Qt.point(0,0)
      property point initialCenter:Qt.point(0,0)
      onPressed:(mouse)=>{initialMouse=mapToItem(visual,mouse.x,mouse.y);initialCenter=box.center}
      onPositionChanged:(mouse)=>{
       if(!pressed || parent.pinch.active)return
       var pos=mapToItem(visual,mouse.x,mouse.y)
       var cx=Math.max(root.areaWidth/20000,Math.min(1-root.areaWidth/20000,initialCenter.x+(pos.x-initialMouse.x)/visual.width))
       var cy=Math.max(root.areaHeight/20000,Math.min(1-root.areaHeight/20000,initialCenter.y+(pos.y-initialMouse.y)/visual.height))
       model.setFocusPoint(Qt.point(cx,cy));root.requestId++;root.send()
      }
     }
    }
   }
   Rectangle {
    x:12;y:12;width:label.implicitWidth+20;height:34*Constants.scaleFactor
    color:"#99000000";radius:3
    Text{id:label;anchors.centerIn:parent;color:box.border.color;font.pixelSize:16*Constants.scaleFactor
     text:(root.mode===1?"扩展点":"自定义")+" 实验 · "+(root.applied?"ROI 已提交":"等待实际 ROI")}
   }
  }
 }
}
