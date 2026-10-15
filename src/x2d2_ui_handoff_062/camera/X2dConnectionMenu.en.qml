import QtQuick

// Presentation only. Keep stock model, button actions and wifiMenu routing.
QtObject {
    id: root
    property var grid: null
    property var menuModel: null
    property bool active: false
    property string connectionLabel: "Connections"
    property string connectionIcon: "image://svg/file:///system/etc/X2dConnectionMenuIcon"
    property var button: null

    function findButton(item) {
        if (!item) return null
        if (item.objectName === "FramedItem_root" && typeof item.text === "string" &&
                typeof item.source !== "undefined") return item
        if (!item.children) return null
        for (var i=0; i<item.children.length; ++i) {
            var result=findButton(item.children[i])
            if (result) return result
        }
        return null
    }
    function refresh() {
        if (!active || !grid || !menuModel || !menuModel.extensionPresent ||
                menuModel.rejectionReason !== "") { button=null; return }
        var index=-1
        for (var i=0; i<menuModel.items.count; ++i) {
            var entry=menuModel.items.get(i)
            if (!entry.isUnresolved && entry.model.menuName === "wifiMenu") {
                if (index!==-1) { button=null; return }
                index=i
            }
        }
        button=index>=0 && index<grid.count ? findButton(grid.itemAtIndex(index)) : null
    }
    property Binding labelBinding: Binding {
        target: root.button; property: "text"; value: root.connectionLabel
        when: root.active && root.button!==null
        restoreMode: Binding.RestoreBindingOrValue
    }
    property Binding iconBinding: Binding {
        target: root.button; property: "source"; value: root.connectionIcon
        when: root.active && root.button!==null
        restoreMode: Binding.RestoreBindingOrValue
    }
    property Timer scan: Timer {
        interval: 250; repeat: true; running: root.active && root.grid!==null
        onTriggered: root.refresh()
    }
    property Connections gridChanges: Connections {
        target: root.grid; ignoreUnknownSignals: true
        function onCountChanged() { Qt.callLater(root.refresh) }
    }
    property Connections delegateChanges: Connections {
        target: root.grid ? root.grid.contentItem : null; ignoreUnknownSignals: true
        function onChildrenChanged() { Qt.callLater(root.refresh) }
    }
    property Connections modelChanges: Connections {
        target: root.menuModel ? root.menuModel.items : null; ignoreUnknownSignals: true
        function onChanged() { Qt.callLater(root.refresh) }
    }
    onActiveChanged: refresh()
    onGridChanged: refresh()
    onMenuModelChanged: refresh()
    Component.onCompleted: refresh()
    Component.onDestruction: active=false
}
