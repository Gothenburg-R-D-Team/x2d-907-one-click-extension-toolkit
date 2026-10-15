import QtQuick
import com.hasselblad.types
import com.hasselblad.constants
import "X2dSubjectPolicy.js" as Policy

// Reuses stock capability gates, signals and modal state. No GUI binary patch.
Item {
    id: root
    visible: false
    width: 0; height: 0
    property var controlRoot: null
    property var viewModel: null
    property bool attached: false
    property bool installed: false
    property bool menuEnabled: false
    property bool faulted: false
    property var control: null
    property var loader: null
    property var iconItem: null
    property var uiRoot: null
    property var liveBindings: []
    Component {
        id: liveBindingFactory
        Item {
            id: live
            property var overlay: null
            property var stockIcon: null
            anchors.fill: parent
            Binding {
                target: live.stockIcon; property: "visible"
                value: false
                when: root.active && live.stockIcon !== null
                restoreMode: Binding.RestoreBindingOrValue
            }
            Image {
                objectName: "X2dSubjectLiveBadge"
                width: 48 * Constants.scaleFactorX
                height: 48 * Constants.scaleFactorY
                anchors.right: parent.right
                anchors.rightMargin: live.overlay ? live.overlay.borderMarginX : 0
                y: parent.height * 0.32
                source: "file:///system/etc/X2dSubject-live-human.svg"
                fillMode: Image.PreserveAspectFit
                asynchronous: false
                visible: root.active && live.overlay !== null && live.overlay.viewModel !== null &&
                    live.overlay.viewModel.faceDetection !== HblmTypes.E_FaceDetection_Off &&
                    live.overlay.viewModel.faceDetectionIcon !== "" && live.overlay.infoVisible &&
                    !live.overlay.overlayOff && !live.overlay.showOnlyBottomRow
            }
        }
    }
    function discoverLive(item) {
        if (!item) return
        if (item.objectName === "LiveViewOverlay_root" && item.viewModel) {
            for (var i=0; i<liveBindings.length; ++i)
                if (liveBindings[i] && liveBindings[i].overlay === item) return
            var stock = null
            for (var j=0; j<item.children.length; ++j) {
                var child=item.children[j]
                if (typeof child.source !== "undefined" &&
                    (child.source.toString().indexOf("image://svg/ic_liveview_face_detection_") === 0 ||
                     (j+1<item.children.length && item.children[j+1].objectName === "FocusIndicator_root")))
                    stock=child
            }
            if (stock) {
                var binding=liveBindingFactory.createObject(item,{overlay:item,stockIcon:stock})
                if (binding) liveBindings.push(binding)
            }
        }
        for (var k=0; k<item.children.length; ++k) discoverLive(item.children[k])
    }
    property var area: null
    property bool nearbyFaces: false
    property var faceFrames: null
    function attachFrames(){
        if(!active || !uiRoot || faceFrames)return
        var component=Qt.createComponent("file:///system/etc/X2dFaceFrames.qml")
        if(component.status!==Component.Ready)return
        faceFrames=component.createObject(root,{uiRoot:uiRoot,
            active:Qt.binding(function(){return root.active}),
            focusIndex:Qt.binding(function(){return root.selectedFocusIndex}),
            nearbyPriority:Qt.binding(function(){return root.nearbyFaces})})
    }
    property int selectedFocusIndex: 0
    property int selectedSubjectIndex: -1
    readonly property int displayedSubjectIndex: selectedSubjectIndex >= 4 ? selectedSubjectIndex :
        viewModel && viewModel.faceDetection === HblmTypes.E_FaceDetection_Off ? 7 : 4
    readonly property bool previewGray: Policy.grayCombination(selectedFocusIndex, displayedSubjectIndex,area!==null)
    readonly property url popupSource: "file:///system/etc/X2dSubjectDetectionPopup.qml"
    readonly property bool active: attached && installed && menuEnabled && !faulted && viewModel !== null
    Binding {
        target: root.control; property: "symbolScale"
        // Stock ScaledImage requests 160 px at scaleFactor=1. A file SVG uses
        // that as pixels (unlike the stock percentage-based SVG provider).
        value: 70 / 160
        when: root.active && root.control !== null
        restoreMode: Binding.RestoreBindingOrValue
    }
    Binding {
        target: root.control; property: "symbol"
        value: "file:///system/etc/X2dSubject-control-" +
               (!root.viewModel || !root.viewModel.canChangeFaceDetection ? "disabled" :
                Policy.controlArtwork(root.selectedFocusIndex, root.displayedSubjectIndex)) + ".svg"
        when: root.active && root.control !== null
        restoreMode: Binding.RestoreBindingOrValue
    }
    Binding {
        target: root.iconItem; property: "opacity"
        value: (root.previewGray ? 0.32 : 1) * (root.control ? root.control.blinkOpacity : 1)
        when: root.active && root.iconItem !== null
        restoreMode: Binding.RestoreBindingOrValue
    }
    function rememberChoice(index) {
        if (index < 0 || index > 7) return
        if (index < 4) selectedFocusIndex = index
        else selectedSubjectIndex = index
    }
    function findSymbol(item) {
        if (!item || !control) return null
        if (typeof item.source !== "undefined" && item.source.toString() === control.symbol.toString()) return item
        for (var i = 0; i < item.children.length; ++i) {
            var result = findSymbol(item.children[i])
            if (result) return result
        }
        return null
    }
    function find(item, name) {
        if (!item) return null
        if (item.objectName === name) return item
        for (var i = 0; i < item.children.length; ++i) {
            var result = find(item.children[i], name)
            if (result) return result
        }
        return null
    }
    function refresh() {
        if (!active) return
        attachFrames()
        liveBindings = liveBindings.filter(function(binding) { return binding && binding.overlay })
        if (!control) control = find(controlRoot, "ControlScreen_faceDetectionControl")
        if (!iconItem) iconItem = findSymbol(control)
        if (!loader) loader = find(controlRoot, "ControlScreen_popupLoader")
        discoverLive(uiRoot || controlRoot)
        route()
    }
    function route() {
        if (!active || !loader || viewModel.mainState !== "face_detection") return
        if (loader.source.toString().indexOf("/popups/PopoverFaceDetection.qml") !== -1)
            loader.source = popupSource
    }
    Connections {
        target: root.viewModel
        function onMainStateChanged() { root.refresh() }
        function onFaceDetectionChanged() { root.selectedSubjectIndex = -1; Qt.callLater(root.refresh) }
    }
    Connections {
        target: root.loader
        function onSourceChanged() { root.route() }
        function onLoaded() {
            if (root.active && root.loader && root.loader.item &&
                    root.loader.source.toString() === root.popupSource.toString())
                root.loader.item.presentationState = root
        }
        function onStatusChanged() {
            if (root.active && root.loader && root.loader.status === Loader.Error &&
                    root.loader.source.toString() === root.popupSource.toString()) {
                root.faulted = true
                var vm = root.viewModel
                Qt.callLater(function() {
                    if (vm && vm.mainState === "face_detection") vm.clearMainState("face_detection")
                })
                console.warn("X2D_SUBJECT_MENU_LOAD_FAILED_STOCK_RESTORED")
            }
        }
    }
    onAttachedChanged: { if (attached) Qt.callLater(refresh) }
    onActiveChanged: {
        if (active) Qt.callLater(refresh)
        else if (loader && loader.item && loader.source.toString() === popupSource.toString()) {
            // Withdraw only our popup; never replace other control-screen states.
            loader.item.close()
        }
    }
    onControlRootChanged: { if (attached) Qt.callLater(refresh) }
    onUiRootChanged: { if (attached) Qt.callLater(refresh) }
    Timer { interval: 5000; repeat: true; running: root.active; onTriggered: root.refresh() }
    Component.onDestruction: {
        installed = false
        for (var i=0; i<liveBindings.length; ++i)
            if (liveBindings[i]) liveBindings[i].destroy()
    }
}
