import QtQuick
import com.hasselblad.types
import com.hasselblad.proxies
import com.hasselblad.uiproxies
import "qrc:/app/qml/components" as StockComponents

// Runtime model experiment. This never writes /proc/mem or camera files.
// It is deliberately fail-closed until an exact two-item stock model and
// CameraUI.canChangeAfc are visible through ControlDrawer.
Item {
    id: root
    objectName: "X2dAfcMenuController"
    visible: false
    width: 0
    height: 0

    property var controlViewModel: null
    property bool focusPopoverOpen: false
    property var focusPopover: null
    property var uiRoot: null
    property var controlRoot: null
    property var popupLoader: null
    property url extendedPopupSource: "file:///system/etc/X2dFocusModePopup.qml"
    property string focusTitle: "對焦模式"
    property string afsCaption: "單次自動對焦"
    property string mfCaption: "手動對焦"
    property var stockAfs: null
    property var stockMf: null
    property var afcItem: null
    property bool trackingReady: false
    function resolveFocusMode(mode){
        if(mode===HblmTypes.E_FocusModes_Afc && trackingReady && Camera.face_detection===HblmTypes.E_FaceDetection_Multi)return aftFocusMode
        return mode
    }
    property bool afcAvailable: false
    readonly property int aftFocusMode: 6
    property var extendedAfs: null
    property var extendedMf: null
    property var visualBindings: []
    property bool loaded: false
    property bool busy: false
    property bool faulted: false
    property string statusMessage: "AF-C 尚未開啟"
    readonly property bool ready: !faulted && controlViewModel !== null && CameraUI.canChangeAfc
    signal result(bool loaded, bool busy, string message)

    Component {
        id: afsFactory
        StockComponents.FocusModeListItem {
            focusMode: HblmTypes.E_FocusModes_Afs
            valid: root.stockAfs ? root.stockAfs.valid : false
            icon: "image://svg/ic_x2d2_focus_control_AF-S"
            text: root.afsCaption
        }
    }
    Component {
        id: mfFactory
        StockComponents.FocusModeListItem {
            focusMode: HblmTypes.E_FocusModes_Man
            valid: root.stockMf ? root.stockMf.valid : false
            icon: "image://svg/ic_x2d2_focus_control_MF"
            text: root.mfCaption
        }
    }
    Component {
        id: afcFactory
        StockComponents.FocusModeListItem {
            focusMode: HblmTypes.E_FocusModes_Afc
            valid: root.afcAvailable && CameraUI.canChangeAfc
            icon: "image://svg/ic_x2d2_focus_control_AF-C"
            text: "連續自動對焦"
        }
    }
    function modeName(mode) {
        if (mode === HblmTypes.E_FocusModes_Afs) return "AF-S"
        if (mode === HblmTypes.E_FocusModes_Afc) return "AF-C"
        if (mode === HblmTypes.E_FocusModes_Man) return "MF"
        if (mode === aftFocusMode) return "AF-C"
        return ""
    }
    function modeIcon(mode, liveview) {
        var name = modeName(mode)
        if (!name) return ""
        return "image://svg/ic_x2d2_" + (liveview ? "liveview_" : "focus_control_") + name +
                (CameraUI.focusModeSelectable ? "" : liveview ? "_disable" : "_disabled")
    }
    // Binding restores the original binding (including future mode/lens
    // changes), rather than saving a stale icon or visibility value.
    Component {
        id: controlBindingFactory
        Item {
            id: controlBinding
            property var item: null
            Binding {
                target: controlBinding.item
                property: "symbol"
                value: root.modeIcon(Camera.focus_mode, false) || root.controlViewModel.focusModeIcon
                when: (root.loaded || Camera.focus_mode === root.aftFocusMode) && controlBinding.item !== null
                restoreMode: Binding.RestoreBindingOrValue
            }
        }
    }
    Component {
        id: liveviewBindingFactory
        Item {
            id: liveBinding
            property var item: null
            property var icon: item ? item.children[0] : null
            Binding {
                target: liveBinding.icon; property: "source"
                value: liveBinding.item ? (root.modeIcon(liveBinding.item.viewModel.focusMode, true) ||
                                           liveBinding.item.viewModel.focusModeIcon) : ""
                when: (root.loaded || (liveBinding.item && liveBinding.item.viewModel.focusMode === root.aftFocusMode)) && liveBinding.item !== null
                restoreMode: Binding.RestoreBindingOrValue
            }
            Binding {
                target: liveBinding.icon; property: "scaleFactor"
                // Stock AF-T is control-screen artwork (44 logical px high),
                // whereas the accepted liveview badges are 24 px high. Keep
                // the original SVG and scale only AFT in the stock ScaledImage.
                value: 1
                when: (root.loaded || (liveBinding.item && liveBinding.item.viewModel.focusMode === root.aftFocusMode)) && liveBinding.item !== null &&
                      liveBinding.item.viewModel.focusMode === root.aftFocusMode &&
                      liveBinding.icon !== null
                restoreMode: Binding.RestoreBindingOrValue
            }
            Binding {
                target: liveBinding.icon; property: "visible"
                value: liveBinding.item ? liveBinding.item.viewModel.canShowFocusMode : false
                when: (root.loaded || (liveBinding.item && liveBinding.item.viewModel.focusMode === root.aftFocusMode)) && liveBinding.item !== null
                restoreMode: Binding.RestoreBindingOrValue
            }
            Binding {
                target: liveBinding.item; property: "visible"
                value: liveBinding.item !== null && (liveBinding.item.viewModel.canShowFocusMode || liveBinding.item.showIndicators) &&
                       !liveBinding.item.parent.overlayOff && liveBinding.item.parent.infoVisible &&
                       !liveBinding.item.parent.showOnlyBottomRow
                when: (root.loaded || (liveBinding.item && liveBinding.item.viewModel.focusMode === root.aftFocusMode)) && liveBinding.item !== null
                restoreMode: Binding.RestoreBindingOrValue
            }
        }
    }
    function bindVisual(item, factory) {
        for (var i = 0; i < visualBindings.length; ++i)
            if (visualBindings[i].item === item) return
        var binding = factory.createObject(root, {item: item})
        if (binding) visualBindings.push(binding)
    }
    function discover(item, controls) {
        if (!item) return
        if (controls && item.objectName === "ControlScreen_popupLoader") popupLoader = item
        if (controls && item.objectName === "ControlScreen_afControl" && typeof item.symbol !== "undefined")
            bindVisual(item, controlBindingFactory)
        if (item.objectName === "FocusIndicator_root" && item.viewModel && item.children.length >= 2 &&
                typeof item.children[0].source !== "undefined" && item.parent &&
                typeof item.parent.overlayOff === "boolean")
            bindVisual(item, liveviewBindingFactory)
        for (var i = 0; i < item.children.length; ++i) discover(item.children[i], controls)
    }
    function refreshUi() {
        if (!uiRoot && !controlRoot) return
        discover(uiRoot, false)
        discover(controlRoot || uiRoot, true)
        routeFocusPopup()
    }
    function routeFocusPopup() {
        if (faulted || !loaded || !popupLoader || !controlViewModel || controlViewModel.mainState !== "focus_mode") return
        var source = popupLoader.source.toString()
        if (source.indexOf("/popups/PopoverFocusMode.qml") !== -1)
            popupLoader.source = extendedPopupSource
    }
    Connections {
        target: root.popupLoader
        function onSourceChanged() { root.routeFocusPopup() }
        function onStatusChanged() {
            if (root.loaded && root.popupLoader && root.popupLoader.status===Loader.Error &&
                    root.popupLoader.source.toString()===root.extendedPopupSource.toString()) {
                // Exit the failed modal state; keep original model objects
                // alive rather than deleting an object referenced by the UI.
                root.faulted=true
                var failedLoader=root.popupLoader,failedVm=root.controlViewModel
                // Loader.Error may be emitted inside the stock StateGroup's
                // enter script. Defer withdrawal until that transition ends.
                Qt.callLater(function() {
                    if (root.popupLoader===failedLoader && root.controlViewModel===failedVm &&
                            failedVm && failedVm.mainState==="focus_mode" &&
                            typeof failedVm.clearMainState==="function")
                        failedVm.clearMainState("focus_mode")
                })
                root.publish("对焦弹窗加载失败，正在退出；扩展弹窗已停用，请使用恢复原状")
            }
        }
        function onLoaded() {
            if (root.loaded && root.popupLoader.source.toString() === root.extendedPopupSource.toString())
                {
                root.popupLoader.item.heading = root.focusTitle
                root.popupLoader.item.selectionAdapter=root
            }
        }
    }
    Timer { interval: 5000; repeat: true; running: root.uiRoot !== null; onTriggered: root.refreshUi() }
    onUiRootChanged: Qt.callLater(refreshUi)
    onControlRootChanged: Qt.callLater(refreshUi)
    function clearExtendedItems() {
        // Keep Binding objects alive while their `when` becomes false. Qt
        // restores the saved binding then; destroying one immediately after
        // changing loaded can discard that restoration on Qt 6.4.1.
        popupLoader = null
        if (extendedAfs) extendedAfs.destroy()
        if (afcItem) afcItem.destroy()
        if (extendedMf) extendedMf.destroy()
        extendedAfs = null; afcItem = null; extendedMf = null
    }

    function sameModel(items) {
        if (!controlViewModel || controlViewModel.focusModeModel.length !== items.length)
            return false
        for (var i = 0; i < items.length; ++i) {
            if (controlViewModel.focusModeModel[i] !== items[i])
                return false
        }
        return true
    }

    function replaceModel(items) {
        // A list property is mutable in QML. Read back every entry: a silent
        // append/conversion must never be reported as a successful switch.
        controlViewModel.focusModeModel.length = 0
        for (var i = 0; i < items.length; ++i)
            controlViewModel.focusModeModel.push(items[i])
        return sameModel(items)
    }

    function publish(message) {
        statusMessage = message
        result(loaded, busy, message)
    }

    function extendedItems() {
        var items=[extendedAfs]
        if (afcAvailable) items.push(afcItem)
        // AFT is the internal face-tracking path of AF-C, never a separate item.
        items.push(extendedMf)
        return items
    }
    function setEnabled(enable) { return setFeatures(enable,false) }
    function setFeatures(afc, legacyAft) {
        // The second argument is retained for old callers; AF-C is the sole availability switch.
        var enable=!!afc
        if (busy || faulted)
            return false
        if (enable === loaded && afc===afcAvailable) {
            publish(loaded ? "AF-C 菜單擴展已加載" : "AF-C 尚未開啟")
            return true
        }
        if (enable && !ready) {
            publish("AF-C 條件未滿足，未加載")
            return false
        }
        if (focusPopoverOpen) {
            publish("請先關閉對焦模式彈窗")
            return false
        }
        if ((!afc && Camera.focus_mode === HblmTypes.E_FocusModes_Afc) ||
            (!afc && Camera.focus_mode === aftFocusMode)) {
            publish("請先切換到 AF-S 或 MF，再關閉實驗室功能")
            return false
        }
        if (loaded && !sameModel(extendedItems())) {
            publish("對焦列表被其他代碼修改，拒絕卸載")
            return false
        }

        busy = true
        var didMutate = false
        try {
            if (loaded) {
                didMutate=true
                if (!replaceModel([stockAfs,stockMf])) throw new Error("恢復原廠兩項後回讀不一致")
                loaded=false;clearExtendedItems()
            }
            afcAvailable=afc
            if (enable) {
                var model = controlViewModel.focusModeModel
                if (model.length !== 2 ||
                    model[0].focusMode !== HblmTypes.E_FocusModes_Afs ||
                    model[1].focusMode !== HblmTypes.E_FocusModes_Man) {
                    throw new Error("原廠對焦列表不是預期的 AF-S/MF 兩項")
                }
                stockAfs = model[0]
                stockMf = model[1]
                // Never rewrite stock captions/icons; their validity bindings
                // and translation context remain available for exact restore.
                extendedAfs = afsFactory.createObject(root)
                if (afc) afcItem = afcFactory.createObject(root)
                extendedMf = mfFactory.createObject(root)
                didMutate = true
                if (!extendedAfs || !extendedMf || (afc && !afcItem) ||
                        !replaceModel(extendedItems()))
                    throw new Error("AF-C 條目插入後回讀不一致")
                loaded = true
                refreshUi()
                publish("AF-C 菜單擴展已加載")
            } else {
                didMutate = true
                if (!replaceModel([stockAfs, stockMf]))
                    throw new Error("恢復原廠兩項後回讀不一致")
                loaded = false
                afcAvailable=false
                clearExtendedItems()
                publish("AF-C 尚未開啟")
            }
            return true
        } catch (error) {
            // Keep the AF-C object alive if the list still references it.
            // A failed rollback is reported, never shown as OFF.
            if (didMutate && stockAfs && stockMf) {
                try {
                    if (replaceModel([stockAfs, stockMf])) {
                        loaded = false
                        afcAvailable=false
                        clearExtendedItems()
                    } else {
                        faulted = true
                    }
                } catch (recoveryError) {
                    faulted = true
                }
            }
            publish(faulted ? "對焦列表狀態不確定；請重啟 GUI：" + error :
                    didMutate ? "切換未生效，已恢復原廠列表：" + error :
                                "未加載：" + error)
            return false
        } finally {
            busy = false
            result(loaded, busy, statusMessage)
        }
    }
}
