/*
 * vim: tabstop=4 softtabstop=4 shiftwidth=4 expandtab fileencoding=utf-8
 * encoding: utf-8
 * -*- coding: utf-8 -*-
 *
 * Copyright 2020 Victor Hasselblad AB.
 *
 * All information contained in or disclosed by this document is confidential
 * and proprietary of Victor Hasselblad AB. By accepting this material the
 * recipient agrees that this material and the information contained therein
 * will be held in confidence and will not be reproduced in whole or in part
 * without written permission from Victor Hasselblad AB.
 */

import QtQuick
import "qrc:/app/qml/popups"
import "file:///system/etc/x2d-multishot/NativePixelControl.js" as PixelControl
import "file:///system/etc/x2d-multishot/NativePixelTrace.js" as PixelTrace
import com.hasselblad.proxies
import com.hasselblad.storage
import "qrc:/app/qml/components/buttons"

import com.hasselblad.constants
import com.hasselblad.menumodel
import com.hasselblad.types
import com.hasselblad.keys
import com.hasselblad.valueformatter

import "qrc:/app/qml/components"
import "qrc:/app/qml/mainmenu"
import "qrc:/app/qml/scripts/Keys.js" as MKeys

Popover {
    id: root
    objectName: "PopoverDriveMode_root"

    property MainMenuViewModel mainMenuViewModel: null
    property bool lensHasMicroFocusAdjust: false
    property int expMode: 0
    property int driveMode: 0
    readonly property bool pixelPage: grid.currentIndex >= 0 && gridModel.get(grid.currentIndex).drivemode === 6
    readonly property bool pixelCanChange: (Camera.can_change & 16) !== 0 &&
        (Camera.exposure_status & 1299) === 0 && expMode !== HblmTypes.E_ExpMode_FullAuto
    readonly property bool pixelCaptureOnly: true
    readonly property int pixelInitialDelay: pixelBackend.initialMs / 1000
    readonly property int pixelSoundLevel: pixelBackend.soundLevel
    property int pendingPixelSound: -1
    function choosePixelSound(level) {
        if (!pixelParametersReady || !pixelCanChange || pendingPixelMode || pendingPixelWait >= 0 || pendingPixelInitial >= 0 || pendingPixelSound >= 0 || [0,1,2,3].indexOf(level) < 0) return
        pendingPixelSound = level
        pixelMessage = "正在保存…"
        if (!pixelBackend.request("sound", level)) {
            pendingPixelSound = -1; pixelMessage = "未能保存，请重新选择"
        }
    }
    property int pendingPixelInitial: -1
    function choosePixelInitialDelay(seconds) {
        if (!pixelParametersReady || !pixelCanChange || pendingPixelMode || pendingPixelWait >= 0 || pendingPixelInitial >= 0 || pendingPixelSound >= 0 || !(seconds === 0 || (Number.isInteger(seconds) && seconds >= 2 && seconds <= 60))) return
        pendingPixelInitial = seconds * 1000
        pixelMessage = "正在保存…"
        if (!pixelBackend.request("initial", pendingPixelInitial)) {
            pendingPixelInitial = -1; pixelMessage = "未能保存，请重新选择"
        }
    }
    property var pixelControlBridge: null
    onPixelInitialDelayChanged: {
        if (pixelControlBridge) pixelControlBridge.initialDelayMs=root.pixelInitialDelay*1000
    }
    property bool pixelHalfExitRequested: false
    function finishPixelHalfExit() {
        if (pixelHalfExitRequested && pendingPixelMode === 0 && pendingPixelWait < 0 && pendingPixelInitial < 0 && root.pendingPixelSound < 0) {
            pixelHalfExitRequested = false
            returnPixelLiveview()
        }
    }
    function requestPixelLiveview() {
        pixelHalfExitRequested = true
        Qt.callLater(root.finishPixelHalfExit)
    }
    onPendingPixelModeChanged: Qt.callLater(root.finishPixelHalfExit)
    onPendingPixelWaitChanged: Qt.callLater(root.finishPixelHalfExit)
    onPendingPixelInitialChanged: Qt.callLater(root.finishPixelHalfExit)
    onPendingPixelSoundChanged: Qt.callLater(root.finishPixelHalfExit)
    function findPixelControl(item, name) {
        if (item.objectName === name) return item
        for (var i = 0; i < item.children.length; i++) {
            var found = findPixelControl(item.children[i], name)
            if (found) return found
        }
        return null
    }
    function attachPixelControl() {
        var screen = root.parent
        var chain = []
        while (screen && screen.objectName !== "ControlScreen_focusScope") { chain.push(screen.objectName); screen = screen.parent }
        PixelTrace.record("menu", "attach", {parents:chain,screen:!!screen,initial:root.pixelInitialDelay})
        if (!screen) return
        pixelControlBridge = findPixelControl(screen, "NativePixelControlBridge")
        if (pixelControlBridge) {
            pixelControlBridge.initialDelayMs=root.pixelInitialDelay*1000
            return
        }
        var control = findPixelControl(screen, "ControlScreen_driveControl")
        PixelTrace.record("menu", "control", {found:!!control})
        if (!control) return
        // A library context survives popup destruction in the camera's Qt 6.4.1.
        pixelControlBridge = PixelControl.create(screen)
        pixelControlBridge.initialDelayMs=root.pixelInitialDelay*1000
        pixelControlBridge.attach(control)
    }
    function returnPixelLiveview() {
        if (!pixelControlBridge) attachPixelControl()
        if (pixelControlBridge) pixelControlBridge.returnLiveview()
        root.closeDriveMode()
    }
    Keys.onPressed: (event) => {
        if (MKeys.pressedFnAcc(KeyFn.HalfPress, event)) root.requestPixelLiveview()
        else if (MKeys.pressedFnAcc(KeyFn.PopAccept, event)) grid.setSelected()
        else if (MKeys.pressedFnListAcc([KeyFn.NavLeft,KeyFn.Up],event)) grid.moveCurrentIndexLeft()
        else if (MKeys.pressedFnListAcc([KeyFn.NavRight,KeyFn.Down],event)) grid.moveCurrentIndexRight()
        else if (MKeys.pressedFnListAcc([KeyFn.Abort,KeyFn.Menu,KeyFn.Browse],event)) root.closeDriveMode()
        else event.accepted = false
    }

    property bool pixelModeAcknowledged: false
    property bool pixelWaitAcknowledged: false
    readonly property int pixelMode: pixelBackend.mode
    readonly property int pixelWait: pixelBackend.waitMs
    readonly property bool pixelParametersReady: pixelBackend.ready
    NativePixelBackend {
        id: pixelBackend
        polling: root.visible && root.pixelPage && root.pendingPixelMode === 0 && root.pendingPixelWait < 0 && root.pendingPixelInitial < 0 && root.pendingPixelSound < 0
        onCompleted: (kind, value, okay, reason) => {
            if (kind === "refresh") {
                if (!okay) root.pixelMessage = "读取失败，正在重试…"
                else if (root.pixelMessage === "读取失败，正在重试…") root.pixelMessage = ""
                return
            }
            if (kind === "initial" && root.pendingPixelInitial === value) {
                root.pendingPixelInitial = -1
                root.pixelMessage = okay ? "参数已保存" : "未能保存，请重新选择"
                return
            }
            if (kind === "sound" && root.pendingPixelSound === value) {
                root.pendingPixelSound = -1
                root.pixelMessage = okay ? "参数已保存" : "未能保存，请重新选择"
                return
            }
            if (okay) {
                if (kind === "mode" && root.pendingPixelMode === value) root.pixelModeAcknowledged = true
                if (kind === "wait" && root.pendingPixelWait === value) root.pixelWaitAcknowledged = true
                return
            }
            if (kind === "mode" && root.pendingPixelMode === value) {
                pixelAcknowledge.stop()
                root.cancelPixelPreparation(reason === "busy" ? "相机忙，请稍后选择" : "未能启用，请重新选择")
            } else if (kind === "wait" && root.pendingPixelWait === value) {
                waitAcknowledge.stop(); root.pendingPixelWait = -1
                root.pixelMessage = reason === "busy" ? "相机忙，请稍后选择" : "未能保存，请重新选择"
            }
        }
    }
    property int pendingPixelMode: 0
    property int previousPixelMode: 0
    property int pixelTicks: 0
    property string pixelMessage: ""
    property int previousPixelDrive: 0
    property int previousPixelFormat: 0
    property int previousPixelStorage: 0
    property int expectedPixelFormat: 0
    property int expectedPixelStorage: 0
    readonly property bool pixelRaw: [0,1,3].indexOf(Camera.image_format) >= 0
    readonly property bool pixelLocal: Storage.capture_storage_mode === 0 ||
                                      (Storage.capture_storage_mode & 1) !== 0
    readonly property bool pixelCaptureReady: pixelParametersReady && pendingPixelMode === 0 && Camera.drive_mode === 6 &&
        [1,2,3].indexOf(root.pixelMode) >= 0 && pixelBackend.frames === (root.pixelMode === 1 ? 4 : root.pixelMode === 2 ? 6 : 16) && pixelRaw && pixelLocal &&
        pixelBackend.suStatus !== 6
    function pixelFrames() {
        var m = root.pixelMode
        return pixelBackend.frames
    }
    function choosePixelMode(mode) {
        if (!pixelParametersReady) { pixelMessage = "正在读取参数…"; return }
        if (!pixelCanChange || pendingPixelMode || pendingPixelWait >= 0 || pendingPixelInitial >= 0 || pendingPixelSound >= 0 || [1,2,3].indexOf(mode) < 0) return
        if (pixelBackend.suStatus === 6) {
            pixelMessage = "请退出 USB 磁盘导出后再拍摄"; return
        }
        previousPixelMode = root.pixelMode
        previousPixelDrive = Camera.drive_mode
        previousPixelFormat = Camera.image_format
        previousPixelStorage = Storage.capture_storage_mode
        expectedPixelFormat = 0
        expectedPixelStorage = pixelLocal ? previousPixelStorage : (previousPixelStorage | 1)
        pixelModeAcknowledged = false
        pendingPixelMode = mode
        pixelTicks = 0
        pixelMessage = "正在设置 RAW 和本机保存…"
        if (Camera.image_format !== expectedPixelFormat) Camera.image_format = expectedPixelFormat
        if (Storage.capture_storage_mode !== expectedPixelStorage)
            Storage.capture_storage_mode = expectedPixelStorage
        if (!pixelBackend.request("mode", mode)) {
            cancelPixelPreparation("未能启用，请重新选择"); return
        }
        pixelAcknowledge.start()
    }
    function cancelPixelPreparation(message) {
        // Roll back only acknowledged values from this transaction, while idle.
        if ((Camera.exposure_status & 1299) === 0) {
            if (Camera.drive_mode === 6 && previousPixelDrive !== 6) root.setDriveMode(previousPixelDrive)
            if (pixelMode === pendingPixelMode && previousPixelMode !== pendingPixelMode)
                pixelBackend.request("mode", previousPixelMode)
            if (Camera.image_format === expectedPixelFormat && previousPixelFormat !== expectedPixelFormat)
                Camera.image_format = previousPixelFormat
            if (Storage.capture_storage_mode === expectedPixelStorage && previousPixelStorage !== expectedPixelStorage)
                Storage.capture_storage_mode = previousPixelStorage
        }
        pendingPixelMode = 0; pixelMessage = message
    }
    Timer {
        id: pixelAcknowledge; interval: 100; repeat: true
        onTriggered: {
            root.pixelTicks++
            if (!root.pixelCanChange) {
                stop(); root.cancelPixelPreparation("相机忙，请稍后选择")
                return
            }
            if (pixelBackend.suStatus === 6) {
                stop(); root.cancelPixelPreparation("请退出 USB 磁盘导出后再拍摄"); return
            }
            if (root.pixelModeAcknowledged && root.pixelMode === root.pendingPixelMode &&
                Camera.image_format === root.expectedPixelFormat &&
                Storage.capture_storage_mode === root.expectedPixelStorage &&
                root.pixelRaw && root.pixelLocal) {
                if (Camera.drive_mode !== 6) root.setDriveMode(6)
                else {
                    stop(); root.pendingPixelMode = 0
                    root.pixelMessage = "RAW 序列保存到相机，按机身快门开始拍摄"
                }
            }
            if (root.pixelTicks >= 30 && !pixelBackend.busy) {
                stop()
                root.cancelPixelPreparation("未能启用，请检查 RAW 和本机存储")
            }
        }
    }
    property int pendingPixelWait: -1
    property int waitTicks: 0
    function choosePixelWait(value) {
        if (!pixelParametersReady || !pixelCanChange || pendingPixelMode || pendingPixelWait >= 0 || pendingPixelInitial >= 0 || pendingPixelSound >= 0 ||
            [0,500,1000,2000,5000].indexOf(value) < 0) return
        pixelWaitAcknowledged = false
        pendingPixelWait = value; waitTicks = 0
        pixelMessage = "正在保存…"
        if (!pixelBackend.request("wait", value)) {
            pendingPixelWait = -1; pixelMessage = "未能保存，请重新选择"; return
        }
        waitAcknowledge.start()
    }
    Timer {
        id: waitAcknowledge; interval: 100; repeat: true
        onTriggered: {
            root.waitTicks++
            if (root.pixelWaitAcknowledged && root.pixelWait === root.pendingPixelWait) {
                stop(); root.pendingPixelWait = -1; root.pixelMessage = "参数已保存"
            } else if (!root.pixelCanChange || (root.waitTicks >= 30 && !pixelBackend.busy)) {
                stop(); root.pendingPixelWait = -1; root.pixelMessage = "未能保存，请重新选择"
            }
        }
    }

    readonly property int keyOverride: HblmTypes.E_CameraKeyOption_OverrideHalfPress // Used by KeyFocusHandler.cpp
    readonly property real leftSideWidth: 256 * 1.6 * Constants.scaleFactorX
    readonly property real headerAreaHeight: 56 * 1.6 * Constants.scaleFactorY
    readonly property real headerFontSize: 20 * 1.6 * Constants.scaleFactor
    readonly property int headerFontWeight: Font.Medium

    signal setDriveMode(int mode)
    signal setExitDriveMode(int mode)

    contentItem: grid
    headingSize: 0
    contentWidth: 564 * 1.6 * Constants.scaleFactorX
    contentHeight: 426 * 1.6 * Constants.scaleFactorY
    popupTopMargin: 27 * 1.6 * Constants.scaleFactorY

    clickedHandler: popoverClickCloseHandler

    onActiveFocusChanged: {
        if (activeFocus) {
            grid.focus = true
        }
    }

    function popoverClickCloseHandler()
    {
        var closePopover = !menuLoader.popupActive
        if (!closePopover) {
            menuLoader.item.closePopup()
        }

        return closePopover
    }

    function closeDriveMode()
    {
        popoverClickCloseHandler()
        root.close()
    }

    content: Item {
        anchors.fill: parent
        clip: true

        Row {
            anchors.fill: parent

            Item {
                id: left_side

                width: root.leftSideWidth
                height: parent.height

                Item {
                    id: left_header_area
                    anchors {
                        top: parent.top
                        left: parent.left
                        right: parent.right
                    }
                    height: root.headerAreaHeight

                    Text {
                        anchors.centerIn: parent
                        objectName: "NativeDriveModeHeading"
                        text: qsTranslate("PopoverDriveMode", "Drive Mode")
                        color: Constants.colorWhite
                        font.pixelSize: root.headerFontSize
                        font.weight: root.headerFontWeight
                    }
                }

                NativePixelGrid {
                    id: grid
                    focus: true
                    srcModel: gridModel
                    expMode: root.expMode
                    lensHasMicroFocusAdjust: root.lensHasMicroFocusAdjust
                    driveMode: root.driveMode
                    maxWidth: parent.width
                    anchors {
                        top: parent.top
                        horizontalCenter: parent.horizontalCenter
                        topMargin: 62 * 1.6 * Constants.scaleFactorY
                    }

                    onOpenDialog: (settingsList)=> {
                        swipeArea.settingsList = settingsList
                        swipeArea.showLoader(true)
                    }
                    onSetDriveMode: (mode)=> {
                        // Set both drive mode and exit_drive_mode that should be used when exiting from bracketing etc.
                        if (mode === 6) {
                            var selected = root.pixelMode
                            root.choosePixelMode([1,2,3].indexOf(selected) >= 0 ? selected : 1)
                        } else {
                            if (!root.pixelCanChange || root.pendingPixelMode || root.pendingPixelWait >= 0 || root.pendingPixelInitial >= 0 || root.pendingPixelSound >= 0) {
                                root.pixelMessage = "相机忙，请稍后选择"
                                Qt.callLater(function() { grid.updateCurrentIndex() }); return
                            }
                            root.setDriveMode(mode)
                            root.setExitDriveMode(mode)
                        }
                    }

                    Component.onCompleted: {
                        close.connect(root.closeDriveMode)
                    }
                }
            }
            Separator {
                anchors {
                    top: parent.top
                    bottom: parent.bottom
                }
                color: Constants.popupBorderColor
                width: Constants.popupBorderWidth
            }
            Item {
                id: right_side
                width: parent.width - left_side.width
                height: parent.height
                readonly property bool canShowSettings: root.pixelPage || list.settingsList !== ""

                MouseArea {
                    id: right_side_ma
                    objectName: "DriveSettingsEntry"
                    anchors {
                        fill: parent
                        topMargin: right_header_area.height
                    }
                    enabled: right_side.canShowSettings
                    onClicked: {
                        swipeArea.settingsList = list.settingsList
                        swipeArea.showLoader(true)
                    }
                }

                Item {
                    id: right_header_area
                    anchors {
                        top: parent.top
                        left: parent.left
                        right: parent.right
                    }
                    height: root.headerAreaHeight

                    Text {
                        anchors.centerIn: parent
                        text: root.pixelPage ? "像素位移" : qsTranslate("DriveModes", list.headerText)
                        color: Constants.colorWhite
                        font.pixelSize: root.headerFontSize
                        font.weight: root.headerFontWeight
                    }
                }


                Column {
                    objectName: "NativePixelSummary"
                    visible: root.pixelPage
                    x: list.sideMargins
                    y: list.listTopMargin
                    width: list.width
                    spacing: list.spacing
                    TextValueRow {
                        objectName: "NativePixelSummaryFrames"
                        labelFontWeight: list.labelFontWeight
                        valueFontWeight: list.valueFontWeight
                        width: parent.width; text: "拍摄张数"
                        valueText: !root.pixelParametersReady ? "读取中…" : root.pixelFrames() === (root.pixelMode === 1 ? 4 : root.pixelMode === 2 ? 6 : root.pixelMode === 3 ? 16 : 0) ? root.pixelFrames() + " 张" : "请选择张数"
                        pixelSize: 25 * 1.6 * Constants.scaleFactor
                    }
                    TextValueRow {
                        objectName: "NativePixelSummaryInitial"
                        labelFontWeight: list.labelFontWeight
                        valueFontWeight: list.valueFontWeight
                        width: parent.width; text: "初始延迟"
                        valueText: root.pixelParametersReady ? (root.pixelInitialDelay === 0 ? "关闭" : root.pixelInitialDelay + " 秒") : "读取中…"
                        pixelSize: 25 * 1.6 * Constants.scaleFactor
                    }
                    TextValueRow {
                        objectName: "NativePixelSummarySound"
                        labelFontWeight: list.labelFontWeight
                        valueFontWeight: list.valueFontWeight
                        width: parent.width; text: qsTranslate("MENUS", "Volume")
                        valueText: root.pixelParametersReady ? ValueFormatter.getDisplayValue("selftimer_sound_level",root.pixelSoundLevel) : "读取中…"
                        pixelSize: 25 * 1.6 * Constants.scaleFactor
                    }
                    TextValueRow {
                        objectName: "NativePixelSummaryWait"
                        labelFontWeight: list.labelFontWeight
                        valueFontWeight: list.valueFontWeight
                        width: parent.width; text: "帧间等待"
                        valueText: root.pixelParametersReady ? (root.pixelWait / 1000).toFixed(1) + " 秒" : "读取中…"
                        pixelSize: 25 * 1.6 * Constants.scaleFactor
                    }
                    Text {
                        objectName: "NativePixelTripodNotice"
                        width: parent.width; wrapMode: Text.WordWrap
                        text: "请使用三脚架\n保持相机与被摄物静止"
                        color: Constants.popupTextColor
                        font.family: Constants.menuItemFontName
                        font.pixelSize: Constants.settingsMenuDescriptionFontSize
                    }
                    Text {
                        width: parent.width; wrapMode: Text.WordWrap
                        text: root.pixelMessage || "保存原始 RAW 序列，请在电脑合成"
                        color: Constants.popupTextColor
                        font.family: Constants.menuItemFontName
                        font.pixelSize: Constants.settingsMenuDescriptionFontSize
                    }
                }

                HblListView {
                    id: list
                    objectName: "NativeStockDriveSummaryList"
                    visible: !root.pixelPage
                    interactive: false
                    spacing: 32 * 1.6 * Constants.scaleFactorY
                    readonly property string headerText: grid.currentIndex >= 0 ? gridModel.get(grid.currentIndex).text : ""
                    readonly property string settingsList: grid.currentIndex >= 0 ? gridModel.get(grid.currentIndex).settingsList : ""
                    readonly property string description: grid.currentIndex >= 0 ? gridModel.get(grid.currentIndex).description : ""
                    readonly property real sideMargins: 14 * 1.6 * Constants.scaleFactorX
                    readonly property real listTopMargin: 67 * 1.6 * Constants.scaleFactorY
                    readonly property int labelFontWeight: Font.Medium
                    readonly property int valueFontWeight: Font.Normal

                    onSettingsListChanged: {
                        if (settingsList === "") {
                            SubMenu.closeMenu(0)
                            list.model = null
                        } else {
                            SubMenu.showMenu(0, settingsList)
                            list.model = SubMenu.getModel(0)
                        }
                    }
                    anchors {
                        fill: parent
                        topMargin: list.listTopMargin
                        leftMargin: list.sideMargins
                        rightMargin: list.sideMargins
                    }

                    Text {
                        visible: list.settingsList === ""
                        width: parent.width
                        fontSizeMode: Text.HorizontalFit
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        font.pixelSize: 25 * 1.6 * Constants.scaleFactor
                        text: qsTranslate("DriveModes", list.description)
                        color: Constants.colorWhite
                    }

                    delegate: TextValueRow {
                        width: list.width
                        text: model.text1
                        enabled: model.itemEnabled
                        valueText: ValueFormatter.getDisplayAltValue(model.itemName, model.propValue)
                        pixelSize: 25 * 1.6 * Constants.scaleFactor
                        labelFontWeight: list.labelFontWeight
                        valueFontWeight: list.valueFontWeight
                    }
                }
            }
        }

        MenuSwipe {
            id: swipeArea
            objectName: "PopoverDriveMode_swipe_area"
            property string settingsList: ""
            readonly property bool preventSwipe: menuLoader.item &&
                                                 menuLoader.item.preventSwipe
            anchors.fill: parent
            loader: menuLoader
            parentItem: parent
            enabled: menuLoader.active &&
                     !mainMenuViewModel.screenEVF &&
                     !preventSwipe
            filterChildren: true
            deactivateLoaderWhenHidden: true
            animateLoader: true

            Keys.onPressed: (event)=> {
                if (MKeys.pressedFnListAcc([KeyFn.Abort, KeyFn.JstkEscape], event)) {
                    show = false
                } else if (MKeys.pressedFnAcc(KeyFn.Right, event)) {
                    // block key
                }
            }

            HblLoader {
                id: menuLoader
                objectName: "PopoverDriveMode_menuLoader"
                active: false
                asynchronous: true
                readonly property bool popupActive: item && item.popupActive

                anchors {
                    top: parent.top
                    bottom: parent.bottom
                }
                width: parent.width
                onWidthChanged: updatePosition()
                onXChanged: {
                    if (swipeArea.isXAtScreenEdge()) {
                        swipeArea.animateLoader = true
                    }
                }

                function updatePosition()
                {
                    // When changing to/from EVF then move x to new position without animation
                    if (!swipeArea.isXAtScreenEdge()) {
                        swipeArea.animateLoader = false
                    }
                }

                source: root.pixelPage ? "file:///system/etc/x2d-multishot/NativePixelSettings.qml" : "qrc:/app/qml/mainmenu/SettingsGeneric.qml"
                arguments: { "externalMenu": true }

                onLoaded: {
                    menuLoader.item.viewModel = Qt.binding( function() { return root.mainMenuViewModel })
                    if (root.pixelPage) {
                        menuLoader.item.controller = root
                    } else {
                        menuLoader.item.populateModel(0, swipeArea.settingsList)
                        menuLoader.item.menuLabel = Qt.binding( function() { return qsTranslate("DriveModes", list.headerText) })
                    }

                    if (!swipeArea.show) {
                        // Close menu after being loaded in onCompleted
                        menuLoader.active = false
                    }
                }

                Connections {
                    target: menuLoader.item
                    ignoreUnknownSignals: true
                    function onClose()
                    {
                        swipeArea.showLoader(false)
                    }
                    function onCloseExternal()
                    {
                        swipeArea.showLoader(false)
                        if (root.pixelPage) root.requestPixelLiveview(); else root.closeDriveMode()
                    }
                }

                // Border for loaded menu
                Rectangle {
                    id: menuBorder

                    anchors.fill: parent
                    color: "transparent"
                    border.width: Constants.popupBorderWidth
                    border.color: Constants.popupBorderColor
                }
            }
        }

        states: [
            State {
                name: "show_dialog"
                when: swipeArea.show
                PropertyChanges { target: menuLoader; focus: true;}
                StateChangeScript { script: {
                        menuLoader.active = true
                    }
                }
            },
            State {
                name: ""
                PropertyChanges { target: grid; focus: true; restoreEntryValues: false }
            }
        ]
    }

    ListModel {
        id: gridModel
        ListElement {
            icon: "image://svg/ic_controlscreen_drive_mode_single_popup"
            disabledIcon: ""
            text: QT_TRANSLATE_NOOP("DriveModes", "Single")
            description: QT_TRANSLATE_NOOP("DriveModes", "Single Drive Mode")
            settingsList: ""
            drivemode: HblmTypes.E_DriveModes_Single
        }
        ListElement {
            icon: "image://svg/ic_controlscreen_drive_mode_continuous_popup"
            disabledIcon: ""
            text: QT_TRANSLATE_NOOP("DriveModes", "Continuous")
            description: QT_TRANSLATE_NOOP("DriveModes", "Continuous Drive Mode")
            settingsList: ""
            drivemode: HblmTypes.E_DriveModes_Continuous
        }
        ListElement {
            icon: "image://svg/ic_controlscreenpic_drive_mode_selftimer_popup"
            disabledIcon: ""
            text: QT_TRANSLATE_NOOP("DriveModes", "Self-Timer")
            description: ""
            settingsList: "cameraSettingsSelfTimer"
            drivemode: HblmTypes.E_DriveModes_SelfTimer
        }
        ListElement {
            icon: "image://svg/ic_controlscreenpic_drive_mode_interval_popup"
            disabledIcon: "image://svg/ic_controlscreenpic_drive_mode_interval_popup_disable"
            text: QT_TRANSLATE_NOOP("DriveModes", "Interval")
            description: ""
            settingsList: "cameraSettingsInterval"
            drivemode: HblmTypes.E_DriveModes_Interval
        }
        ListElement {
            icon: "image://svg/ic_controlscreen_drive_mode_exposure_bracketing_popup"
            disabledIcon: "image://svg/ic_controlscreen_drive_mode_exposure_bracketing_popup_disable"
            text: QT_TRANSLATE_NOOP("DriveModes", "Exposure Bracketing")
            description: ""
            settingsList: "cameraSettingsExposureBracketing"
            drivemode: HblmTypes.E_DriveModes_ExposureBracketing
        }
        ListElement {
            icon: "image://svg/ic_controlscreen_drive_mode_focus_bracketing_popup"
            disabledIcon: "image://svg/ic_controlscreen_drive_mode_focus_bracketing_popup_disabled"
            text: QT_TRANSLATE_NOOP("DriveModes", "Focus Bracketing")
            description: ""
            settingsList: "cameraSettingsFocusBracketing"
            drivemode: HblmTypes.E_DriveModes_FocusBracketing
        }
        ListElement {
            icon: "file:///system/etc/x2d-multishot/ic_drive_mode_multishot.svg"
            disabledIcon: "file:///system/etc/x2d-multishot/ic_drive_mode_multishot_disable.svg"
            text: "像素位移"
            description: "请使用三脚架"
            settingsList: ""
            drivemode: 6
        }
    }

    Component.onCompleted: {
        Qt.callLater(root.attachPixelControl)
        // Loader is slow the first time so start immediately to avoid penalty later.
        menuLoader.active = true
    }
    Component.onDestruction: {
        SubMenu.closeMenu(0)
    }

    component NativePixelGrid: HblGridView {

    id: root
    objectName: "DriveModeGrid_root"
    property ListModel srcModel: null
    property int driveMode: 0
    property int expMode: 0
    property real maxWidth: 0
    property bool lensHasMicroFocusAdjust: false
    readonly property real sideMargin: 28 * 1.6 * Constants.scaleFactorX
    readonly property real highlightWidth: 76 * 1.6 * Constants.scaleFactorX
    readonly property real highlightHeight: 44 * 1.6 * Constants.scaleFactorY
    // Make item wide enough to avoid spacing
    readonly property real itemWidth: (maxWidth - 2 * sideMargin - numCols * highlightWidth) / (numCols - 1) + highlightWidth
    readonly property real itemHeight: 87 * 1.6 * Constants.scaleFactorY // top of topItem to top of next item

    signal setDriveMode(int mode)
    signal close()
    signal openDialog(string settingsList)

    model: srcModel
    interactive: false
    boundsBehavior: Flickable.StopAtBounds
    width: numCols * itemWidth
    height: numRows * itemHeight
    cellWidth: itemWidth
    cellHeight: itemHeight
    numRows: 4
    numCols: 2

    onCountChanged: updateCurrentIndex()
    onDriveModeChanged: updateCurrentIndex()

    function updateCurrentIndex()
    {
        for (var i = 0; i < root.count; i++) {
            if (model.get(i).drivemode === root.driveMode) {
                root.currentIndex = i
                break
            }
        }
    }

    function setSelected(closePopup)
    {
        var mode = root.model.get(root.currentIndex).drivemode
        root.setDriveMode(mode)
        if (mode === 6) return

        if (closePopup === undefined || closePopup) {
            root.close()
        }
    }

    function isIndexSelectable(ix : int) : bool // Overrides HblGridView
    {
        if (!root.srcModel || ix < 0 || ix >= root.srcModel.count) {
            return false
        }
        var item = srcModel.get(ix)

        if (root.expMode === HblmTypes.E_ExpMode_FullAuto &&
            (item.drivemode === 6 || item.drivemode === HblmTypes.E_DriveModes_Interval ||
             item.drivemode === HblmTypes.E_DriveModes_ExposureBracketing ||
             item.drivemode === HblmTypes.E_DriveModes_FocusBracketing)) {
            return false
        } else if (item.drivemode === HblmTypes.E_DriveModes_FocusBracketing &&
                   !root.lensHasMicroFocusAdjust) {
            return false
        }

        return true
    }

    delegate: Component { FocusScope {
        id: delegate
        focus: GridView.isCurrentItem

        readonly property bool isSelectable: root.isIndexSelectable(index)

        width: root.cellWidth
        height: root.cellHeight
        enabled: isSelectable

        FramedImage {
            text: qsTranslate("DriveModes", model.text)
            textColor: delegate.isSelectable ? Constants.popupTextColor :
                                               Constants.popupTextDisabledColor
            textPixelSize: 18 * 1.6 * Constants.scaleFactor
            textSideMargin: 0 * 1.6 * Constants.scaleFactorX
            textTopMargin: 6 * 1.6 * Constants.scaleFactorY
            anchors {
                top: parent.top
                horizontalCenter: parent.horizontalCenter
            }
            width: parent.width
            highlightHeight: root.highlightHeight
            highlightWidth: root.highlightWidth
            focus: parent.GridView.isCurrentItem
            source: delegate.isSelectable ? model.icon :
                                            model.disabledIcon
            image.sourceSize: model.drivemode === 6 ?
                Qt.size(52 * 1.6 * Constants.scaleFactor, 52 * 1.6 * Constants.scaleFactor) :
                Qt.size(100 * 1.6 * Constants.scaleFactor, 100 * 1.6 * Constants.scaleFactor)

            Keys.onPressed: (event)=> {
                if (!delegate.isSelectable) {
                    return
                }

                /* Joystick center and AF-D should behave slightly different:
                 *  - Joystick center: Choose the wb mode and exit the popup
                 *  - AF-D: Enter the settings popup
                 */
                if (MKeys.pressedFnAcc(KeyFn.JstkCenter, event)) {
                    root.currentIndex = index
                    root.setSelected(true)
                } else if (MKeys.pressedFnAcc(KeyFn.Enter, event)) {
                    root.currentIndex = index
                    if (model.settingsList !== "") {
                        root.openDialog(model.settingsList)
                    } else {
                        root.setSelected(true)
                    }
                } else if (MKeys.pressedFnAcc(KeyFn.JstkUp, event)) {
                    root.moveUp()
                } else if (MKeys.pressedFnAcc(KeyFn.JstkDown, event)) {
                    root.moveDown()
                } else if (MKeys.pressedFnListAcc([KeyFn.Up, KeyFn.Left], event)) {
                    root.moveLeft()
                } else if (MKeys.pressedFnListAcc([KeyFn.Down, KeyFn.Right], event)) {
                    root.moveRight()
                }
            }
            onPressed: {
                root.focus = true
                var closePopup = index === root.currentIndex
                root.currentIndex = index
                root.setSelected(closePopup)
            }
        }
    }

    }
    Component.onCompleted: updateCurrentIndex()

    }
}
