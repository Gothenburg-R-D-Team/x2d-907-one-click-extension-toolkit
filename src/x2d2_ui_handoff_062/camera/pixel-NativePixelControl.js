.pragma library
.import "NativePixelTrace.js" as Trace

var component;
function create(screen) {
    if (!component) component = Qt.createComponent("file:///system/etc/x2d-multishot/NativePixelControlBridge.qml");
    Trace.record("bridge", "component", {status: component.status, error: component.errorString()});
    var bridge = component.createObject(screen, {controlScreen: screen});
    if (!bridge) throw new Error(component.errorString());
    Trace.record("bridge", "created", {parent: screen.objectName});
    return bridge;
}
