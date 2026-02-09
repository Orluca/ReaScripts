-- @noindex

local constants = require("data.constants")
local mathx = require("utils.math")
local articulations = require("data.articulations")
local midi_input = require("midi.input")
local settings = require("UI.settings.settings")

local keyboard = {}

local STEPS = {0, 0, 1, 1, 2, 3, 3, 4, 4, 5, 5, 6}

local NOTE_IS_BLACK = {}
local NOTE_WHITE_OFFSET = {}
do
  -- Precompute note metadata once; avoids `%` and `math.floor` hot-path work per frame.
  for note = 0, 127 do
    local o = note % 12
    NOTE_IS_BLACK[note] = (o == 1 or o == 3 or o == 6 or o == 8 or o == 10)
    NOTE_WHITE_OFFSET[note] = (math.floor(note / 12) * 7) + STEPS[o + 1]
  end
end

-- Reused key objects (absolute positions are updated each frame).
local live_keys = {}
for note = 0, 127 do
  live_keys[note] = { note = note, black = NOTE_IS_BLACK[note] }
end

-- Cached layout geometry, keyed by note range + integer sizes.
local layout_cache = {}

local font_cache = {}
local MIN_LABEL_FONT_SIZE = 8

-- Subtle hover feedback values.
local HOVER_DARKEN = 0.20
local HOVER_LIGHTEN = 0.08

-- Active/pressed visual feedback values.
-- Decide whether to lighten or darken based on the final fill color
-- so zone-colored keys don't always brighten just because they're black keys.
local ACTIVE_DARKEN = 0.18
local ACTIVE_LIGHTEN = 0.20
local ACTIVE_BRIGHTNESS_THRESHOLD = 0.40 -- 0..1, lower = lighten only near-black

-- Mouse-to-MIDI settings.
local MIDI_MODE = 0
local MIDI_CHANNEL = 0
local STATUS_NOTE_ON = 0x90 + MIDI_CHANNEL
local STATUS_NOTE_OFF = 0x80 + MIDI_CHANNEL

local mouse_midi = {
  captured = false,
  active_note = nil
}

-- Zone hover label (used for tooltip + info line).
local ZONE_TOOLTIP_GRACE_FRAMES = 2
local zone_hover = {
  label = nil,
  grace_frames = 0
}

-- Zone played label (used for info line).
local zone_play = {
  label = nil
}

-- Trigger note hover label (used for tooltip + info line).
local TRIGGER_TOOLTIP_GRACE_FRAMES = 2
local trigger_hover = {
  name = nil,
  grace_frames = 0
}


local function adjust_brightness(color, delta)
  local r = (color >> 24) & 0xFF
  local g = (color >> 16) & 0xFF
  local b = (color >> 8) & 0xFF
  local a = color & 0xFF

  if delta >= 0 then
    r = r + (255 - r) * delta
    g = g + (255 - g) * delta
    b = b + (255 - b) * delta
  else
    local factor = 1 + delta
    r = r * factor
    g = g * factor
    b = b * factor
  end

  r = mathx.clamp_byte(r)
  g = mathx.clamp_byte(g)
  b = mathx.clamp_byte(b)

  return (r << 24) | (g << 16) | (b << 8) | a
end

local function get_brightness(color)
  local r = (color >> 24) & 0xFF
  local g = (color >> 16) & 0xFF
  local b = (color >> 8) & 0xFF
  return math.max(r, g, b) / 255
end

local function get_label_font(ctx, size)
  local font_size = math.max(MIN_LABEL_FONT_SIZE, mathx.round(size))
  local font = font_cache[font_size]
  if not font then
    font = ImGui.CreateFont("sans-serif", font_size)
    ImGui.Attach(ctx, font)
    font_cache[font_size] = font
  end
  return font, font_size
end

local function send_note_on(note, velocity)
  reaper.StuffMIDIMessage(MIDI_MODE, STATUS_NOTE_ON, note, velocity)
