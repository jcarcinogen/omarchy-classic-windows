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
      bar_color = "rgb(2a2a2a)",
      ["col.text"] = "rgb(f0f0f0)",
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

local function float_size()
  local m = hl.get_active_monitor()
  local scale = m.scale
  if scale == nil or scale < 0.1 then
    scale = 1
  end
  local mw = m.width / scale
  local mh = m.height / scale
  return math.floor(mw * 0.55), math.floor(mh * 0.60)
end

hl.on("window.open", function(w)
  if w ~= nil and not w.floating then
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
    set_nobar(false, w)
    local fw, fh = float_size()
    hl.dispatch(hl.dsp.window.resize({ x = fw, y = fh, relative = false, window = w }))
    hl.dispatch(hl.dsp.window.center({ window = w }))
  else
    set_nobar(true, w)
  end
end)
