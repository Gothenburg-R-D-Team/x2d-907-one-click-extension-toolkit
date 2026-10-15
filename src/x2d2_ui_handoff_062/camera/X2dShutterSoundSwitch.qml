import QtQuick
import com.hasselblad.constants
import "qrc:/app/qml/mainmenu" as StockMenu
import "qrc:/app/qml/mainmenu/delegates" as StockDelegate
StockDelegate.BaseDelegate {
    id:root
    objectName:"X2dShutterSoundSwitch"
    property var soundController:null
    height:defaultHeight
    function gotSelected(fromTouch) {
        if(!soundController || (!soundController.enabledPreference && (!soundController.menuAvailable || soundController.busy)))return
        soundController.setSound(!soundController.enabledPreference)
    }
    StockMenu.MenuBoolSelector {
        anchors.left:parent.left;anchors.right:parent.right
        anchors.leftMargin:Constants.settingsMenuSettingLeftMargin
        anchors.rightMargin:Constants.settingsMenuSettingRightMargin
        anchors.top:parent.top;anchors.topMargin:16 * 1.6 * Constants.scaleFactorY
        text:root.model ? root.model.text1 : "模拟快门音"
        value:root.soundController ? root.soundController.enabledPreference:false
        itemEnabled:root.soundController && (root.soundController.enabledPreference || (root.soundController.menuAvailable && !root.soundController.busy))
        highlighted:root.activeFocus;showSwitch:true;fontWeight:root.defaultLabelFontWeight
    }
    StockMenu.MenuDelegateClickArea {
        anchors.fill:parent
        enabled:root.soundController && (root.soundController.enabledPreference || (root.soundController.menuAvailable && !root.soundController.busy))
        helper:root.list.helper;itemIndex:root.itemIndex;subDialogActive:root.subDialog.active
        onSetItemIndex:root.list.currentIndex=itemIndex
        onSetHighlightMoveDuration:(val)=>root.list.highlightMoveDuration=val
        onClicked:root.gotSelected(true)
    }
}
