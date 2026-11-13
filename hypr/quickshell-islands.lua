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
  { key = "SUPER + ALT + C", desc = "Cursor X-Ray toggle", dispatch = "quickshell:cursorXRayToggle" },
  { key = "SUPER + ALT + I", desc = "Stay awake toggle", dispatch = "quickshell:stayAwakeToggle" },
  { key = "SUPER + ALT + L", desc = "Night light toggle", dispatch = "quickshell:nightLightToggle" },
  { key = "XF86RFKill", desc = "Airplane mode toggle", dispatch = "quickshell:airplaneToggle" },
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
  "cursor-xray-main",
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

-- The shell's user settings live in config.toml next to the QML. The shell
-- watches the file and pushes changes to Hyprland live; reading it here as
-- well keeps a `hyprctl reload` from reverting them. Only flat
-- `key = number` lines are needed, so this is not a full TOML parser.
M.config_path = (home or "") .. "/.config/quickshell/config.toml"

local function read_config()
  local config = {}
  local file = io.open(M.config_path, "r")
  if not file then
    return config
  end
  for line in file:lines() do
    local key, value = line:match("^%s*([%w_]+)%s*=%s*(%d+)")
    if key then
      config[key] = tonumber(value)
    end
  end
  file:close()
  return config
end

M.config = read_config()

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
-- that already has them the result is identical. The rounding comes from
-- the same config.toml as Theme.rounding, so the island corners line up
-- with the window corners.
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
      -- Capped at 20 like Theme.rounding: the islands are laid out for
      -- radii up to it.
      rounding = math.min(M.config.rounding or 20, 20),

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
  -- Drop Omarchy default audio binding so SUPER + CTRL + A is free
  hl.unbind("SUPER + CTRL + A")

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

  -- The pickers animate themselves: they open zoomed into the wallpaper on
  -- screen and close zoomed into the new one, so any layer animation of
  -- Hyprland's own shows up as a frame that pops in or fades out over a
  -- desktop it already matches.
  hl.layer_rule({
    match = { namespace = "^(quickshell-wallpaper-grid|quickshell-theme-grid)$" },
    no_anim = true,
    animation = "none",
  })
end

-- The shell is started here so the islands come up with the session.
-- --no-duplicate keeps a second launcher from spawning a rival instance.
-- The wallpaper is Omarchy's own (its background plugin and OWE), which
-- Omarchy starts itself.
function M.autostart()
  o.launch_on_start("qs --no-duplicate")
end

-- Tile groups: moving a whole branch of the dwindle tree at once.
--
-- Dwindle keeps a binary tree of splits, but its own commands only ever act
-- on the parent of one window, so a branch of several windows cannot be
-- moved. The shell (TileGroups.qml) works the tree out from the window
-- geometry, draws a dot on each split, and decides what the new tree should
-- be. This side then rebuilds the workspace into exactly that tree.
--
-- The rebuild floats every window but the first, then tiles them back one at
-- a time: each window is opened next to the window it was split from, with
-- the side preselected and the ratio set right after, which is the same path
-- dwindle takes for a new window. It all runs inside one call, so the
-- compositor never draws the windows half rebuilt, only the windows sliding
-- from their old places to the new ones.
--
-- A tree is { a = "<address>" } for a window, or
-- { s = "v" | "h", r = <ratio>, c = { first, second } } for a split, where
-- "v" puts the children side by side and "h" stacks them. The ratio is
-- dwindle's own, where 1 is an even split.
QsTiles = QsTiles or {}
M.tiles = QsTiles

-- Set by the shell while a dot is hovered or picked, so Super+Shift+arrows
-- moves that group instead of the active window.
QsTiles.armed = false

-- A reload must not leave the previous Super listener behind.
if QsTiles.super_watch then
  pcall(function()
    QsTiles.super_watch:remove()
  end)
  QsTiles.super_watch = nil
end

local function window_selector(address)
  return "address:" .. address
end

local function first_window(node)
  while node.c do
    node = node.c[1]
  end
  return node.a
end

local function tree_windows(node, out)
  out = out or {}
  if node.c then
    tree_windows(node.c[1], out)
    tree_windows(node.c[2], out)
  else
    table.insert(out, node.a)
  end
  return out
end