end

local function send_note_off(note)
  reaper.StuffMIDIMessage(MIDI_MODE, STATUS_NOTE_OFF, note, 0)
end

local function compute_velocity(key, my)
  local height = math.max(1, key.y2 - key.y1)
  local t = (my - key.y1) / height
  t = math.max(0, math.min(1, t))
  return math.max(1, math.min(127, math.floor(t * 126) + 1))
end

--- Returns per-key sizes for the keyboard, optionally scaled.
---@param scale number|nil Scale multiplier (1 = default)
---@return table sizes Table with white_w, white_h, black_w, black_h
local function get_sizes(scale)
  local s = scale or 1
  return {
    white_w = math.floor(18 * s),
    white_h = math.floor(90 * s),
    black_w = math.floor(10 * s),
    black_h = math.floor(56 * s)
  }
end

--- Normalize a low/high MIDI note range.
---@param low integer|nil
---@param high integer|nil
---@return integer low_note
---@return integer high_note
local function normalize_note_range(low, high)
  local lo = math.floor(tonumber(low) or 0)
  local hi = math.floor(tonumber(high) or 127)
  lo = math.max(0, math.min(127, lo))
  hi = math.max(0, math.min(127, hi))
  if lo > hi then
    lo, hi = hi, lo
  end
  return lo, hi
end

