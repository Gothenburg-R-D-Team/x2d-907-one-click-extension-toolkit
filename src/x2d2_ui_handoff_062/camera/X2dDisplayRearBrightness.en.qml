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
import com.hasselblad.menumodel
import com.hasselblad.keys
// todo: EC1706-881 (user data collection)
//import com.hasselblad.analyticstypes

import "qrc:/app/qml/scripts/Keys.js" as MKeys
import "qrc:/app/qml/mainmenu"
import "qrc:/app/qml/mainmenu/delegates"

BaseDelegate {
    objectName: "SliderDelegate_root"
    id: root
    readonly property bool continuous: root.model ? (root.model.options & GuiTypes.E_MenuOption_SliderContinuous) : false
    readonly property real topOffset: 16 * 1.6 * Constants.scaleFactorY

    readonly property bool featureAvailable: controller.masterEnabled && controller.availablePreference
    property bool autoSelected: false
    readonly property real autoHeight: featureAvailable ? Constants.menuListItemDefaultHeight : 0
    height: autoHeight + topOffset + column.height
    X2dAutoBrightnessController {
        id: controller
        followMaster: true
        pageActive: root.visible
    }
    Item {
        objectName: "X2dDisplayAutoBrightnessRow"
        width: parent.width; height: root.autoHeight; visible: root.featureAvailable
        MenuBoolSelector {
            objectName: "X2dDisplayAutoBrightnessSwitch"
            anchors.left: parent.left; anchors.right: parent.right
            anchors.leftMargin: Constants.settingsMenuSettingLeftMargin
            anchors.rightMargin: Constants.settingsMenuSettingRightMargin
            anchors.verticalCenter: parent.verticalCenter
            text: "Auto Brightness"
            value: controller.enabledPreference
            itemEnabled: root.model.itemEnabled && !controller.busy && (controller.ready || controller.enabledPreference)
            highlighted: autoTouch.pressed || (root.autoSelected && root.list.highlighting && root.list.currentIndex === root.itemIndex)
            showSwitch: true; fontWeight: Constants.menuItemLabelFontWeight
        }
        MouseArea {
            id: autoTouch; anchors.fill: parent
            enabled: root.model.itemEnabled && !controller.busy && (controller.ready || controller.enabledPreference)
            onClicked: { root.autoSelected = true; controller.toggle() }
        }
    }

    function gotSelected(fromTouch)
    {
        if (!root.model.itemEnabled) {
            return
        }

        if (!fromTouch && root.featureAvailable && root.autoSelected) { controller.toggle(); return }
        if (settingsSlider.activeFocus) {
            settingsSlider.focus = false
        } else {
            settingsSlider.focus = true
        }
        /* todo: EC1706-881 (user data collection)
        Analytics.logAction(AnalyticsTypes.E_Category_Menu, AnalyticsTypes.E_Control_Slider, root.model.itemName,
                            fromTouch ? AnalyticsTypes.E_ActionSource_Touch : AnalyticsTypes.E_ActionSource_Key,
                            settingsSlider.activeFocus ? AnalyticsTypes.E_Action_Select : AnalyticsTypes.E_Action_Deselect)*/
    }

    /* QML repaint bug: The border must be placed in a separate z layer than the slider
       to avoid the slider horizontal line being repainted 1 pixel higher than before when
       moving the marker over the line (by dragging or changing x value with keys). The bug
       only occurs when the border is visible. */
    Rectangle {
        anchors.fill: parent
        anchors.topMargin: root.autoHeight
        color: "transparent"
        border.width: 2 * Constants.scaleFactorX
        border.color: settingsSlider.activeFocus ? Constants.colorWhite : "transparent"
        z: parent.z+1
    }

    Column {
        id: column
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            leftMargin: Constants.settingsMenuSliderLeftMargin
            rightMargin: Constants.settingsMenuSliderRightMargin
            topMargin: root.autoHeight + root.topOffset
        }
        spacing: 8 * 1.6 * Constants.scaleFactor

        Item {
            width: parent.width
            height: textItem.font.pixelSize
            Text {
                id: textItem
                anchors {
                    left: parent.left
                    verticalCenter: parent.verticalCenter
                }
                text: root.featureAvailable ? "Maximum Screen Brightness" : root.model.text1
                width: parent.width
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: Text.AlignLeft
                font.family: Constants.menuItemFontName
                font.pixelSize: Constants.settingsMenuTextFontSize
                font.weight: root.defaultLabelFontWeight
                color: Constants.menuItemColor
                opacity: root.model.itemEnabled ? 1.0 : Constants.menuItemDisabledTextOpacity
            }
        }

        X2dBrightnessSlider {
            id: settingsSlider
            enabled: root.model.itemEnabled
            width: parent.width
            height: 64 * 1.6 * Constants.scaleFactorY
            value: root.model.propValue
            automatic: root.featureAvailable && controller.enabledPreference && controller.effective
            actualValue: controller.applied
            updateValueWhileDragging: root.continuous
            minValue: ValueFormatter.getMinValue(root.model.itemName);
            maxValue: ValueFormatter.getMaxValue(root.model.itemName);
            stepValue: ValueFormatter.getStepsForValue(root.model.itemName)
            onValueChanged: {
                root.model.propValue = value
                /* todo: EC1706-881 (user data collection)
                Analytics.logAction(AnalyticsTypes.E_Category_Menu, AnalyticsTypes.E_Control_Slider, root.model.itemName,
                                    AnalyticsTypes.E_ActionSource_Unknown, AnalyticsTypes.E_Action_ValueChanged)*/

                if (activeFocus) {
                    // When keeping joystick pressed left/right to change value then highlight timer may timeout.
                    root.list.startHighlight()
                }
            }
        }
    }
    Keys.onPressed: (event)=> {
        if (root.featureAvailable && !settingsSlider.activeFocus) {
            if (root.autoSelected && MKeys.pressedFnAcc(KeyFn.ListDown, event)) {
                root.autoSelected = false; return
            }
            if (!root.autoSelected && MKeys.pressedFnAcc(KeyFn.ListUp, event)) {
                root.autoSelected = true; return
            }
        }

        /* AE-L handling:
         * If slider has focus (white border) then exit focus, otherwise exit menu.
         */
        if (settingsSlider.activeFocus && MKeys.pressedFnAcc(KeyFn.Ael, event)) {
            settingsSlider.focus = false
            /* todo: EC1706-881 (user data collection)
            Analytics.logAction(AnalyticsTypes.E_Category_Menu, AnalyticsTypes.E_Control_Slider, root.model.itemName,
                                AnalyticsTypes.E_ActionSource_Key, AnalyticsTypes.E_Action_Deselect)*/
        }
    }
}
