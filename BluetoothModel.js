function deviceLabel(device) {
    if (!device) return ""
    return String(device.deviceName || device.name || "").trim()
}

function toArray(values) {
    if (!values) return []
    if (Array.isArray(values)) return values.slice()
    var length = Number(values.length || 0)
    if (!isFinite(length) || length <= 0) return []
    var list = []
    for (var i = 0; i < length; i++) list.push(values[i])
    return list
}

function isUuidLike(value) {
    var text = String(value || "").trim()
    if (text === "") return false
    return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(text)
        || /^[0-9a-f]{32}$/i.test(text)
        || /^0x[0-9a-f]{4,32}$/i.test(text)
        || /^0000[0-9a-f]{4}-0000-1000-8000-00805f9b34fb$/i.test(text)
}

function isAddressLike(value) {
    var text = String(value || "").trim()
    return /^([0-9a-f]{2}[:-]){5}[0-9a-f]{2}$/i.test(text)
}

function hasHumanName(device) {
    var label = deviceLabel(device)
    return label !== "" && !isUuidLike(label) && !isAddressLike(label)
}

function deviceIcon(d) {
    if (!d) return "󰂯"
    var name = (d.name || d.deviceName || "").toLowerCase()
    if (name.includes("headphone") || name.includes("headset") || name.includes("wh-") || name.includes("wf-") || name.includes("buds") || name.includes("airpods") || name.includes("earphone")) return "󰋋"
    if (name.includes("speaker") || name.includes("soundbar") || name.includes("audio") || name.includes("boom") || name.includes("echo")) return "󰓃"
    if (name.includes("keyboard") || name.includes("keychron") || name.includes("kbd")) return "󰌌"
    if (name.includes("mouse") || name.includes("trackpad") || name.includes("mx master") || name.includes("touchpad")) return "󰍽"
    if (name.includes("phone") || name.includes("iphone") || name.includes("galaxy") || name.includes("pixel")) return "󰏲"
    if (name.includes("controller") || name.includes("gamepad") || name.includes("xbox") || name.includes("dualsense") || name.includes("pro controller")) return "󰊴"
    return d.connected ? "󰂱" : "󰂯"
}

function sortedByLabel(devices) {
    var list = toArray(devices)
    list.sort(function(a, b) { return deviceLabel(a).localeCompare(deviceLabel(b)) })
    return list
}

function deviceRow(d) {
    if (!d) return null
    return {
        address: d.address || "",
        name: d.name || "",
        deviceName: d.deviceName || "",
        connected: !!d.connected,
        paired: !!(d.paired || d.bonded || d.trusted),
        batteryAvailable: !!d.batteryAvailable,
        battery: d.battery !== undefined ? d.battery : 0,
        pairing: !!d.pairing,
        deviceObject: d
    }
}

function deviceLists(devices) {
    var values = toArray(devices)
    var connected = []
    var known = []
    var discovered = []

    for (var i = 0; i < values.length; i++) {
        var d = values[i]
        if (!d || !hasHumanName(d)) continue
        if (d.connected) connected.push(d)
        else if (d.paired || d.bonded || d.trusted) known.push(d)
        else discovered.push(d)
    }

    return {
        connected: sortedByLabel(connected).map(deviceRow),
        known: sortedByLabel(known).map(deviceRow),
        discovered: sortedByLabel(discovered).map(deviceRow)
    }
}

function formatBattery(battery) {
    if (battery === undefined || battery === null || battery < 0) return ""
    return Math.round(battery * 100) + "%"
}