local function tile_branch(node, window)
  if not node.c then
    return
  end

  local other = first_window(node.c[2])
  hl.dispatch(hl.dsp.focus({ window = window_selector(window) }))
  hl.dispatch(hl.dsp.layout("preselect " .. (node.s == "v" and "r" or "d")))
  hl.dispatch(hl.dsp.window.float({ action = "disable", window = window_selector(other) }))
  hl.dispatch(hl.dsp.focus({ window = window_selector(window) }))
  hl.dispatch(hl.dsp.layout(string.format("splitratio %.4f exact", node.r or 1)))

  tile_branch(node.c[1], window)
  tile_branch(node.c[2], other)
end

-- Rebuild the workspace of the tree's windows into `tree`. The tree has to
-- hold exactly that workspace's tiled windows; anything else means the shell
-- worked from an old picture, and the call fails rather than guess.
--
-- Dwindle takes layout messages for the focused monitor's workspace only;
-- focusing the tree's windows on the way makes that the right one.
function QsTiles.apply(tree)
  if type(tree) ~= "table" then
    error("qs-tiles: nothing to rebuild")
  end

  local windows = tree_windows(tree)
  local anchor = hl.get_window(window_selector(windows[1]))
  local workspace = anchor and anchor.workspace
  if not workspace or not workspace.visible then
    error("qs-tiles: the workspace is not on screen")
  end
  if workspace.has_fullscreen then
    error("qs-tiles: the workspace has a fullscreen window")
  end

  local wanted = {}
  for _, address in ipairs(windows) do
    wanted[address] = true
  end

  local tiled = 0
  for _, window in ipairs(hl.get_workspace_windows(workspace.id)) do
    if window.mapped and not window.floating then
      if window.group then
        error("qs-tiles: tabbed groups are not supported")
      end
      if not wanted[window.address] then
        error("qs-tiles: the tree is out of date")
      end
      tiled = tiled + 1
    end
  end
  if tiled ~= #windows then
    error("qs-tiles: the tree is out of date")
  end

  local active = hl.get_active_window()
  local cursor = hl.get_cursor_pos()

  for index = 2, #windows do
    hl.dispatch(hl.dsp.window.float({ action = "enable", window = window_selector(windows[index]) }))
  end
  tile_branch(tree, windows[1])

  -- Focusing each window on the way warps the pointer; put both back.
  if active then
    hl.dispatch(hl.dsp.focus({ window = window_selector(active.address) }))
  end
  if cursor then
    hl.dispatch(hl.dsp.cursor.move({ x = cursor.x, y = cursor.y }))
  end
end

-- A group moved with the keys slides out from under the pointer, which would
-- drop the pick at once. The shell keeps it while Super is held and is told
-- here when Super comes up. The key listener only exists for that stretch.
--
-- Super is recognised by elimination, so a remapped Super (Caps Lock as
-- Super, say) works too: during a key move only Super, Shift and the arrows
-- are held, so a release of anything but Shift or an arrow is Super's.
local KEEP_HOLD_KEYCODES = {
  [50] = true, -- Shift_L
  [62] = true, -- Shift_R
  [111] = true, -- Up
  [113] = true, -- Left
  [114] = true, -- Right
  [116] = true, -- Down
}

local function watch_super_release()
  if QsTiles.super_watch then
    return
  end
  QsTiles.super_watch = hl.on("input.keyboard.key", function(keycode, _, state)
    if state ~= 0 or KEEP_HOLD_KEYCODES[keycode] then
      return
    end
    local watch = QsTiles.super_watch
    QsTiles.super_watch = nil
    if watch then
      pcall(function()
        watch:remove()
      end)
    end
    hl.dispatch(hl.dsp.global("quickshell:tilesHoldEnd"))
  end)
end

-- Super+Shift+arrows swaps the active window, as in Omarchy, unless a group
-- is armed: then the shell moves the group.
function QsTiles.key_move(dir)
  if QsTiles.armed then
    watch_super_release()
    local names = { l = "Left", r = "Right", u = "Up", d = "Down" }
    hl.dispatch(hl.dsp.global("quickshell:tilesMove" .. names[dir]))
  else
    hl.dispatch(hl.dsp.window.swap({ direction = dir }))
  end
end

function M.tile_bindings()
  local directions = {
    { key = "LEFT", dir = "l", desc = "left" },
    { key = "RIGHT", dir = "r", desc = "right" },
    { key = "UP", dir = "u", desc = "up" },
    { key = "DOWN", dir = "d", desc = "down" },
  }

  for _, direction in ipairs(directions) do
    local key = "SUPER + SHIFT + " .. direction.key
    hl.unbind(key)
    o.bind(key, "Swap window or tile group " .. direction.desc, function()
      QsTiles.key_move(direction.dir)
    end)
  end
end

M.decorations()
M.apply()
M.tile_bindings()
M.autostart()

return M
