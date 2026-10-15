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
import QtQml.Models

import com.hasselblad.types
import com.hasselblad.menumodel
import com.hasselblad.keys
import com.hasselblad.constants
import com.hasselblad.guiconfig

import "qrc:/app/qml/components" as Components
import "qrc:/app/qml/scripts/Keys.js" as MKeys
import "qrc:/app/qml/mainmenu/delegates"
import "qrc:/app/qml/mainmenu"

FocusScope {
    objectName: "SettingsGeneric_root"
    id: root
    readonly property bool x2dExposureExtension: true
    focus: true

    X2dShutterSoundController { id: sound }
    X2dExposureMenuModel {
        id: adapter
        stockDelegate: baseDelegate
        controller: sound
        menuName: root.menuName
    }
    property MainMenuViewModel viewModel: null
    property string menuLabel
    property bool showHeader: true
    readonly property real heightForItemList: list.model ? heightForItem * Math.min(list.model.totalSize, Constants.maxVisibleMenuItems) : 0
    property real heightForItem: Constants.menuListItemDefaultHeight
    property int subMenuLevel: 0
    property string menuName: ""
    readonly property bool preventSwipe: subDialog.preventSwipe
    readonly property bool popupActive: subDialog.active
    property string itemToOpen: ""
    property bool externalMenu: false // Opened from WB/drive mode popovers

    signal close()
    signal closeExternal()
    signal loaded()

    // Open top-level menu
    function openTopMenu()
    {
        root.menuName = viewModel.menu.menuName
        SubMenu.showMenu(0, root.menuName)
        root.populateModel(0, root.menuName);

        if (viewModel.menu.scrollToItem !== "") {
            root.scrollToItem(viewModel.menu.scrollToItem)

            if (viewModel.menu.openItem) {
                // Do not start timer here but wait for item to load first.
                root.itemToOpen = viewModel.menu.scrollToItem
            } else {
                loadTimer.start()
            }
        } else {
            root.loaded()
        }
    }

    function populateModel(level, menuName)
    {
        root.subMenuLevel = level
        root.menuName = menuName
        root.menuLabel = SubMenu.menuLabel(menuName)

        if (level > 0) {
            // Used by unit tests
            root.objectName = root.objectName + level.toString()
        }

        adapter.sourceModel = SubMenu.getModel(level)
        list.model = adapter
        console.info("X2D_SHUTTER_PAGE_MODEL",menuName,level)
    }

    function closePopup()
    {
        subDialog.closeSubDialog()
    }

    function closeSubMenus()
    {
        // Make sure eventual loading is finished before killing it
        subDialog.asynchronous = false
        subDialog.asynchronous = true

        swipeArea.showLoader(false)
        SubMenu.closeMenu(0)
    }

    /* The menu contains delegates of different height and the correct height for each delegate isn't set
     * until its Loader has finished loading. Normally the ListView positions itself so currentItem is
     * shown when currentIndex changes but if currentIndex is changed before all ListView delegates have
     * correct height then the ListView will not position the item correctly.
     *
     * When loading a menu using 'scrollToItem' option we therefore neeed to wait a bit to let items
     * to load before we try to position the ListView for our item.
     * The MainMenu will be hidden until we have positioned the item.
     */
    Timer {
        id: loadTimer
        interval: 50
        onTriggered: root.loaded()
    }

    // This marks entire area available for list view
    Item {
        id: listViewArea
        anchors {
            top: list.top
            left: root.left
            right: root.right
            bottom: list.bottom
        }
        // Dummy mouse area. Without it, sweep away does not work properly. QML Magic...
        MouseArea {
            anchors.fill: parent
        }
    }

    // Activate highlighting of the chosen menu item
    function activateHighlight()
    {
        list.showHighlight()
    }

    // Deactivate highlighting of all menu items
    function deactivateHighlight()
    {
        list.stopHighlight()
    }

    function scrollToItem(itemName)
    {
        if (itemName !== "") {
            list.currentIndex = list.model.srcIndex(itemName)
            list.positionViewAtIndex(list.currentIndex, ListView.Beginning)
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Constants.menuBackgroundColor
    }
    Keys.forwardTo: [list]

    MenuHeader {
        id: listview_header_text
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
        }
        height: root.showHeader ? defaultHeight : 0
        visible: root.showHeader
        showSeparator: !list.atYBeginning
        externalMenu: root.externalMenu
        text: [ { context: root.externalMenu ? "" : "MENUS",
                  text: root.menuLabel,
                  color: Constants.settingsMenuHeaderSuffixFontColor } ]
        Component.onCompleted: {
            close.connect(root.close)
        }

        onActiveFocusChanged: {
            if (activeFocus) {
                list.positionViewAtBeginning()
            }
        }
    }

    Components.CustomListView {
        objectName: "SettingsGeneric_list"
        id: list

        readonly property int headerIndex: -1

        interactive: contentHeight > height && !viewModel.screenEVF
        clip: true
        focus: true

        height: root.heightForItemList
        anchors {
            left: parent.left
            right: parent.right
            top: listview_header_text.bottom
            bottom: parent.bottom
            // Add some space at bottom to allow swiping up drawer
            bottomMargin: viewModel.menuSwipeAreaHeight
        }
        viewInactiveIndex: headerIndex - 1
        currentIndex: viewInactiveIndex
        maximumFlickVelocity: 8000

        onCountChanged: {
            currentIndex = viewInactiveIndex
        }

        onActiveFocusChanged: {
            // Only when we get activeFocus back from something else we set the index selection to none.
            // Otherwise the reflection of a click doesn't show up.
            if (activeFocus) {
                list.stopHighlight()
            }
        }

        // Work-around for EC1704-7929:
        // When going from EVF to LCD (or vice versa) the listview and its
        // delegate items are resized. For some unknown reason the first delegate can be skewed and look strange
        // This seems to be related to section headers and a QML bug, avoid this by resetting the section headers
        // everytime we switch display (Which is triggered by having the height changed)
        onHeightChanged: {
            var delegate = section.delegate
            section.delegate = null
            section.delegate = delegate
        }

        Keys.onPressed: (event)=> {
            if (MKeys.pressedFnListAcc([KeyFn.Ael, KeyFn.JstkEscape], event)) {
                list.stopHighlight()
                root.close()
                return
            } else if (MKeys.pressedFnAcc(KeyFn.Cross, event)) {
                if (list.highlighting) {
                    list.stopHighlight()
                } else {
                    root.close()
                }
                return
            }

            if (!list.highlighting) {
                if (MKeys.pressedFnListAcc([KeyFn.ListUp, KeyFn.ListDown, KeyFn.HighlightSelect, KeyFn.JstkSelect], event)) {
                    list.startHighlight()
                }
            } else { // Highlighting
                if (MKeys.pressedFnAcc(KeyFn.ListUp, event)) {
                    list.decrementCurrentIndex()
                } else if (MKeys.pressedFnAcc(KeyFn.ListDown, event)) {
                    list.incrementCurrentIndex()
                } else if (MKeys.pressedFnAcc(KeyFn.Select, event)) {
                    list.stopHighlight()
                } else if (!MKeys.pressedFnListAcc([KeyFn.JstkEscape, KeyFn.NavKey], event)) {
                    //Block all navigation keys except JstkEscape
                }
            }
        }

        // Header and footer to add some extra spacing at top bottom of listview
        header: Rectangle {
            readonly property bool noHeader: root.externalMenu || menuName == "generalMenu"
            color: Constants.colorBlack
            width: list.width
            height: noHeader ? 0 : 16 * 1.6 * Constants.scaleFactorY
        }

        // Section header
        section.property: "sectionName"
        section.delegate: Item {
            id: sectionItem
            readonly property bool syntheticBlankSection: section === "" && adapter.suppressSyntheticBlankSection

            /* We have two different types of subheaders:
             * TextSection: Ends previous section with a separator and starts next section with a text
             * Separator: Ends previous section with a separator and add some padding after the separator
             */
            readonly property string separatorId: "_separator_"
            readonly property bool firstInList: list.model ? list.model.isSectionFirstInList(section) : false
            readonly property bool isSeparator: section.startsWith(separatorId)
            readonly property real separatorTopPadding: list.model ? list.model.separatorTopPadding(section) * Constants.scaleFactorY : 0
            readonly property real separatorBottomPadding: list.model ? list.model.separatorBottomPadding(section) * Constants.scaleFactorY : 0
            readonly property real textTopPadding: firstInList ? 0 : separatorTopPadding + 24 * 1.6 * Constants.scaleFactorY
            readonly property real textBottomPadding: 8 * 1.6 * Constants.scaleFactorY
            readonly property real heightSeparator: separatorTopPadding + separatorBottomPadding
            readonly property real heightTextSection: textTopPadding + sectionText.height + textBottomPadding

            width: list.width
            height: syntheticBlankSection ? 0 : isSeparator ? heightSeparator :
                                  heightTextSection

            Components.Separator {
                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                    topMargin: sectionItem.separatorTopPadding
                    leftMargin: Constants.settingsMenuSettingLeftMargin
                }
                visible: !sectionItem.firstInList && !sectionItem.syntheticBlankSection
                horizontal: true
                height: Constants.menuListDividerHeight
                color: Constants.menuListDividerColor
            }

            Text {
                id: sectionText
                anchors {
                    top: parent.top
                    topMargin: parent.textTopPadding
                    left: parent.left
                    leftMargin: Constants.settingsMenuSettingLeftMargin
                }
                visible: !sectionItem.isSeparator && !sectionItem.syntheticBlankSection
                text: qsTranslate("MENUS", section)
                font.pixelSize: 24 * 1.6 * Constants.scaleFactor
                font.weight: Font.Normal
                color: Constants.colorWhite
                opacity: 0.9
            }
        }

        delegate: null // DelegateModel owns the unchanged native base delegate.
        highlightMoveDuration: -1
        highlightMoveVelocity: -1
        highlight: Rectangle {
            color: Constants.popupBackgroundColor
            Rectangle {
                color: list.highlighting ? Constants.highlightColor :
                                           Constants.popupBackgroundColor
                anchors.fill: parent
            }
        }

        // Trigger a highlight with a small delay
        function showHighlight()
        {
            list.startDelayedHighlight()
        }

        // Delegate that loads different component based on type of setting
        Component {
            id: baseDelegate
            Item {
                objectName: "baseItem"
                id: baseItem
                readonly property int displayIndex: baseItem.DelegateModel.itemsIndex
                Components.DemoMarker {
                    anchors.fill: parent
                    showMarker: model.demo
                    demoMode: root.viewModel ? root.viewModel.demoMode : false
                }

                width: list.width
                readonly property real itemHeight: specialItem.item ? specialItem.item.height : 0
                height: Math.max(itemHeight, root.heightForItem)

                Components.HblLoader {
                    objectName: "specialItem"
                    id: specialItem
                    asynchronous: true
                    active: true
                    visible: status === Loader.Ready
                    centerInParent: true
                    focus: baseItem.ListView.isCurrentItem
                    Keys.onReturnPressed: {
                        console.info("Return pressed in loader");
                        event.accepted = true
                    }
                    // Loader adapts its size to match size of the loaded delegate
                    anchors.centerIn: parent

                    source: {
                        if (model.itemName === adapter.extraName)
                            return "file:///system/etc/x2d-shutter-sound/X2dShutterSoundSwitch.qml"
                        switch (model.elem) {
                        case GuiTypes.E_MenuElem_DropDown:      return "qrc:/app/qml/mainmenu/delegates/DropdownDelegate.qml"
                        case GuiTypes.E_MenuElem_ValueSwitch: return "qrc:/app/qml/mainmenu/delegates/ValueSwitchDelegate.qml"
                        case GuiTypes.E_MenuElem_CombinationValue: return "qrc:/app/qml/mainmenu/delegates/CombinationValueDelegate.qml"
                        case GuiTypes.E_MenuElem_Button:        return "qrc:/app/qml/mainmenu/delegates/ButtonDelegate.qml"
                        case GuiTypes.E_MenuElem_Submenu:       return "qrc:/app/qml/mainmenu/delegates/SubmenuDelegate.qml"
                        case GuiTypes.E_MenuElem_Switch:        return "qrc:/app/qml/mainmenu/delegates/SwitchDelegate.qml"
                        case GuiTypes.E_MenuElem_Slider:        return "qrc:/app/qml/mainmenu/delegates/SliderDelegate.qml"
                        case GuiTypes.E_MenuElem_EditText:      return "qrc:/app/qml/mainmenu/delegates/EditTextDelegate.qml"
                        case GuiTypes.E_MenuElem_Text:          return "qrc:/app/qml/mainmenu/delegates/TextDelegate.qml"
                        case GuiTypes.E_MenuElem_TextButton:    return "qrc:/app/qml/mainmenu/delegates/TextButtonDelegate.qml"
                        case GuiTypes.E_MenuElem_TextAction:    return "qrc:/app/qml/mainmenu/delegates/TextActionDelegate.qml"
                        case GuiTypes.E_MenuElem_StorageInfo:   return "qrc:/app/qml/mainmenu/delegates/StorageInfoDelegate.qml"
                        case GuiTypes.E_MenuElem_Image:         return "qrc:/app/qml/mainmenu/delegates/ImageDelegate.qml"
                        case GuiTypes.E_MenuElem_ListValueSwitch: return "qrc:/app/qml/mainmenu/delegates/ListValueSwitchDelegate.qml"
                        }
                        console.warn("Invalid elem", model.elem)
                    }

                    arguments: { "model" : model,
                                 "itemIndex": baseItem.displayIndex,
                                 "viewModel": root.viewModel,
                                 "list": list,
                                 "subDialog": subDialog,
                                 "externalMenu": root.externalMenu
                    }
                    onLoaded: {
                        if (item.hasOwnProperty("soundController")) item.soundController = sound
                        item.defaultHeight = Qt.binding(function () { return root.heightForItem })

                        // signals
                        item.activateSettingsSubMenu.connect(root.activateSettingsSubMenu)

                        if (root.itemToOpen === model.itemName) {
                            item.openFromShortcut()
                        }
                    }
                }

                Keys.onPressed: (event)=> {
                    event.accepted = false
                    if (MKeys.pressedFnAcc(KeyFn.Select, event)) {
                        if (list.highlighting) {
                            var fromTouch = false;
                            specialItem.item.gotSelected(fromTouch);
                            // not accepting event here, letting ListView do its post processing.
                        }
                    }
                }
            }
        }
    }

    Connections {
        target: GuiConfig
        function onShowSecretMenuItemsChanged()
        {
            // This will be triggered for all instances of SettingsGeneric.
            // Ignore it for top-level instance it will replace the currently loaded item
            if (root.subMenuLevel === 0) {
                return
            }

            if (GuiConfig.showSecretMenuItems) {
                subDialog.source = "qrc:/app/qml/components/NotificationMessage.qml"
                subDialog.arguments = { "headingText": qsTr("Additional functions now\navailable in Service Menu"), "showtime" : 4500, "capitalization": Font.MixedCase }
                swipeArea.showLoader(true)
            }
        }
    }

    function activateSettingsSubMenu(menuLevel, menuName, itemFile, owner)
    {
        subDialog.menuName = menuName
        subDialog.source = menuName === "exposureMenu" &&
                itemFile === "qrc:/app/qml/mainmenu/SettingsGeneric.qml" ?
                "file:///system/etc/x2d-shutter-sound/X2dExposureSettings.qml" : itemFile
        subDialog.arguments = { "viewModel": root.viewModel }
        subDialog.subMenuLevel = menuLevel
        subDialog.owner = owner
        swipeArea.showLoader(true)
    }

    MenuSwipe {
        id: swipeArea
        objectName: "MenuSwipe_" + root.menuName
        anchors {
            top: root.top
            bottom: root.bottom
            right: root.right
            left: root.left
            // Don't overlap with drawer swipe up area
            bottomMargin: viewModel.menuSwipeAreaHeight
        }
        loader: subDialog
        parentItem: root
        filterChildren: true
        enabled: subDialog.active && !subDialog.preventSwipe
        onCloseItem: subDialog.closeSubDialog()

        Components.HblLoader {
            id: subDialog
            objectName: "subDialogLoader"
            anchors {
                top: parent.top
                bottom: parent.bottom
                // Negative margin since parent MouseArea stops above drawer swipe up area
                bottomMargin: -viewModel.menuSwipeAreaHeight
            }

            width: parent.width
            active: false
            enabled: false
            asynchronous: true
            visible: subDialog.status === Loader.Ready

            property bool preventSwipe: false
            property var menuName
            property string menuLabel: ""
            property int subMenuLevel: 0
            property alias animatePopupOpen: swipeArea.animateLoader
            property string owner: "" // Who is using loader when active
            property bool delayedClose: false

            Connections {
                target: subDialog.item
                ignoreUnknownSignals: true

                function onClose() { subDialog.closeSubDialog(); }
                function onClosePopup() { subDialog.closeSubDialog() }
                function onCloseExternal()
                {
                    subDialog.closeSubDialog();
                    root.closeExternal()
                }
            }

            onActiveChanged: {
                // If active becomes false, a dialog was closed, and list must get focus
                if (!active) {
                    // Make sure to break various bindings that could cause this to be active again
                    closeSubDialog()
                }
            }

            function showLoader(doShow)
            {
                swipeArea.showLoader(doShow)
            }

            function closeSubDialog()
            {
                if (subDialog.delayedClose) {
                    subDialog.delayedClose = false
                    closeTimer.start()
                    return
                }

                if (subDialog.source === "") {
                    // Already closed
                    return
                }

                console.info("subdialog was closed in", root.menuName)
                subDialog.source = ""
                swipeArea.showLoader(false)
                subDialog.arguments = null
                subDialog.preventSwipe = false
                swipeArea.animateLoader = true
                subDialog.owner = ""
                list.stopHighlight()
                closeTimer.stop()
            }

            // When changing a value which may take some time to be updated then keep popup open
            // until value has changed to avoid old value being shown briefly before being changed.
            // Use a timeout just to be safe.
            Timer {
                id: closeTimer
                interval: 300 // Some properties (like cfv camera_type) takes longer time to change
                onTriggered: subDialog.closeSubDialog()
            }

            onLoaded: {
                if (item.hasOwnProperty("menuLabel")) {
                    item.menuLabel = subDialog.menuLabel
                }

                // It has a function populateModel then it is a submenu
                if (item.hasOwnProperty("populateModel") && typeof item.populateModel == 'function') {
                    item.viewModel = root.viewModel
                    SubMenu.showMenu(subDialog.subMenuLevel, subDialog.menuName)
                    item.populateModel(subDialog.subMenuLevel, subDialog.menuName);
                }

                if (item.hasOwnProperty("preventSwipe")) {
                    subDialog.preventSwipe = Qt.binding(function() { return item && item.preventSwipe })
                } else {
                    console.error("Error: Loaded file", subDialog.source, "is missing property 'preventSwipe'")
                }

                // If we have opened a submenu item from shortcut then show menu again
                if (root.itemToOpen === subDialog.owner) {
                    root.itemToOpen = ""
                    loadTimer.start()
                }
            }
        }
    }

    state: ""
    states: [
        State {
            when: swipeArea.show
            name: "dialog"
            PropertyChanges { target: subDialog; focus: true; active: true; visible: true; enabled: true }
        },
        State {
            when: list.currentIndex === list.headerIndex
            name: "back_arrow"
            PropertyChanges { target: listview_header_text; focus: true }
        },
        State {
            name: ""
            PropertyChanges { target: list; focus: true }
        }
    ]

    Component.onCompleted: {
        // If this is top-level menu
        if (root.subMenuLevel === 0) {
            // This will also be set also when loading popups from a top-level menu but
            // it should be fine
            if (viewModel) {
                viewModel.menu.subMenuActive = Qt.binding(function() { return subDialog.active })
            }
        }
    }
}
