-- Floating island desktop shell for Omarchy.
--
-- Loaded from ~/.config/hypr/hyprland.lua with:
--
--   require("hypr.quickshell-islands")
--
-- The module name must live under the "hypr." prefix: Omarchy's Lua
-- bootstrap only clears package.loaded for the "default.hypr", "hypr" and
-- "omarchy.current.theme" prefixes, so a top-level module would never be
-- re-executed by `hyprctl reload`.
--
-- This file is the single source of truth for everything the islands need
-- from Hyprland. install.sh removes the equivalent hand-written blocks from
-- bindings.lua, looknfeel.lua and autostart.lua so nothing is bound twice.

-- Ensure ~/.local/bin takes precedence over /usr/share/omarchy/bin for custom user shims
local home = os.getenv("HOME")
if home and home ~= "" then
  hl.env("PATH", home .. "/.local/bin:" .. (os.getenv("PATH") or ""))
end

local bin = (home and home ~= "") and (home .. "/.local/bin/") or ""

local M = {}

-- The shell's global shortcuts are registered by the Quickshell instance and
-- dispatched straight into its event loop, so a keypress never spawns a
-- process. Unbinding first drops the Omarchy default for that combination.
M.bindings = {
  { key = "SUPER + SPACE", desc = "Omarchy menu", dispatch = "quickshell:menuToggle" },
  { key = "SUPER + ALT + SPACE", desc = "Apps menu", dispatch = "quickshell:appsToggle" },
  { key = "SUPER + CTRL + W", desc = "Wifi HUD and Panel", dispatch = "quickshell:wifiToggle" },
  { key = "SUPER + CTRL + B", desc = "Bluetooth HUD and Panel", dispatch = "quickshell:bluetoothToggle" },
  { key = "SUPER + CTRL + T", desc = "Time HUD and Panel", dispatch = "quickshell:timeToggle" },
  { key = "SUPER + CTRL + P", desc = "Power HUD and Panel", dispatch = "quickshell:batteryToggle" },
  { key = "SUPER + CTRL + D", desc = "Brightness HUD and Panel", dispatch = "quickshell:brightnessToggle" },
  { key = "SUPER + CTRL + SPACE", desc = "Wallpaper switcher", dispatch = "quickshell:wallpaperToggle" },
  { key = "SUPER + SHIFT + CTRL + SPACE", desc = "Theme switcher", dispatch = "quickshell:themeToggle" },
  { key = "SUPER + ALT + N", desc = "Notification DND toggle", dispatch = "quickshell:notifToggle" },
  { key = "SUPER + ALT + M", desc = "Microphone mute toggle", dispatch = "quickshell:micToggle" },
}

-- Hardware keys. Omarchy binds these to the same command names by default;
-- the shims in ~/.local/bin shadow the packaged binaries, so the islands HUD
-- answers instead of the stock OSD.
M.hardware_bindings = {
  { key = "XF86AudioRaiseVolume", desc = "Volume up", cmd = bin .. "omarchy-audio-output-volume +10" },
  { key = "XF86AudioLowerVolume", desc = "Volume down", cmd = bin .. "omarchy-audio-output-volume -10" },
  { key = "XF86MonBrightnessUp", desc = "Brightness up", cmd = bin .. "omarchy-brightness-display +10%" },
  { key = "XF86MonBrightnessDown", desc = "Brightness down", cmd = bin .. "omarchy-brightness-display 10%-" },
  { key = "XF86AudioMicMute", desc = "Microphone mute toggle", cmd = "omarchy-audio-input-mute" },
}

-- Panel surfaces that get the compositor-level X-Ray blur: a hairline border
-- rendered at near-zero opacity acts as an aperture, so only the frosted
-- edge around each island is blurred and the interior stays crisp.
--
-- Only the panel surfaces are listed. The full-screen backdrops
-- (quickshell-wallpaper-grid) and the invisible twin-dismiss catchers
-- (wifi-panel-twin-dismiss, bluetooth-panel-twin-dismiss) are deliberately
-- excluded: they are opaque or fully transparent, so blurring them does
-- nothing but costs a pass.
M.island_namespaces = {
  "workspaces-panel-main",
  "time-panel-main",
  "wifi-panel-main",
  "bluetooth-panel-main",
  "audio-panel-main",
  "brightness-panel-main",
  "battery-panel-main",
  "notification-panel-main",
  "toggle-panel-main",
  "quickshell-omarchy-menu",
  "scoop-v2-inspector",
  "quickshell",
}

local function escape_pattern(text)
  -- Hyprland matches namespaces with a regular expression, so only the
  -- characters that are metacharacters there need escaping. The namespace
  -- names here are plain lowercase and dashes.
  return (text:gsub("([%.%+%[%]%(%)%^%$%|%?%*%\\])", "%%%1"))
end

-- The X-Ray effect needs the global decoration blur.
--
-- A layer rule asking for xray does nothing while
-- decoration:blur:enabled is false, which is Omarchy's default. The layer
-- rule below would then be applied and produce no visible effect at all.
--
-- The shell therefore owns these settings rather than depending on the
-- user's look'n'feel: without them the islands render flat, which is the
-- single most visible difference between the shell working and not.
--
-- The values match the ones this desktop was tuned with, so on a machine
-- that already has them the result is identical. The rounding matches
-- Theme.rounding, so the island corners line up with the window corners.
function M.decorations()
  hl.config({
    general = {
      -- The gaps are part of the same calculation as the shell's own
      -- border. The scoops are drawn with a 4px border, the same as
      -- gaps_out, and the gap between two windows is the same again, so
      -- the islands and the windows sit in one rhythm.
      gaps_in = 2,
      gaps_out = 4,
      border_size = 0,
    },
    decoration = {
      rounding = 20,

      blur = {
        enabled = true,
        size = 10,
        passes = 2,
        noise = 0.15,
        contrast = 0.75,
      },
    },
  })
end

function M.apply()
  for _, binding in ipairs(M.bindings) do
    hl.unbind(binding.key)
    o.bind(binding.key, binding.desc, hl.dsp.global(binding.dispatch))
  end

  for _, binding in ipairs(M.hardware_bindings) do
    hl.unbind(binding.key)
    o.bind(binding.key, binding.desc, binding.cmd, { locked = true, repeating = true })
  end

  local namespaces = {}
  for _, namespace in ipairs(M.island_namespaces) do
    table.insert(namespaces, escape_pattern(namespace))
  end

  hl.layer_rule({
    match = { namespace = "^(" .. table.concat(namespaces, "|") .. ")$" },
    blur = true,
    xray = true,
    ignore_alpha = 0.005,
  })
end

-- The wallpaper bridge keeps awww in sync with Omarchy's background state,
-- and the shell itself is started here so the islands come up with the
-- session. --no-duplicate keeps a second launcher from spawning a rival
-- instance.
function M.autostart()
  o.launch_on_start(os.getenv("HOME") .. "/.local/bin/awww-omarchy-bridge")
  o.launch_on_start("qs --no-duplicate")
end

M.decorations()
M.apply()
M.autostart()

return M
