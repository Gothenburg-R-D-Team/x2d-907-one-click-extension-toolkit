import QtQuick
import com.hasselblad.keys
import "qrc:/app/qml/scripts/Keys.js" as MKeys

// 由 MainScreen 中新增的 Loader 创建，稍后挂到原厂 ControlDrawer。
Item {
    id: root
    objectName: "X2dNativeMenuExtension"
    anchors.fill: parent
    z: 20
    visible: route.playShowing
    enabled: visible
    property var screen: null
    property var drawer: null
    property var menu: null
    property var grid: null
    property var originalModel: null
    property Component originalDelegate: null
    property var originalLoader: null
    property var originalSwipe: null
    property var drawerList: null
    property var playButton: null
    property var prankButton: null
    property var focusPopup: null
    property var pixelBridge: null
    property var pixelComponent: null
    function attachPixelBridge() {
        if (pixelBridge || !attached || !(afcController.featureMask & 32) || !focusUiRoot) return
        var controlScreen=findItem(focusUiRoot,"ControlScreen_focusScope")
        var control=findItem(focusUiRoot,"ControlScreen_driveControl")
        if (!controlScreen || !control) return
        pixelComponent=Qt.createComponent("file:///system/etc/x2d-multishot/NativePixelControlBridge.qml")
        if (pixelComponent.status !== Component.Ready) return
        pixelBridge=pixelComponent.createObject(controlScreen,{controlScreen:controlScreen})
        if (pixelBridge) pixelBridge.attach(control)
    }
    Timer { interval:250; repeat:true; running:root.attached && !root.pixelBridge && (afcController.featureMask & 32); onTriggered:root.attachPixelBridge() }
    property var shutterBridge: null
    property var shutterComponent: null
    function attachShutterSound() {
        if (shutterBridge || !attached || !(afcController.featureMask & 128)) return
        shutterComponent=Qt.createComponent("file:///system/etc/x2d-shutter-sound/X2dShutterSoundCapture.qml")
        if (shutterComponent.status !== Component.Ready) return
        shutterBridge=shutterComponent.createObject(root)
        if (shutterBridge) afcController.shutterSound=shutterBridge.controller
    }
    Timer { interval:250;repeat:true;running:root.attached && !root.shutterBridge && (afcController.featureMask & 128);onTriggered:root.attachShutterSound() }
    property var focusAreaBridge: null
    function attachFocusAreas(){
        if(focusAreaBridge || !attached || !afcController.focusAreasInstalled)return
        var component=Qt.createComponent("file:///system/etc/X2dFocusAreaController.qml")
        if(component.status!==Component.Ready)return
        focusAreaBridge=component.createObject(root,{uiRoot:focusUiRoot,subject:subjectController,
            areaEnabled:Qt.binding(function(){return subjectController.active})})
        if(focusAreaBridge)subjectController.area=focusAreaBridge
    }
    Timer {interval:500;repeat:true;running:root.attached && afcController.focusAreasInstalled && !root.focusAreaBridge;onTriggered:root.attachFocusAreas()}
    property bool attached: false
    property int attachAttempts: 0
    Timer { interval:100; repeat:true; running:!root.attached && root.attachAttempts<120; onTriggered:{root.attachAttempts++;root.attach()} }
    property var focusUiRoot: null
    readonly property bool menuActive: attached && drawer.mainState === "main_menu"
                                      && drawer.mainViewState === "main_menu" && !drawer.drawerAtTop

    function findItem(item, name) {
        if (!item) return null
        if (item.objectName === name) return item
        for (var i = 0; i < item.children.length; ++i) {
            var result = findItem(item.children[i], name)
            if (result) return result
        }
        return null
    }
    function attach() {
        if (attached || !screen || !screen.mainMenu || !screen.viewModel) return
        menu = screen.mainMenu
        drawer = menu.parent
        if (!drawer || drawer.objectName !== "ControlDrawer_root") return
        grid = findItem(screen, "MainScreen_grid")
        originalLoader = findItem(menu, "menu_loader")
        originalSwipe = findItem(menu, "MainMenu_swipeArea")
        drawerList = findItem(drawer, "ControlDrawer_list")
        if (!grid || !originalLoader || !originalSwipe || !drawerList) return
        // ControlDrawer.onLoaded 原文把信号接到这个具名函数；不能仅旁听。
        try { screen.loadSubMenuItem.disconnect(menu.loadSubmenu) }
        catch (error) { console.warn("X2D_NATIVE_MENU_ROUTE_NOT_READY"); return }
        originalModel = screen.viewModel.favoriteModel
        adapter.sourceModel = originalModel
        originalDelegate = grid.delegate
        adapter.stockDelegate = originalDelegate
        screen.loadSubMenuItem.connect(dispatch)
        screen.viewModel.favoriteModel = adapter
        parent = drawer
        focusUiRoot = drawer
        while (focusUiRoot.parent) focusUiRoot = focusUiRoot.parent
        attached = true
        routeDisplaySettings()
        screen.viewModel.inMenu = Qt.binding(function() { return originalLoader.active || route.playShowing })
        screen.viewModel.preventSwipe = Qt.binding(function() { return originalSwipe.preventSwipe || route.playShowing })
        drawerList.interactive = Qt.binding(function() { return !drawerList.blockSwipe && !route.playShowing })
        console.info("X2D_NATIVE_MENU_ATTACHED")
    }
    function dispatch(name, sub, open, shortcut) { route.dispatch(name, sub, open, shortcut) }
    function refreshFocusPopup() {
        focusPopup = drawer && drawer.mainState === "focus_mode"
                   ? findItem(drawer, "PopoverFocusMode_root") : null
    }
    // Keep the stock Display model and submenu routing; replace only its rear slider.
    function routeDisplaySettings() {
        if (!attached || !originalLoader || !screen.viewModel.menu) return
        if ((afcController.featureMask & 128) &&
            screen.viewModel.menu.menuName === "exposureMenu" &&
            originalLoader.source.toString() === "qrc:/app/qml/mainmenu/SettingsGeneric.qml")
            originalLoader.source = "file:///system/etc/x2d-shutter-sound/X2dExposureSettings.qml"
        if (afcController.brightnessInstalled && screen.viewModel.menu.menuName === "displayMenu" &&
            originalLoader.source.toString() === "qrc:/app/qml/mainmenu/SettingsGeneric.qml")
            originalLoader.source = "file:///system/etc/X2dDisplaySettings.qml"
    }
    Connections {
        target: root.originalLoader
        function onSourceChanged() { Qt.callLater(root.routeDisplaySettings) }
    }
    Connections {
        target: afcController
        function onBrightnessInstalledChanged() { Qt.callLater(root.routeDisplaySettings) }
        function onFeatureMaskChanged() { Qt.callLater(root.attachPixelBridge); Qt.callLater(root.attachShutterSound); Qt.callLater(root.routeDisplaySettings) }
    }
    Connections {
        target: root.screen && root.screen.viewModel ? root.screen.viewModel.menu : null
        ignoreUnknownSignals: true
        function onMenuNameChanged() { Qt.callLater(root.routeDisplaySettings) }
    }
    function refreshPlayButton() {
        playButton = attached && adapter.extensionPresent && grid.count === adapter.items.count
                    ? findItem(grid.itemAtIndex(adapter.extensionIndex), "FramedItem_root") : null
        prankButton = attached && adapter.prankPresent && grid.count === adapter.items.count
                    ? findItem(grid.itemAtIndex(adapter.prankIndex), "FramedItem_root") : null
    }
    property string reportedMenuState: ""
    property int menuReportTick: 0
    function reportMenuState() {
        if (!attached) return
        var state = playButton !== null && adapter.extensionPresent && (!adapter.prankPresent || prankButton !== null) ? "menu_ready_" + grid.count : "menu_unavailable"
        // A service restart removes its volatile marker. Refresh the receipt
        // even when the already-visible menu has not changed.
        menuReportTick += 1
        if (state === reportedMenuState && menuReportTick < 5) return
        menuReportTick = 0
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
                try { if (JSON.parse(xhr.responseText).menuAcknowledged) root.reportedMenuState = state }
                catch (error) {}
            }
        }
        xhr.open("POST", "http://127.0.0.1:18763/" + state)
        xhr.send()
    }
    Timer { interval: 1000; repeat: true; running: root.attached; onTriggered: root.reportMenuState() }
    function detach() {
        if (!attached) return
        route.dismiss()
        if (shutterBridge) { shutterBridge.destroy(); shutterBridge=null; afcController.shutterSound=null }
        if (pixelBridge) { pixelBridge.destroy(); pixelBridge=null }
        screen.loadSubMenuItem.disconnect(dispatch)
        screen.loadSubMenuItem.connect(menu.loadSubmenu)
        screen.viewModel.favoriteModel = originalModel
        grid.delegate = originalDelegate
        screen.viewModel.inMenu = Qt.binding(function() { return originalLoader.active })
        screen.viewModel.preventSwipe = Qt.binding(function() { return originalSwipe.preventSwipe })
        drawerList.interactive = Qt.binding(function() { return !drawerList.blockSwipe })
        attached = false
        playButton = null
    }
    X2dNativeMenuModel {
        id: adapter
        supportedLayout: root.screen !== null && !root.screen.viewModel.sparseFavoritesGrid
        playLabel: "Laboratory Features"
        playIcon: "file:///system/etc/X2dPlayIcon"
        prankEnabled: afcController.prankIbis
        onExtensionPresentChanged: Qt.callLater(root.refreshPlayButton)
        onPrankPresentChanged: Qt.callLater(root.refreshPlayButton)
    }
    // 未解析的扩展项没有源模型 index。原厂 onPressed 使用该值会恢复旧高亮；
    // 在同次 pressed 信号内用实际显示位置纠正，保留原厂按钮和高亮计时逻辑。
    Connections {
        target: root.playButton
        function onPressed() {
            if (root.attached && adapter.extensionPresent && root.playButton.selectable)
                root.grid.highlightIndex(adapter.extensionIndex)
        }
    }
    Connections {
        target: root.prankButton
        function onPressed() {
            if (root.attached && adapter.prankPresent && root.prankButton.selectable)
                root.grid.highlightIndex(adapter.prankIndex)
        }
    }
    Connections {
        target: root.grid
        function onCountChanged() { Qt.callLater(root.refreshPlayButton) }
    }
    Connections {
        target: root.grid ? root.grid.contentItem : null
        function onChildrenChanged() { Qt.callLater(root.refreshPlayButton) }
    }
    // 消费页面空白处触摸；半按等未处理按键继续交给原厂。
    MouseArea { anchors.fill: parent; onPressed: (mouse) => { mouse.accepted = true } }
    X2dConnectionMenu {
        grid: root.grid
        menuModel: adapter
        active: root.attached && afcController.subjectMenuEnabled
    }
    X2dSubjectDetectionController {
        id: subjectController
        installed: afcController.subjectMenuInstalled
        menuEnabled: afcController.subjectMenuEnabled
        controlRoot: root.drawer
        uiRoot: root.focusUiRoot
        viewModel: root.drawer ? root.drawer.controlScreenViewModel : null
        attached: root.attached
    }
    X2dAfcMenuController {
        id: nativeAfcMenu
        trackingReady: afcController.ready && afcController.aftReady && afcController.aftActive && afcController.master && afcController.afcEnabled
        controlViewModel: root.drawer ? root.drawer.controlScreenViewModel : null
        focusPopoverOpen: root.drawer !== null && root.drawer.mainState === "focus_mode"
        focusPopover: root.focusPopup
        uiRoot: root.focusUiRoot
        controlRoot: root.drawer
    }
    X2dSpeedBuffController {
        id: afcController
        afcMenu: nativeAfcMenu
        subjectMenu: subjectController
    }
    X2dNativeMenuRoute {
        id: route
        anchors.fill: parent
        menuActive: root.menuActive
        mediaProcessing: root.screen !== null && root.screen.viewModel.mediaProcessing
        stockSubmenuActive: root.menu !== null && root.menu.state === "menu"
        featureController: afcController
        prankEnabled: adapter.prankPresent
        onStockRequested: (name, sub, open, shortcut) => root.menu.loadSubmenu(name, sub, open, shortcut)
        onMainMenuRequested: { if (root.menuActive) root.screen.forceActiveFocus() }
    }
    Connections {
        target: root.drawer
        function onMainStateChanged() {
            nativeAfcMenu.refreshUi()
            Qt.callLater(root.refreshFocusPopup)
        }
        function onMainMenuExited() { route.dismiss() }
    }
    Connections {
        target: root.screen ? root.screen.viewModel : null
        function onCloseMenu() { route.dismiss() }
    }
    Keys.onPressed: (event) => {
        if (route.playShowing && MKeys.pressedFnListAcc([KeyFn.Escape, KeyFn.JstkEscape, KeyFn.Menu], event))
            route.back()
        else if (route.playShowing && MKeys.pressedFnListAcc([KeyFn.NavKey, KeyFn.Square, KeyFn.Cross], event)) {}
        else event.accepted = false
    }
    Component.onCompleted: {
        screen = parent ? parent.parent : null
        Qt.callLater(attach)
    }
    Component.onDestruction: detach()
}
