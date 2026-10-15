import QtQuick
import com.hasselblad.constants
import com.hasselblad.keys
import com.hasselblad.types
import "qrc:/app/qml/components"
import "qrc:/app/qml/components/buttons"
import "qrc:/app/qml/popups" as StockPopups
import "qrc:/app/qml/scripts/Keys.js" as MKeys

// Actual first-generation Popover/FramedImage lifecycle and renderer.
StockPopups.Popover {
    id: root
    objectName: "PopoverFocusMode_root"
    property list<QtObject> focusModeModel
    property var selectionAdapter:null
    property int focusMode: HblmTypes.E_FocusModes_Max
    readonly property int keyOverride: HblmTypes.E_CameraKeyOption_OverrideHalfPress
    readonly property int guiPopupState: HblmTypes.E_GuiPopupState_FocusMode
    heading: "对焦模式"
    contentItem: choices
    handleDefaultKeys: false
    readonly property bool fourItems: focusModeModel.length === 4
    contentWidth: Math.min(width-48,494*1.6*Constants.scaleFactorX)
    contentHeight: fourItems ? Constants.popupHeaderHeight+500*Constants.scaleFactorY :
                              260*1.6*Constants.scaleFactorY+44
    popupTopMargin: Math.max(24,(height-contentHeight)/2)
    signal setFocusMode(int mode)
    onFocusModeChanged: choices.updateCurrentIndex()
    onFocusModeModelChanged: Qt.callLater(choices.updateCurrentIndex)
    onActiveFocusChanged: { if (activeFocus) choices.focus=true }
    Keys.onPressed: (event) => {
        if (MKeys.pressedFnListAcc([KeyFn.Up],event)) choices.move(0,-1)
        else if (MKeys.pressedFnListAcc([KeyFn.Down],event)) choices.move(0,1)
        else if (MKeys.pressedFnListAcc([KeyFn.NavLeft],event)) choices.move(-1,0)
        else if (MKeys.pressedFnListAcc([KeyFn.NavRight],event)) choices.move(1,0)
        else if (MKeys.pressedFnListAcc([KeyFn.PopAccept,KeyFn.FocusMode],event)) choices.setSelected()
        else if (MKeys.pressedFnListAcc([KeyFn.Abort,KeyFn.Menu,KeyFn.Browse],event)) close()
        else event.accepted=false
    }
    content: Item {
        anchors.fill: parent
        Grid {
            id: choices
            objectName: "PopoverFocusMode_list"
            x: 28*Constants.scaleFactorX; y: 30*1.6*Constants.scaleFactorY
            width: parent.width-2*x
            columns: root.fourItems ? 2 : Math.max(1,root.focusModeModel.length)
            // Let Grid infer rows: model replacement briefly changes count
            // one entry at a time, so an explicit rows binding can lag behind.
            rows: 0
            rowSpacing: 24*Constants.scaleFactorY; columnSpacing: 14*Constants.scaleFactorX
            readonly property int count: root.focusModeModel.length
            readonly property int numItems: count
            readonly property int rowCount: Math.ceil(count/columns)
            property int currentIndex: -1
            readonly property real cellWidth: (width-(columns-1)*columnSpacing)/columns
            readonly property real cellHeight: 190*Constants.scaleFactorY
            function updateCurrentIndex() {
                currentIndex=-1
                for (var i=0;i<count;++i) if (root.focusModeModel[i].focusMode===(root.focusMode===6 ? HblmTypes.E_FocusModes_Afc : root.focusMode)) currentIndex=i
            }
            function setSelected() {
                if (currentIndex<0 || currentIndex>=count || !root.focusModeModel[currentIndex].valid) return false
                var mode=root.focusModeModel[currentIndex].focusMode;root.setFocusMode(root.selectionAdapter?root.selectionAdapter.resolveFocusMode(mode):mode);root.close();return true
            }
            function move(dx,dy) {
                if (currentIndex<0) { updateCurrentIndex();return }
                var col=currentIndex%columns,row=Math.floor(currentIndex/columns)
                var nextCol=col+dx,nextRow=row+dy
                if (nextCol<0 || nextCol>=columns || nextRow<0 || nextRow>=rowCount) return
                var next=nextRow*columns+nextCol
                if (next<count && root.focusModeModel[next].valid) currentIndex=next
            }
            function incrementIndex() { move(1,0) }
            function decrementIndex() { move(-1,0) }
            Repeater {
                model: root.focusModeModel
                delegate: FocusScope {
                    required property var modelData
                    required property int index
                    objectName: "X2dFocusCell_"+index
                    width: choices.cellWidth; height: choices.cellHeight
                    focus: choices.currentIndex===index
                    FramedImage {
                        objectName: "X2dStockFocusImage_"+index
                        anchors.top: parent.top
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width
                        text: qsTranslate("FocusModes",modelData.text)
                        textColor: Constants.popupTextColor
                        textPixelSize: 18*1.6*Constants.scaleFactor
                        textTopMargin: 8*1.6*Constants.scaleFactorY
                        selectable: modelData.valid
                        touchEnabled: modelData.valid
                        focus: choices.currentIndex===index
                        source: modelData.icon
                        highlightWidth: 91*1.6*Constants.scaleFactorX
                        highlightHeight: 60*1.6*Constants.scaleFactorY
                        onPressed: { choices.currentIndex=index;choices.setSelected() }
                    }
                }
            }
        }
    }
    Component.onCompleted: choices.updateCurrentIndex()
}