local function make_layout_cache_key(sizes, low_note, high_note)
  -- Pack into a <=48-bit integer (safe in Lua's double number representation).
  return (low_note & 0xFF) |
         ((high_note & 0xFF) << 8) |
         ((sizes.white_w & 0xFF) << 16) |
         ((sizes.white_h & 0xFF) << 24) |
         ((sizes.black_w & 0xFF) << 32) |
         ((sizes.black_h & 0xFF) << 40)
end

local function get_layout_entry(sizes, low_note, high_note)
  local lo, hi = normalize_note_range(low_note, high_note)
  local key = make_layout_cache_key(sizes, lo, hi)
  local entry = layout_cache[key]
  if entry then
    return entry
  end

  local base_offset = NOTE_WHITE_OFFSET[lo] or 0
  local black_x_offset = math.floor(sizes.white_w * 0.7)

  local white_notes = {}
  local black_notes = {}
  local rel_x1 = {}
  local rel_x2 = {}
  local rel_h = {}

  local width = 0
  for note = lo, hi do
    local black = NOTE_IS_BLACK[note]
    local off = (NOTE_WHITE_OFFSET[note] or 0) - base_offset

    -- `off * sizes.white_w` is always an integer, so
    -- floor(sx + integer) == floor(sx) + integer.
    local x1 = (off * sizes.white_w) + (black and black_x_offset or 0)
    local w = black and sizes.black_w or sizes.white_w
    local h = black and sizes.black_h or sizes.white_h
    local x2 = x1 + w

    rel_x1[note] = x1
    rel_x2[note] = x2
    rel_h[note] = h

    if black then
      black_notes[#black_notes + 1] = note
    else
      white_notes[#white_notes + 1] = note
    end

    if x2 > width then
      width = x2
    end
  end

  entry = {
    lo = lo,
    hi = hi,
    width = width,
    height = sizes.white_h,
    white_notes = white_notes,
    black_notes = black_notes,
    rel_x1 = rel_x1,
    rel_x2 = rel_x2,
    rel_h = rel_h
  }
  layout_cache[key] = entry
  return entry
end


--- Returns keyboard dimensions and sizes for a given visible note range.
---@param scale number|nil Scale multiplier (1 = default)
---@param low_note integer|nil Lowest visible MIDI note (0-127)
---@param high_note integer|nil Highest visible MIDI note (0-127)
---@return number width
---@return number height
---@return table sizes Table with white_w, white_h, black_w, black_h
local function get_dimensions(scale, low_note, high_note)
  local sizes = get_sizes(scale)
  local entry = get_layout_entry(sizes, low_note, high_note)
  return entry.width, entry.height, sizes
end


local function blend_colors(base, overlay, strength)
  overlay = overlay or 0
  local a = (overlay & 0xFF) / 255
  a = math.max(0, math.min(1, a * (strength or 1)))
  if a <= 0 then
    return base
  end

  local br = (base >> 24) & 0xFF
  local bg = (base >> 16) & 0xFF
  local bb = (base >> 8) & 0xFF
  local ba = base & 0xFF

  local orr = (overlay >> 24) & 0xFF
  local og = (overlay >> 16) & 0xFF
  local ob = (overlay >> 8) & 0xFF

  local inv = 1 - a
  local r = mathx.clamp_byte((br * inv) + (orr * a))
  local g = mathx.clamp_byte((bg * inv) + (og * a))
  local b = mathx.clamp_byte((bb * inv) + (ob * a))

  return (r << 24) | (g << 16) | (b << 8) | ba
end

local function build_zone_maps(art)
  local zones = (type(art) == "table" and type(art.zones) == "table") and art.zones or nil
  if not zones then
    return {}, {}
  end

  local colors = {}
  local labels = {}

  for _, z in ipairs(zones) do
    if type(z) == "table" then
      local s = tonumber(z.start_note)
      local e = tonumber(z.end_note)
      if s and e then
        local lo = math.max(0, math.min(127, math.min(s, e)))
        local hi = math.max(0, math.min(127, math.max(s, e)))

        local mode = tonumber(z.mode) or constants.zone_mode.chromatic
        local color = tonumber(z.color) or (settings.default_zone_color or constants.zones.DEFAULT_COLOR)
        local label = (type(z.label) == "string" and z.label ~= "") and z.label or nil

        for note = lo, hi do
          local black = NOTE_IS_BLACK[note]
          local match = (mode == constants.zone_mode.chromatic) or
                        (mode == constants.zone_mode.white and not black) or
                        (mode == constants.zone_mode.black and black)
          if match then
            -- Later zones override earlier zones (same behavior as the old script).
            colors[note] = color
            labels[note] = label -- nil clears any previous label
          end
        end
      end
    end
  end

  return colors, labels
end


local function build_trigger_maps(items, color)
  if type(items) ~= "table" then
    return {}, {}
  end

  local colors = {}
  local names = {}

  local function add_note(note, name)
    note = tonumber(note)
    note = note and math.floor(note)
    if not note or note < 0 or note > 127 then
      return
    end

    colors[note] = color

    local existing = names[note]
    if type(existing) == "string" and existing ~= "" then
      if existing ~= name then
        names[note] = existing .. ", " .. name
      end
    else
      names[note] = name
    end
  end

  for _, art in ipairs(items) do
    if type(art) == "table" then
      local trig = (type(art.trigger) == "table") and art.trigger or nil
      if trig then
        local name = (type(art.name) == "string" and art.name ~= "") and art.name or "<unnamed>"

        if trig.type == midi_input.MSG_TYPE.note_on then
          if trig.keyswitch_note ~= nil then
            add_note(trig.keyswitch_note, name)
          else
            add_note(trig.val1, name)
          end
        elseif trig.type == midi_input.MSG_TYPE.cc or trig.type == midi_input.MSG_TYPE.pc then
          add_note(trig.keyswitch_note, name)
        end
      end
    end
  end

  return colors, names
end
local function update_zone_hover(state, zone_labels)
  local note = state and state.hovered_note or nil

  if note ~= nil then
    local label = zone_labels and zone_labels[note] or nil
    if type(label) == "string" and label ~= "" then
      zone_hover.label = label
      zone_hover.grace_frames = 0
    else
      -- When hovering a key that is not in a labeled zone, clear immediately.
      zone_hover.label = nil
      zone_hover.grace_frames = 0
    end
    return
  end

  -- Grace period to avoid tooltip flicker when moving between adjacent keys.
  if zone_hover.label ~= nil then
    zone_hover.grace_frames = zone_hover.grace_frames + 1
    if zone_hover.grace_frames > ZONE_TOOLTIP_GRACE_FRAMES then
      zone_hover.label = nil
      zone_hover.grace_frames = 0
    end
  end
end

local function update_played_zone_label(state, zone_labels)
  local midi_active = state and state.midi_active or nil
  if type(midi_active) ~= "table" then
    zone_play.label = nil
    return
  end

  local label = nil
  for note = 0, 127 do
    if midi_active[note] ~= nil then
      local l = zone_labels and zone_labels[note] or nil
      if type(l) == "string" and l ~= "" then
        label = l
        break
      end
    end
  end

  zone_play.label = label
end


local function update_trigger_hover(state, trigger_names)
  local note = state and state.hovered_note or nil

  if note ~= nil then
    local name = trigger_names and trigger_names[note] or nil
    if type(name) == "string" and name ~= "" then
      trigger_hover.name = name
      trigger_hover.grace_frames = 0
    else
      trigger_hover.name = nil
      trigger_hover.grace_frames = 0
    end
    return
  end

  if trigger_hover.name ~= nil then
    trigger_hover.grace_frames = trigger_hover.grace_frames + 1
    if trigger_hover.grace_frames > TRIGGER_TOOLTIP_GRACE_FRAMES then
      trigger_hover.name = nil
      trigger_hover.grace_frames = 0
    end
  end
end
local function draw_keyboard_tooltip(ctx)
  if zone_hover.label == nil and trigger_hover.name == nil then
    return
  end

  if ImGui.BeginTooltip(ctx) then
    if zone_hover.label ~= nil then
      ImGui.Text(ctx, zone_hover.label)
    end
    if trigger_hover.name ~= nil then
      ImGui.Text(ctx, "KS: " .. trigger_hover.name)
    end
    ImGui.EndTooltip(ctx)
  end
end

-- Layout: compute all key rectangles in screen space.
local function build_layout(sx, sy, sizes, low_note, high_note)
  local entry = get_layout_entry(sizes, low_note, high_note)

  local base_x = math.floor(sx)
  local base_y = sy

  local rel_x1 = entry.rel_x1
  local rel_x2 = entry.rel_x2
  local rel_h = entry.rel_h

  local white_notes = entry.white_notes
  local black_notes = entry.black_notes

  for i = 1, #white_notes do
    local note = white_notes[i]
    local key = live_keys[note]
    key.x1 = base_x + rel_x1[note]
    key.y1 = base_y
    key.x2 = base_x + rel_x2[note]
    key.y2 = base_y + rel_h[note]
  end

  for i = 1, #black_notes do
    local note = black_notes[i]
    local key = live_keys[note]
    key.x1 = base_x + rel_x1[note]
    key.y1 = base_y
    key.x2 = base_x + rel_x2[note]
    key.y2 = base_y + rel_h[note]
  end

  return live_keys, white_notes, black_notes
end

local function point_in_rect(mx, my, key)
  return mx >= key.x1 and mx < key.x2 and my >= key.y1 and my < key.y2
end

-- State: resolve hover (black keys win when overlapping white keys).
local function get_hovered_key(ctx, keys, white_notes, black_notes)
  local mx, my = ImGui.GetMousePos(ctx)

  for i = 1, #black_notes do
    local note = black_notes[i]
    local key = keys[note]
    if key and point_in_rect(mx, my, key) then
      return note, key, mx, my
    end
  end

  for i = 1, #white_notes do
    local note = white_notes[i]
    local key = keys[note]
    if key and point_in_rect(mx, my, key) then
      return note, key, mx, my
    end
  end

  return nil, nil, mx, my
end

local function build_state(ctx, keys, white_notes, black_notes, midi_active)
  local hovered_note, hovered_key, mx, my = get_hovered_key(ctx, keys, white_notes, black_notes)
  return {
    hovered_note = hovered_note,
    hovered_key = hovered_key,
    mx = mx,
    my = my,
    mouse_down = ImGui.IsMouseDown(ctx, ImGui.MouseButton_Left),
    mouse_clicked = ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left),
    mouse_released = ImGui.IsMouseReleased(ctx, ImGui.MouseButton_Left),
    mouse_active_note = mouse_midi.active_note,
    midi_active = midi_active or {}
  }
end

local function update_mouse_midi(state)
  if state.mouse_clicked then
    mouse_midi.captured = state.hovered_note ~= nil
  end

  if state.mouse_released then
    if mouse_midi.active_note ~= nil then
      send_note_off(mouse_midi.active_note)
      mouse_midi.active_note = nil
    end
    mouse_midi.captured = false
    return
  end

  if not mouse_midi.captured or not state.mouse_down then
    return
  end

  if state.hovered_note ~= nil and state.hovered_key ~= nil then
    if mouse_midi.active_note ~= state.hovered_note then
      if mouse_midi.active_note ~= nil then
        send_note_off(mouse_midi.active_note)
      end

      local velocity = compute_velocity(state.hovered_key, state.my)
      send_note_on(state.hovered_note, velocity)
      mouse_midi.active_note = state.hovered_note
    end
  end
end

local function is_note_active(state, note)
  return state.mouse_active_note == note or state.midi_active[note] ~= nil
end

-- Render: draw from state.
local function draw_keys(dl, keys, colors, state, zone_colors, zone_strength, trigger_colors, trigger_strength, white_notes, black_notes)
  for pass = 1, 2 do
    local notes = (pass == 1) and white_notes or black_notes
    for i = 1, #notes do
      local note = notes[i]
      local key = keys[note]
      if key then
        local fill = key.black and colors.BLACK_FILL or colors.WHITE_FILL
        local zone_color = zone_colors and zone_colors[note] or nil
        if zone_color then
          fill = blend_colors(fill, zone_color, zone_strength)
        end

        local trigger_color = trigger_colors and trigger_colors[note] or nil
        if trigger_color then
          fill = blend_colors(fill, trigger_color, trigger_strength)
        end

        -- Priority: active > hover > base
        if is_note_active(state, note) then
          local brightness = get_brightness(fill)
          local delta = (brightness < ACTIVE_BRIGHTNESS_THRESHOLD) and ACTIVE_LIGHTEN or -ACTIVE_DARKEN
          fill = adjust_brightness(fill, delta)
        elseif state.hovered_note == note then
          fill = adjust_brightness(fill, key.black and HOVER_LIGHTEN or -HOVER_DARKEN)
        end

        ImGui.DrawList_AddRectFilled(dl, key.x1, key.y1, key.x2, key.y2, fill)
        ImGui.DrawList_AddRect(dl, key.x1, key.y1, key.x2, key.y2, colors.BORDER)
      end
    end
  end
end

local function should_draw_c_labels(scale)
  return (scale or 1) >= 1.00
end

local function get_c_octave(note, middle_c_mode)
  local base = (middle_c_mode == 4) and -1 or -2
  return math.floor(note / 12) + base
end

local function draw_c_labels(ctx, dl, keys, low_note, high_note, sizes, scale, middle_c_mode, colors)
  if not should_draw_c_labels(scale) then
    return
  end

  local s = scale or 1
  local base_font_size = ImGui.GetFontSize(ctx)
  local desired_size = base_font_size * s * 0.75
  local font, font_size = get_label_font(ctx, desired_size)
  local padding = math.max(4, mathx.round(6 * s))
  local color = colors.C_LABEL or colors.BORDER

  ImGui.PushFont(ctx, font, font_size)

  local lo, hi = normalize_note_range(low_note, high_note)

  local first_c = lo + ((12 - (lo % 12)) % 12)
  for note = first_c, hi, 12 do
    local key = keys[note]
    if key and not key.black then
      local octave = get_c_octave(note, middle_c_mode)
      local label = "C" .. tostring(octave)

      local text_w, _ = ImGui.CalcTextSize(ctx, label)
      local text_x = mathx.round(key.x1 + (sizes.white_w - text_w) * 0.5)
      local text_y = key.y1 + sizes.white_h - padding - font_size

      ImGui.DrawList_AddTextEx(
        dl,
        font,
        font_size,
        text_x,
        text_y,
        color,
        label,
        0.0,
        key.x1,
        key.y1,
        key.x2,
        key.y2
      )
    end
  end

  ImGui.PopFont(ctx)
end

function keyboard.get_sizes(scale)
  return get_sizes(scale)
end

function keyboard.get_dimensions(scale, low_note, high_note)
  return get_dimensions(scale, low_note, high_note)
end

function keyboard.get_hovered_zone_label()
  return zone_hover.label
end

function keyboard.get_played_zone_label()
  return zone_play.label
end

function keyboard.get_hovered_trigger_articulation_name()
  return trigger_hover.name
end

--- Draw the keyboard.
---@param ctx ImGui_Context
---@param sizes table|nil Precomputed sizes table
---@param opts table|nil Options: { scale = number, middle_c_mode = number, low_note = integer, high_note = integer, zone_color_strength = number, hide_zone_tooltip = boolean, hide_trigger_notes = boolean, hide_key_labels = boolean, trigger_note_color = integer }
function keyboard.draw(ctx, sizes, opts)
  opts = opts or {}
  local scale = opts.scale or 1
  local middle_c_mode = opts.middle_c_mode or 3
  local lo_default, hi_default = normalize_note_range(opts.low_note, opts.high_note)
  opts.low_note = lo_default
  opts.high_note = hi_default

  local dl = ImGui.GetWindowDrawList(ctx)
  local sx, sy = ImGui.GetCursorScreenPos(ctx)

  sizes = sizes or get_sizes(scale)

  local low_note = opts.low_note
  local high_note = opts.high_note
  local keys, white_notes, black_notes = build_layout(sx, sy, sizes, low_note, high_note)
  local state = build_state(ctx, keys, white_notes, black_notes, midi_input.get_active_notes())
  local zone_colors, zone_labels = build_zone_maps(articulations.get_active())

  local hide_trigger_notes = opts.hide_trigger_notes or false
  local trigger_colors, trigger_names = {}, {}
  if not hide_trigger_notes then
    local trigger_color = tonumber(opts.trigger_note_color) or settings.trigger_note_color or constants.keyboard.TRIGGER_NOTE_COLOR
    trigger_colors, trigger_names = build_trigger_maps(articulations.items, trigger_color)
  else
    trigger_hover.name = nil
    trigger_hover.grace_frames = 0
  end

  local strength_pct = tonumber(opts.zone_color_strength)
  if strength_pct == nil then
    strength_pct = constants.zones.COLOR_STRENGTH_DEFAULT or 70
  end
  strength_pct = math.max(0, math.min(100, math.floor(strength_pct)))
  local zone_strength = strength_pct / 100

  update_zone_hover(state, zone_labels)
  update_played_zone_label(state, zone_labels)
  update_trigger_hover(state, trigger_names)
  update_mouse_midi(state)
  draw_keys(dl, keys, constants.keyboard, state, zone_colors, zone_strength, trigger_colors, zone_strength, white_notes, black_notes)
  if not opts.hide_key_labels then
    draw_c_labels(ctx, dl, keys, low_note, high_note, sizes, scale, middle_c_mode, constants.keyboard)
  end
  if not opts.hide_zone_tooltip then
    draw_keyboard_tooltip(ctx)
  end
end

return keyboard

