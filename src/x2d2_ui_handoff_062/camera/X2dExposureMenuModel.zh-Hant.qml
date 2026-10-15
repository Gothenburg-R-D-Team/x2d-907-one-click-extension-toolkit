import QtQuick
import QtQml.Models
import com.hasselblad.menumodel
import com.hasselblad.types
DelegateModel {
    id:root
    objectName:"X2dExposureMenuModel"
    property var sourceModel:null
    property Component stockDelegate:null
    property var controller:null
    property string menuName:""
    property bool ready:false
    property bool reconciling:false
    property int insertionIndex:-1
    property bool suppressSyntheticBlankSection:false
    property string reportedStatus:""
    readonly property int totalSize:items.count
    readonly property string extraName:"x2dSimulatedShutterSound"
    property string caption:"模擬快門音"
    model:sourceModel
    delegate:stockDelegate
    function srcIndex(name) {
        if(name===extraName)return insertionIndex
        var i=sourceModel ? sourceModel.srcIndex(name) : -1
        return insertionIndex>=0 && i>=insertionIndex ? i+1 : i
    }
    function itemEnabled(i){return i>=0 && i<items.count && items.get(i).model.itemEnabled===true}
    function isSectionFirstInList(section){return sourceModel ? sourceModel.isSectionFirstInList(section):false}
    function separatorTopPadding(section){return sourceModel ? sourceModel.separatorTopPadding(section):0}
    function separatorBottomPadding(section){return sourceModel ? sourceModel.separatorBottomPadding(section):0}
    function reconcile() {
        if(!ready || reconciling)return
        reconciling=true
        var extra=-1,anchor=-1,hits=0,section="",collision=false
        for(var i=0;i<items.count;++i){
            var row=items.get(i)
            if(row.isUnresolved && row.model.itemName===extraName)extra=i
            else if(row.model.itemName===extraName)collision=true
            else if(row.model.itemName==="shutter_speed_limit_selected" || row.model.propName==="shutter_speed_limit_selected") {anchor=i;hits++;section=row.model.sectionName}
        }
        var want=controller && controller.menuAvailable && menuName==="exposureMenu" && hits===1 && !collision
        var status=menuName+":"+items.count+":"+hits+":"+(controller && controller.menuAvailable)+":"+collision
        if(status!==reportedStatus){
            reportedStatus=status
            console.info("X2D_SHUTTER_MENU_STATUS",status)
        }
        if(extra>=0 && (!want || extra!==anchor+1)){
            items.remove(extra,1)
            if(extra<anchor)anchor--
            extra=-1
        }
        if(want && extra<0){
            items.insert(anchor+1,{itemName:extraName,sectionName:section,elem:GuiTypes.E_MenuElem_Switch,
                text1:caption,propValue:controller.enabledPreference,itemEnabled:!controller.busy,
                demo:false,options:0,description:""})
            extra=anchor+1
            console.info("X2D_SHUTTER_MENU_INSERTED",menuName,extraName)
        }
        if(extra>=0){var row=items.get(extra).model;row.propValue=controller.enabledPreference;row.itemEnabled=controller.menuAvailable && !controller.busy}
        // Unresolved DelegateModel rows may expose an empty section to the
        // ListView even though the local model role retains its section name.
        // Hide that synthetic header only when no stock row has a blank section.
        var stockHasBlankSection=false
        for(var j=0;j<items.count;++j){
            var item=items.get(j)
            if(!item.isUnresolved && !item.model.sectionName)stockHasBlankSection=true
        }
        suppressSyntheticBlankSection=extra>=0 && !stockHasBlankSection
        insertionIndex=extra;reconciling=false
    }
    function schedule(){if(ready && !reconciling)Qt.callLater(reconcile)}
    items.onChanged:schedule()
    onSourceModelChanged:schedule()
    onMenuNameChanged:schedule()
    property Connections changes:Connections {
        target:root.controller
        function onMenuAvailableChanged(){root.schedule()}
        function onEnabledPreferenceChanged(){root.schedule()}
        function onBusyChanged(){root.schedule()}
    }
    Component.onCompleted:{ready=true;reconcile()}
}
