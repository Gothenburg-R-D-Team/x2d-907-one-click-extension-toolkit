import QtQuick
import com.hasselblad.constants
import com.hasselblad.types
Item {
 id:root;visible:false;width:0;height:0
 property var uiRoot:null
 property bool active:false
 property bool nearbyPriority:false
 property int focusIndex:0
 property var frames:[]
 property var views:[]
 property int lastFace:-1
 function scan(item,view){
  if(!item)return
  if(item.objectName==="LiveViewOverlay_root" && item.viewModel){view=item;if(views.indexOf(item)<0)views.push(item)}
  if(item.objectName==="FaceIndicator_root" && item.targetRect!==undefined){
   var exists=false
   for(var i=0;i<frames.length;i++)if(frames[i] && frames[i].host===item)exists=true
   if(!exists){
    var symbol=null
    for(var j=0;j<item.children.length;j++)if(item.children[j].objectName==="AfSymbol_root")symbol=item.children[j]
    var point=null
    for(var p=0;p<item.parent.children.length;p++)if(item.parent.children[p].objectName==="AfIndicator_root" && item.parent.children[p].showAfIndicator!==undefined)point=item.parent.children[p]
    if(symbol){var frame=frameFactory.createObject(item.parent,{host:item,stockSymbol:symbol,nativePoint:point,view:view || null});if(frame)frames.push(frame)}
   }
  }
  for(var k=0;k<item.children.length;k++)scan(item.children[k],view)
 }
 function selectNear(){
  if(!active || !nearbyPriority || focusIndex!==0){lastFace=-1;return}
  for(var v=0;v<views.length;v++){
   var host=views[v];if(!host || !host.visible || !host.viewModel)continue
   var vm=host.viewModel
   if(vm.exposing || vm.inSession || vm.isZoomed || (vm.cropFactors && (vm.cropFactors.width!==0 || vm.cropFactors.height!==0)) ||
      (vm.cameraRotation!==undefined && vm.cameraRotation!==0) || !vm.showFaceIndicator || vm.afIndicatorStatus!==1 || typeof vm.setFaceTarget!=="function")continue
   var list=vm.faceRegionList,pt=vm.focusRegionCentrePoint;if(!list || !pt)continue
   var best=-1,distance=2
   for(var n=0;n<Math.min(128,list.count);n++){
    var face=list.get(n);if(!face)continue
    var dx=(face.x+face.width/2)/10000-pt.x,dy=(face.y+face.height/2)/10000-pt.y
    if(!Number.isFinite(dx)||!Number.isFinite(dy)||Math.abs(dx)>.09||Math.abs(dy)>.09)continue
    var d=dx*dx+dy*dy;if(d<distance){best=face.id;distance=d}
   }
   if(best>=0 && best!==lastFace){vm.setFaceTarget(best);lastFace=best}
   if(best<0)lastFace=-1
   break
  }
 }
 Component {
  id:frameFactory
  Item {
   id:frame;objectName:"X2dFullFaceLayer";anchors.fill:parent
   property var host:null
   property var stockSymbol:null
   property var nativePoint:null
   property var view:null
   readonly property var vm:view?view.viewModel:null
   readonly property var target:vm && vm.detectedFace!==undefined?vm.detectedFace:null
   readonly property int targetId:target?target.faceId:0
   readonly property rect box:target?target.region:host?host.targetRect:Qt.rect(0,0,0,0)
   readonly property bool genuine:box.width>0 && box.height>0 && (!target || (target.regionValid && !target.detetectionAfcLostTracking)) &&
       (!vm || ((vm.faceDetection===undefined || vm.faceDetection!==HblmTypes.E_FaceDetection_Off) &&
       (!vm.faceDetectionPaused || (vm.inSession && target && !target.detetectionAfcLostTracking)) &&
       !vm.afSelectionStateActive && (vm.canShowAF===undefined || vm.canShowAF)))
   property bool focusConfirmed:false
   readonly property bool failed:stockSymbol && (stockSymbol.afFailed || stockSymbol.exposureFailed || (target && target.detetectionAfcLostTracking))
   readonly property bool owns:root.active && stockSymbol!==null
   onTargetIdChanged:focusConfirmed=false
   onGenuineChanged:if(!genuine)focusConfirmed=false
   onFailedChanged:if(failed)focusConfirmed=false
   function updateResult(){
    if(!vm || vm.afResult===undefined)return
    if(vm.afResult===HblmTypes.E_AutoFocusResult_Success || vm.afResult===HblmTypes.E_AutoFocusResult_SuccessCont)focusConfirmed=true
    else if(vm.afResult===HblmTypes.E_AutoFocusResult_Failed || vm.afResult===HblmTypes.E_AutoFocusResult_FailedCont)focusConfirmed=false
   }
   Binding {target:frame.stockSymbol;property:"visible";value:false;when:frame.owns;restoreMode:Binding.RestoreBindingOrValue}
   // Reuse the manufacturer's current focus point, geometry, feedback and input.
   // Its original hideAf binding can lag a lost tracked target or our face layer.
   Binding {target:frame.nativePoint;property:"showAfIndicator"
    value:!frame.genuine && frame.vm!==null && frame.vm.canShowAF && frame.parent.showMfAssist!==true
    when:frame.owns && frame.nativePoint!==null;restoreMode:Binding.RestoreBindingOrValue}
   Connections {target:frame.stockSymbol;ignoreUnknownSignals:true
    function onAfSuccessChanged(){if(frame.stockSymbol.afSuccess)frame.focusConfirmed=true}
    function onAfFailedChanged(){if(frame.stockSymbol.afFailed)frame.focusConfirmed=false}
    function onAfRunningFirstTimeChanged(){if(frame.stockSymbol.afRunningFirstTime)frame.focusConfirmed=false}
   }
   Connections {target:frame.vm;ignoreUnknownSignals:true
    function onAfResultChanged(){frame.updateResult()}
    function onFocusModeChanged(){frame.focusConfirmed=false}
    function onInSessionChanged(){if(frame.vm.inSession)frame.focusConfirmed=false}
   }
   Rectangle {
    id:border;objectName:"X2dWhiteFaceFrame"
    x:frame.box.x*frame.width;y:frame.box.y*frame.height
    width:frame.box.width*frame.width;height:frame.box.height*frame.height
    visible:frame.owns && frame.genuine
    color:"transparent";border.color:"black";border.width:3*Constants.scaleFactor
    Rectangle {objectName:"X2dFaceFrameColor";anchors.fill:parent;anchors.margins:Constants.scaleFactor;color:"transparent"
     border.color:frame.failed?Constants.afFailedColor:frame.focusConfirmed?Constants.afSuccessColor:"white"
     border.width:Constants.scaleFactor
    }
   }
   Component.onCompleted:if(stockSymbol && stockSymbol.afSuccess)focusConfirmed=true
  }
 }
 Timer {interval:1500;repeat:true;running:root.active;onTriggered:root.scan(root.uiRoot,null)}
 Timer {interval:300;repeat:true;running:root.active && root.nearbyPriority;onTriggered:root.selectNear()}
 onActiveChanged:if(active)Qt.callLater(function(){root.scan(root.uiRoot,null)})
 Component.onDestruction:{active=false;for(var i=0;i<frames.length;i++)if(frames[i])frames[i].destroy()}
}
