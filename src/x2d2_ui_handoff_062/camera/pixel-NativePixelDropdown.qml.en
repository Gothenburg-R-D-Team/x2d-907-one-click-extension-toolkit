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
import com.hasselblad.types
import com.hasselblad.constants
import com.hasselblad.valueformatter
// todo: EC1706-881 (user data collection)
//import com.hasselblad.analyticstypes

import "qrc:/app/qml/mainmenu"
import "qrc:/app/qml/mainmenu/delegates" as Delegates
import "qrc:/app/qml/components" as Components

Delegates.BaseDelegate {
    objectName: model ? model.objectName : "NativePixelRow"
    id: root
    property var controller: null
    property bool awaitingValueChange: false

    readonly property bool hasDescription: infoText.visible
    readonly property real topOffset: 16 * 1.6 * Constants.scaleFactorY
    readonly property real bottomOffset: 8 * 1.6 * Constants.scaleFactorY
    readonly property bool narrowLetterSpacing: root.model ? (root.model.options & GuiTypes.E_MenuOption_NarrowText) : false
    readonly property bool showInitText: root.model.itemName === "lens_manual_focal_length"
    readonly property string initText: viewModel.lensName
    readonly property bool haveDropdownOpen: subDialog.active &&
                                             subDialog.owner === root.model.itemName

    height: hasDescription ? (contentColumn.height + topOffset + bottomOffset) : defaultHeight

    function gotSelected(fromTouch)
    {
        if (!root.model.itemEnabled) {
            return
        }
        /* todo: EC1706-881 (user data collection)
        Analytics.logAction(AnalyticsTypes.E_Category_Menu, AnalyticsTypes.E_Control_DropDown, root.model.itemName,
                            fromTouch ? AnalyticsTypes.E_ActionSource_Touch : AnalyticsTypes.E_ActionSource_Key,
                            AnalyticsTypes.E_Action_Select)*/
        root.subDialog.source = "file:///system/etc/x2d-multishot/NativePixelSelector.qml"
        root.subDialog.arguments = { "viewModel": root.viewModel, "externalMenu": root.externalMenu,
                      "propName": root.model.itemName, "propValue": root.model.propValue,
                      "kind": root.model.kind, "controller": root.controller }
        root.openSubDialog(false)
    }

    onSubDialogLoaded: {
        // Start highlight after popup has been loaded to avoid annoying bright blink from highlight
        root.list.startHighlight(false)
        subDialog.item.setup()
    }

    Column {
        id: contentColumn
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            topMargin: root.topOffset
            leftMargin: Constants.settingsMenuSettingLeftMargin
            rightMargin: Constants.settingsMenuSettingRightMargin
        }
        spacing: 8 * 1.6 * Constants.scaleFactorY

        Item {
            id: dropdownItem
            width: parent.width
            height: dropDownText.font.pixelSize // PixelSize is more exact than height

            Text {
                id: dropDownText
                readonly property bool isEnabled: root.model.itemEnabled && root.model.text1 !== ""
                anchors {
                    left: parent.left
                    verticalCenter: parent.verticalCenter
                }
                text: root.model.text1
                color: Constants.settingsMenuSettingFontColor
                font.pixelSize: Constants.settingsMenuSettingFontSize
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: Text.AlignLeft
                font.weight: root.defaultLabelFontWeight
                opacity: root.model.itemEnabled ? 1.0 : Constants.menuItemDisabledTextOpacity
            }

            Rectangle {
                id: dropDownBox

                anchors {
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                }
                color: comboText.text == "" ? Constants.colorRed : "transparent"
                width: Constants.comboBoxWidth
                height: Constants.dropDownBoxHeight

                Text {
                    id: initTextItem
                    anchors {
                        right: comboText.left
                        verticalCenter: parent.verticalCenter
                    }
                    visible: root.showInitText
                    text: root.initText +  " "
                    verticalAlignment: Text.AlignVCenter
                    font.family: Constants.settingsMenuSettingDropDownFontName
                    font.pixelSize: Constants.settingsMenuSettingDropDownFontSize
                    font.weight: root.defaultValueFontWeight
                    color: Constants.settingsMenuSettingFontColor
                    opacity: root.model.itemEnabled ? 1.0 : Constants.menuItemDisabledTextOpacity
                }
                Text {
                    id: comboText
                    anchors {
                        right: parent.right
                        rightMargin: dropDownText2.visible ? dropDownText2.width : 0
                        verticalCenter: parent.verticalCenter
                    }
                    font.family: Constants.settingsMenuTextFontSize
                    font.pixelSize: Constants.settingsMenuTextFontSize
                    font.weight: root.defaultValueFontWeight
                    font.letterSpacing: root.narrowLetterSpacing ? -2 : 0
                    verticalAlignment: Text.AlignVCenter
                    color: Constants.settingsMenuSettingFontColor
                    text: root.model.displayValue + (dropDownText2.visible ? " " : "")
                    opacity: animation.running ? animation.targetOpacity :
                             root.model.itemEnabled ? 1.0 : Constants.menuItemDisabledTextOpacity
                }

                Text {
                    id: dropDownText2
                    anchors {
                        left: comboText.right
                        verticalCenter: parent.verticalCenter
                    }
                    visible: root.model.text2 !== ""
                    text: root.model.text2
                    verticalAlignment: Text.AlignVCenter
                    font.family: Constants.settingsMenuSettingDropDownFontName
                    font.pixelSize: Constants.settingsMenuSettingDropDownFontSize
                    font.weight: root.defaultValueFontWeight
                    color: Constants.settingsMenuSettingFontColor
                    opacity: animation.running ? animation.targetOpacity :
                             root.model.itemEnabled ? 1.0 : Constants.menuItemDisabledTextOpacity
                }
            }
        }

        SettingDescription {
            id: infoText
            visible: text !== ""
            width: parent.width
            text: root.model.description
            highlighted: root.activeFocus
            isEnabled: root.model.itemEnabled
        }
    }

    MenuDelegateClickArea {
        anchors.fill: parent
        enabled: root.model.itemEnabled
        helper: root.list.helper
        itemIndex: root.itemIndex
        subDialogActive: root.subDialog.active

        onSetItemIndex: root.list.currentIndex = itemIndex
        onSetHighlightMoveDuration: (val) => root.list.highlightMoveDuration = val
        onClicked: root.gotSelected(true)
    }

    Components.DataChangedAnimation {
        id: animation
        objectName: "NativePixelSavedBlink_" + root.model.itemName
    }

    Connections {
        target: root.haveDropdownOpen ? root.subDialog.item : null
        function onValueSaved() {
            root.awaitingValueChange = true
            root.subDialog.delayedClose = true
        }
    }

    Connections {
        target: root.model
        function onPropValueChanged() {
            if (!root.awaitingValueChange) return
            root.awaitingValueChange = false
            root.subDialog.closeSubDialog()
            animation.start()
        }
    }
}
