.pragma library

// Bounded diagnostic records on the existing private tmpfs only. No commands.
var records = {};
var pending = {};
var request = null;
var channels = ["menu", "bridge", "controller", "runtime"];
function record(channel, event, values) {
    if (channels.indexOf(channel) < 0) return;
    if (!records[channel]) records[channel] = [];
    records[channel].push({event: event, values: values || {}});
    if (records[channel].length > 32) records[channel].shift();
    pending[channel] = JSON.stringify({channel: channel, events: records[channel]}) + "\n";
    flush();
}
function flush() {
    if (request) return;
    var channel = null;
    for (var i = 0; i < channels.length; ++i)
        if (pending[channels[i]]) { channel = channels[i]; break; }
    if (!channel) return;
    var body = pending[channel];
    delete pending[channel];
    var req = new XMLHttpRequest();
    request = req;
    req.onreadystatechange = function() {
        if (req.readyState === XMLHttpRequest.DONE) {
            request = null;
            flush();
        }
    };
    req.open("PUT", "file:///tmp/x2d-native-multishot/countdown-" + channel + ".json");
    req.send(body);
}
