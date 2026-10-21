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
  { key = "SUPER + CTRL + SPACE", desc = "Wallpaper switcher", dispatch = "quickshell:wallpaperToggle" },
}

-- Hardware keys. Omarchy binds these to the same command names by default;
-- the shims in ~/.local/bin shadow the packaged binaries, so the islands HUD
-- answers instead of the stock OSD.
M.hardware_bindings = {
  { key = "XF86AudioRaiseVolume", desc = "Volume up", cmd = "omarchy-audio-output-volume +10" },
  { key = "XF86AudioLowerVolume", desc = "Volume down", cmd = "omarchy-audio-output-volume -10" },
  { key = "XF86MonBrightnessUp", desc = "Brightness up", cmd = "omarchy-brightness-display +10%" },
  { key = "XF86MonBrightnessDown", desc = "Brightness down", cmd = "omarchy-brightness-display 10%-" },
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

M.apply()
M.autostart()

return M
