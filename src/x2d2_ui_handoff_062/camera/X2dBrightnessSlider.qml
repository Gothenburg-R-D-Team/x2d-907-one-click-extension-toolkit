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
import com.hasselblad.constants
import com.hasselblad.keys

import "qrc:/app/qml/scripts/Keys.js" as MKeys

// Slider
Rectangle {
    id: root
    objectName: "settingsSlider"
    color: "transparent"
    // The knob is the saved ceiling; only the fill follows measured output.
    property bool automatic: false
    property real actualValue: value
    property real smoothActualValue: actualValue
    Behavior on smoothActualValue { enabled: root.automatic; NumberAnimation { duration: 200 } }
    property real fillValue: automatic ? Math.max(minValue, Math.min(value, smoothActualValue)) : value
    property real value: 1
    property bool updateValueWhileDragging: false
    property int maxValue: 5
    property int minValue: -5
    property int stepValue: 1
    property real realValue: Math.round((minValue + ((slidingMarker.x - horizontalLine.x + slidingMarker.width / 2) / horizontalLine.width * (maxValue - minValue))) / stepValue) * stepValue
    property real stepSize: 0.5

    QtObject {
        id: d
        readonly property color lineColor: Constants.settingsMenuSliderKnobFillColor
        readonly property color markerColor: Constants.settingsMenuSliderKnobFillColor
        readonly property real markerSize: Constants.settingsMenuSliderKnobDiameter
        readonly property real zeroMarkerSize: Constants.settingsMenuSliderMiddleMarkerHeight
    }

    Keys.onPressed: (event)=> {
        var newValue = root.value
        if (MKeys.pressedFnAcc(KeyFn.NavLeft, event)) {
            newValue = newValue - root.stepValue
            if (newValue < root.minValue) {
                newValue = root.minValue;
            }
            root.value = newValue
        } else if (MKeys.pressedFnAcc(KeyFn.NavRight, event)) {
            newValue = newValue + stepValue
            if (newValue > root.maxValue) {
                newValue = root.maxValue;
            }
            root.value = newValue
        }
    }

    // Icon
    Item {
        id: slider
        anchors.fill: parent

        // Background for horizontal line
        Rectangle {
            color: Constants.colorWhite
            id: horizontalLine
            height: Constants.settingsMenuSliderThickness
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: slidingMarker.verticalCenter
            }
            opacity: 0.4
        }

        // The line with slider bar
        Rectangle {
            color: d.lineColor
            id: sliderBar
            objectName: "X2dBrightnessFill"
            height: Constants.settingsMenuSliderThickness
            anchors {
                left: parent.left
                verticalCenter: slidingMarker.verticalCenter
            }
            width: root.automatic ? horizontalLine.width * (root.fillValue - root.minValue) / (root.maxValue - root.minValue) :
                                    slidingMarker.x + slidingMarker.width / 2
        }

        // Sliding marker
        Rectangle {
            id: slidingMarker
            objectName: "X2dBrightnessCeilingKnob"
            anchors.verticalCenter: parent.verticalCenter
            z: 1
            color: sliderMouseArea.containsPress || sliderMouseArea.drag.active ? Constants.highlightColor :
                                                                                  d.markerColor
            border.width: Constants.settingsMenuSliderThickness
            border.color: d.lineColor
            radius: d.markerSize / 2
            width: d.markerSize
            height: d.markerSize
            x: horizontalLine.x - width / 2 + horizontalLine.width / (root.maxValue - root.minValue) * (root.value - root.minValue)
        }

        MouseArea {
            id: sliderMouseArea
            onClicked: { }

            preventStealing: true
            anchors {
                verticalCenter: slidingMarker.verticalCenter
                horizontalCenter: slidingMarker.horizontalCenter
            }
            height: slidingMarker.height * 2.4
            width: height * 1.5
            propagateComposedEvents: false
            drag {
                target: slidingMarker
                axis: Drag.XAxis
                minimumX: horizontalLine.x - slidingMarker.width / 2
                maximumX: horizontalLine.x + horizontalLine.width - slidingMarker.width / 2
            }

            drag.onActiveChanged: {
                if (!drag.active) {
                    // Calculate corresponding value, correct placement of slider
                    root.value = root.realValue
                }
            }

            onPositionChanged: {
                if (!root.updateValueWhileDragging) {
                    return
                }
                if (drag.active) {
                    root.value = root.realValue
                }
            }
        }
    }
}
