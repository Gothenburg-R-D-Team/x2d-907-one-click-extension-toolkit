import QtQuick
import com.hasselblad.constants
import com.hasselblad.types
import com.hasselblad.keys
import "qrc:/app/qml/popups" as Stock
import "qrc:/app/qml/scripts/Keys.js" as MKeys
import "X2dSubjectPolicy.js" as Policy

// Compatible with the first-generation stock ControlScreen loader contract.
// Unsupported tiles are focusable placeholders, never camera modes.
Stock.Popover {
    id: root
    objectName: "PopoverFaceDetection_root"
    property var faceDetectionModel: []
    property var presentationState: null
    readonly property var area: presentationState ? presentationState.area : null
    readonly property bool areaAvailable: area!==null
    function toggleNearby(){if(presentationState)presentationState.nearbyFaces=!presentationState.nearbyFaces}

    property int localFocusIndex: 0
    property int localSubjectIndex: -1
    readonly property int selectedFocusIndex: presentationState ? presentationState.selectedFocusIndex : localFocusIndex
    readonly property int selectedSubjectIndex: presentationState ? presentationState.displayedSubjectIndex :
        localSubjectIndex >= 4 ? localSubjectIndex : faceDetection === HblmTypes.E_FaceDetection_Off ? 7 : 4
    property int faceDetection: HblmTypes.E_FaceDetection_Off
    property bool canChangeFaceDetection: false
    readonly property int keyOverride: HblmTypes.E_CameraKeyOption_OverrideHalfPress
    property int cursorIndex: faceDetection === HblmTypes.E_FaceDetection_Off ? 7 : 4
    property string notice: ""
    property string subjectTitle: "Subject Detection"
    property string unlockCaption: "Please purchase X2D2 to unlock this feature"
    property string unavailableCaption: "Human detection is unavailable in the current state"
    property var captions: ["Spot", "Expand Spot", "Custom", "Wide", "Human", "Cat/Dog", "Vehicle", "Off"]
    readonly property var artwork: ["spot", "spot-plus", "custom", "wide", "human", "pet", "vehicle", "off"]
    signal setFaceDetection(int val)

    heading: "Focus Point"
    contentWidth: 798 * Constants.scaleFactorX
    contentHeight: 650 * Constants.scaleFactorY
    headingSize: 28 * Constants.scaleFactor
    handleDefaultKeys: false
    contentItem: acceptHelper
    clickedHandler: function() { root.close(); return false }
    onCanChangeFaceDetectionChanged: { if (!canChangeFaceDetection) root.close() }
    onFaceDetectionChanged: { localSubjectIndex = -1; notice = "" }

    function remember(index) {
        if (presentationState) presentationState.rememberChoice(index)
        else if (index < 4) localFocusIndex = index
        else localSubjectIndex = index
    }

    function personMode() {
        return Policy.personMode(faceDetectionModel, HblmTypes.E_FaceDetection_Multi)
    }
    function focusChoice(index) {
        cursorIndex = Math.max(0, Math.min(7, index))
        notice = Policy.isUnsupported(cursorIndex,root.areaAvailable) ? unlockCaption : ""
    }
    function choose(index) {
        if (index < 0 || index > 7) return
        focusChoice(index)
        if (Policy.isUnsupported(index,root.areaAvailable)) { if(!root.areaAvailable || index>=4)remember(index); return }
        if (index < 3) {
            if(!root.areaAvailable){if(index===0)remember(index);return}
            if(root.area.select(index))remember(index)
            notice=root.area.notice
            return
        }
        if (!canChangeFaceDetection) return
        var mode = index === 4 ? personMode() : HblmTypes.E_FaceDetection_Off
        if (mode < 0 || !Policy.available(faceDetectionModel, mode)) {
            notice = unavailableCaption
            return
        }
        root.setFaceDetection(mode)
        remember(index)
    }
    Keys.onPressed: (event) => {
        // Dismiss without selecting a tile or consuming the stock half-press.
        // The stock closePopup connection clears face_detection; the original
        // key handler still receives this event and returns to live view.
        if (MKeys.pressedFn(KeyFn.HalfPress, event)) {
            root.close()
            event.accepted = false
            return
        }
        if (MKeys.pressedFnAcc(KeyFn.NavLeft, event)) focusChoice(cursorIndex - 1)
        else if (MKeys.pressedFnAcc(KeyFn.NavRight, event)) focusChoice(cursorIndex + 1)
        else if (MKeys.pressedFnAcc(KeyFn.Up, event)) focusChoice(cursorIndex - 4)
        else if (MKeys.pressedFnAcc(KeyFn.Down, event)) focusChoice(cursorIndex + 4)
        else if (MKeys.pressedFnListAcc([KeyFn.PopAccept, KeyFn.FaceDetection], event)) choose(cursorIndex)
        else if (MKeys.pressedFnListAcc([KeyFn.Abort, KeyFn.Menu, KeyFn.Browse], event)) close()
        else event.accepted = false
    }
    Item {
        id: acceptHelper
        function setSelected() { root.choose(root.cursorIndex) }
    }
    content: Item {
        id: body
        anchors.fill: parent
        readonly property real rowHeight: 210 * Constants.scaleFactorY
        readonly property real inset: 36 * Constants.scaleFactorX
        Rectangle {
            anchors.left: parent.left; anchors.right: parent.right
            y: body.rowHeight
            height: Constants.popupBorderWidth
            color: Constants.popupBorderColor
        }
        Text {
            y: body.rowHeight; width: parent.width; height: 64 * Constants.scaleFactorY
            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
            text: root.subjectTitle; color: Constants.popupTextColor
            font.pixelSize: 28 * Constants.scaleFactor; font.weight: Font.Medium
        }
        Repeater {
            model: 8
            delegate: Item {
                id: tile
                required property int index
                readonly property bool unsupported: Policy.isUnsupported(index,root.areaAvailable)
                readonly property bool activeChoice: Policy.selected(index, root.selectedFocusIndex, root.selectedSubjectIndex)
                x: body.inset + (index % 4) * width
                y: (index < 4 ? 32 : 306) * Constants.scaleFactorY
                width: (body.width - 2 * body.inset) / 4
                height: 156 * Constants.scaleFactorY
                Rectangle {
                    id: highlight
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 104 * Constants.scaleFactorX; height: 82 * Constants.scaleFactorY
                    color: tile.activeChoice && !tile.unsupported ? Constants.hblOrange : "transparent"
                    objectName: "X2dSubjectSelectionFrame_" + tile.index
                    readonly property bool selected: tile.activeChoice
                    border.color: tile.activeChoice ? Constants.hblOrange : "transparent"
                    border.width: Constants.popupBorderWidth
                    Rectangle {
                        anchors.fill: parent; anchors.margins: -6 * Constants.scaleFactor
                        color: "transparent"; border.width: Constants.popupBorderWidth
                        border.color: "#888888"
                        visible: root.cursorIndex === tile.index && !tile.activeChoice
                    }
                }
                Image {
                    anchors.centerIn: highlight
                    width: 70 * Constants.scaleFactorX; height: 70 * Constants.scaleFactorY
                    fillMode: Image.PreserveAspectFit
                    source: "file:///system/etc/X2dSubject-" + root.artwork[tile.index] + ".svg"
                    opacity: tile.unsupported ? 0.32 : 1
                    asynchronous: false
                }
                Text {
                    anchors.top: highlight.bottom; anchors.topMargin: 16 * Constants.scaleFactorY
                    width: parent.width; horizontalAlignment: Text.AlignHCenter
                    color: Constants.popupTextColor; opacity: tile.unsupported ? 0.32 : 1
                    font.pixelSize: 28 * Constants.scaleFactor
                    text: root.captions[tile.index]
                }
                MouseArea {
                    anchors.fill: parent
                    // Gray is deliberately still selectable. choose() denies camera writes.
                    onClicked: root.choose(tile.index)
                }
            }
        }
        Rectangle {
            objectName:"X2dNearbyFacePrioritySwitch"
            anchors.horizontalCenter:parent.horizontalCenter;y:474*Constants.scaleFactorY
            width:470*Constants.scaleFactorX;height:36*Constants.scaleFactorY;color:"#252525";border.color:"#555555"
            Text {anchors.centerIn:parent;color:"white";font.pixelSize:18*Constants.scaleFactor
                text:(root.presentationState && root.presentationState.nearbyFaces?"✓ ":"○ ")+"People: prefer nearby (full-frame detection)"}
            MouseArea {anchors.fill:parent;onClicked:root.toggleNearby()}
        }
        Text {
            objectName: "X2dSubjectDetection_notice"
            anchors.bottom: parent.bottom; anchors.bottomMargin: 14 * Constants.scaleFactorY
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - 40 * Constants.scaleFactorX
            horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
            color: Constants.popupTextColor; opacity: 0.6
            font.pixelSize: 20 * Constants.scaleFactor
            text: root.notice
        }
    }
}
