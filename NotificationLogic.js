// Pure logic for the notification toast panel. No QML imports, no side effects,
// so every rule here is unit-testable and can be reasoned about on its own.

// Popup lifetimes, in milliseconds. A sender's requested expire_timeout is
// honoured only inside this band; anything shorter or longer is clamped.
// Critical notifications ignore the band entirely and are sticky.
var LOW_POPUP_DURATION = 5000
var NORMAL_POPUP_DURATION = 8000
var MAX_POPUP_DURATION = 30000

function requestedDuration(expireTimeout) {
  var ms = Number(expireTimeout || 0)
  if (!isFinite(ms) || ms <= 0) return 0
  return Math.round(ms)
}

// Returns 0 for "never expire", which is how the stock service spells sticky.
function durationFor(urgency, expireTimeout, criticalUrgency) {
  var critical = criticalUrgency === undefined ? 2 : criticalUrgency
  if (urgency === critical) return 0

  var requested = requestedDuration(expireTimeout)
  if (urgency === 0) {
    // Low
    return Math.min(MAX_POPUP_DURATION, Math.max(LOW_POPUP_DURATION, requested))
  }
  return Math.min(MAX_POPUP_DURATION, Math.max(NORMAL_POPUP_DURATION, requested))
}

// Two bypasses only, both deliberate:
//   - omarchy-action is Omarchy's own "you just did a thing" feedback. Silencing
//     the toast that answers the user's own action feels broken.
//   - notify-send at critical urgency is a bare-CLI emergency alert. Chat apps
//     abuse urgency=critical but set app_name to their brand, so they fall
//     outside this rule and are still silenced.
function shouldBypassDnd(notification, criticalUrgency) {
  var critical = criticalUrgency === undefined ? 2 : criticalUrgency
  var appName = String((notification && notification.appName) || "")
  if (appName === "omarchy-action") return true
  return appName === "notify-send" && notification && notification.urgency === critical
}

function isEphemeralApp(appName) {
  var name = String(appName || "")
  return name === "notify-send" || name === "omarchy-action"
}

// Transient notifications are dropped outright while silenced rather than
// queued, because they are by definition not worth remembering.
function isEphemeral(notification) {
  var transient = false
  try {
    transient = !!(notification && notification.hints && notification.hints["transient"])
  } catch (e) {
    transient = false
  }
  return transient || isEphemeralApp(String((notification && notification.appName) || ""))
}

// omarchy-notification-send passes its glyph through a custom hint rather than
// the app_icon field, so it is read from here.
function glyphFromHints(hints) {
  try {
    if (hints && hints["omarchy-glyph"]) return String(hints["omarchy-glyph"])
  } catch (e) { }
  return ""
}

// The click action is a JSON argv array, never a shell string: argv is passed to
// execve directly, so a notification body can never be reinterpreted as a
// command.
function parseExecArgv(raw) {
  if (!raw) return null
  var parsed
  try {
    parsed = JSON.parse(String(raw))
  } catch (e) {
    return null
  }
  if (!Array.isArray(parsed) || parsed.length === 0) return null
  var out = []
  for (var i = 0; i < parsed.length; i++) {
    var value = parsed[i]
    if (value === null || value === undefined) return null
    out.push(String(value))
  }
  return out
}

function execArgvFromHints(hints) {
  try {
    if (hints && hints["omarchy-exec-argv"]) return String(hints["omarchy-exec-argv"])
  } catch (e) { }
  return ""
}

// <b>, <i>, <u> and <a> survive; <img> is stripped because bodyImagesSupported is
// not advertised, and a sender that emitted one would otherwise leave a broken
// image placeholder. Everything else is escaped so a body can never inject
// styled-text markup of its own.
function sanitizeBody(body) {
  var text = String(body || "")
  if (!text) return ""

  var out = ""
  var i = 0
  while (i < text.length) {
    var c = text.charAt(i)
    if (c !== "<") { out += escapeText(c); i++; continue }

    var close = text.indexOf(">", i)
    if (close === -1) { out += escapeText(c); i++; continue }

    var tag = text.substring(i + 1, close)
    var lower = tag.toLowerCase().trim()
    var name = lower.split(/[\s\/>]/)[0]

    if (name === "img") { i = close + 1; continue }
    if (name === "br") { out += "<br>"; i = close + 1; continue }
    if (name === "b" || name === "strong") { out += "<b>"; i = close + 1; continue }
    if (name === "i" || name === "em") { out += "<i>"; i = close + 1; continue }
    if (name === "u") { out += "<u>"; i = close + 1; continue }

    if (name === "/b" || name === "/strong") { out += "</b>"; i = close + 1; continue }
    if (name === "/i" || name === "/em") { out += "</i>"; i = close + 1; continue }
    if (name === "/u") { out += "</u>"; i = close + 1; continue }

    // An <a href> keeps only the label: links are not activated by this panel,
    // and rendering the href would invite the belief that they are.
    if (name === "a") {
      var end = lower.indexOf("</a>")
      var label = ""
      if (end !== -1) label = text.substring(close + 1, i + end)
      out += escapeText(label.replace(/<[^>]*>/g, ""))
      i = end === -1 ? close + 1 : i + end + 4
      continue
    }
    if (name === "/a") { i = close + 1; continue }

    // Unknown tag: drop the markup, keep nothing.
    i = close + 1
  }
  return out
}

function escapeText(value) {
  return String(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
}

// omarchy-action sends headlines that already begin with the glyph followed by
// two spaces; showing the icon slot as well would double it up.
function summaryStartsWithGlyph(summary) {
  var text = String(summary || "")
  if (!text.startsWith("__ ")) return false
  var glyph = text.substring(0, 2)
  return glyph.length === 2 && glyph.charCodeAt(0) > 0x2000
}

function shouldRenderCompactGlyph(glyph, smallIconSource, singleLineToast) {
  if (!glyph) return false
  if (!singleLineToast) return false
  return !smallIconSource
}

// Newest first, which is the order the stack renders in.
function sortPopups(rows) {
  var list = Array.isArray(rows) ? rows.slice() : []
  list.sort(function (a, b) {
    return (b.timestamp || 0) - (a.timestamp || 0)
  })
  return list
}
