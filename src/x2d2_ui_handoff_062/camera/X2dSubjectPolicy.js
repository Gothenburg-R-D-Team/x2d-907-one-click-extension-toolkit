.pragma library

// No camera writes. The only writable modes are supplied by the stock model.
function available(model, mode) {
    if (!model) return false
    for (var i = 0; i < model.length; ++i)
        if (model[i].mode === mode) return !!model[i].canSelect
    return false
}
function personMode(model, multi) {
    return available(model, multi) ? multi : -1
}
function isUnsupported(index, areasAvailable) {
    return ((index === 1 || index === 2) && !areasAvailable) || index === 3 || index === 5 || index === 6
}
function selected(index, focusIndex, subjectIndex) {
    return index === focusIndex || index === subjectIndex
}
function controlArtwork(focusIndex, subjectIndex) {
    var focus = ["spot", "spot-plus", "custom", "wide"]
    var subject = ["human", "pet", "vehicle", "off"]
    if (focusIndex < 0 || focusIndex > 3 || subjectIndex < 4 || subjectIndex > 7) return ""
    return focus[focusIndex] + "-" + subject[subjectIndex - 4]
}
function grayCombination(focusIndex, subjectIndex, areasAvailable) {
    return (focusIndex !== 0 && !(areasAvailable && focusIndex < 3)) || subjectIndex === 5 || subjectIndex === 6
}
