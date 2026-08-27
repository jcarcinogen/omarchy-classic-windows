-- Omarchy Classic Windows
-- Native-feeling floating windows for people coming from Windows or macOS.

hl.config({
  general = {
    resize_on_border = true,
    extend_border_grab_area = 15,
    hover_icon_on_border = true,
  },
  plugin = {
    hyprbars = {
      enabled = true,
      bar_height = 24,
      bar_title_enabled = true,
      bar_text_align = "left",
      bar_buttons_alignment = "right",
      bar_part_of_window = true,
      bar_precedence_over_border = true,
      bar_color = "rgba(00000000)",
      ["col.text"] = "rgb(f0f0f0)",
      on_double_click = "hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = \"maximized\" })'",
    },
  },
})

if hl.plugin.hyprbars ~= nil then
  hl.plugin.hyprbars.add_button({
    bg_color = "rgb(ff4040)",
    fg_color = "rgb(ffffff)",
    size = 12,
    icon = "X",
    action = "hyprctl dispatch 'hl.dsp.window.close()'",
  })
end

o.window({ tag = "cw-nobar" }, {
  name = "classic-windows-no-bar",
  ["hyprbars:no_bar"] = true,
})

-- hyprland-plugins#543: removing the matched tag does not redraw the bar
-- until another tag change forces updateRules.
local function poke_hyprbars(w)
  hl.dispatch(hl.dsp.window.tag({ tag = "+cwpoke", window = w }))
  hl.dispatch(hl.dsp.window.tag({ tag = "-cwpoke", window = w }))
end

local function set_nobar(on, w)
  if on then
    hl.dispatch(hl.dsp.window.tag({ tag = "+cw-nobar", window = w }))
  else
    hl.dispatch(hl.dsp.window.tag({ tag = "-cw-nobar", window = w }))
  end
  poke_hyprbars(w)
end

local function float_size(w)
  local m = (w ~= nil and w.monitor) or hl.get_active_monitor()
  local scale = m.scale
  if scale == nil or scale < 0.1 then
    scale = 1
  end
  local mw = m.width / scale
  local mh = m.height / scale
  return math.floor(mw * 0.55), math.floor(mh * 0.60)
end

local state_home = os.getenv("XDG_STATE_HOME")
if state_home == nil or state_home == "" then
  state_home = os.getenv("HOME") .. "/.local/state"
end
local floating_mode_path = state_home .. "/omarchy-classic-windows/floating-mode.enabled"

local function marker_exists()
  local marker = io.open(floating_mode_path, "r")
  if marker == nil then
    return false
  end
  marker:close()
  return true
end

local floating_mode = marker_exists()

local function persist_floating_mode(on)
  if on then
    local marker = io.open(floating_mode_path, "w")
    if marker == nil then
      return false
    end
    marker:write("enabled\n")
    marker:close()
    return true
  end

  os.remove(floating_mode_path)
  return true
end

local function resize_and_center(w)
  local fw, fh = float_size(w)
  hl.dispatch(hl.dsp.window.resize({ x = fw, y = fh, relative = false, window = w }))
  hl.dispatch(hl.dsp.window.center({ window = w }))
end

local function auto_float(w)
  hl.dispatch(hl.dsp.window.tag({ tag = "+cw-auto-float", window = w }))
  hl.dispatch(hl.dsp.window.float({ action = "set", window = w }))
  set_nobar(false, w)
  resize_and_center(w)
end

local function restore_auto_floats_to_tiling()
  for _, w in ipairs(hl.get_windows({ tag = "cw-auto-float" })) do
    if w.fullscreen ~= 0 then
      hl.dispatch(hl.dsp.window.fullscreen({ action = "unset", window = w }))
    end
    if w.floating then
      hl.dispatch(hl.dsp.window.float({ action = "unset", window = w }))
    end
    hl.dispatch(hl.dsp.window.tag({ tag = "-cw-auto-float", window = w }))
    set_nobar(true, w)
  end
end

hl.on("window.open", function(w)
  if w == nil then
    return
  end

  if floating_mode and not w.floating then
    auto_float(w)
  elseif not w.floating then
    set_nobar(true, w)
  end
end)

hl.unbind("SUPER + T")
o.bind("SUPER + T", "Toggle window floating/tiling", function()
  local w = hl.get_active_window()
  if w == nil then
    return
  end

  local becoming_float = not w.floating
  hl.dispatch(hl.dsp.window.float({ action = "toggle", window = w }))

  if becoming_float then
    hl.dispatch(hl.dsp.window.tag({ tag = "-cw-auto-float", window = w }))
    set_nobar(false, w)
    resize_and_center(w)
  else
    hl.dispatch(hl.dsp.window.tag({ tag = "-cw-auto-float", window = w }))
    set_nobar(true, w)
  end
end)

hl.unbind("SUPER + CTRL + T")
local function toggle_floating_mode()
  floating_mode = not floating_mode
  local persisted = persist_floating_mode(floating_mode)

  if floating_mode then
    local suffix = persisted and "" or " for this session"
    hl.notification.create({
      text = "Classic Windows: new windows will float" .. suffix,
      timeout = 3000,
    })
  else
    restore_auto_floats_to_tiling()
    hl.notification.create({
      text = "Classic Windows: regular tiling restored",
      timeout = 3000,
    })
  end
end

o.bind("SUPER + CTRL + T", "Toggle automatic floating mode", toggle_floating_mode)
