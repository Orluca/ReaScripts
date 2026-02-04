-- @noindex

local constants = require("data.constants")
local mathx = require("utils.math")
local button = require("UI.widgets.button")
local color_picker = require("UI.widgets.color_picker")
local color_preset_picker = require("UI.widgets.color_preset_picker")
local input_note = require("UI.widgets.input_note")
local header = require("UI.widgets.header")

local EXT_SECTION = "Orlu_MIDI_KeyMaps"
local KEY_HIDE_INFO_LINE = "hide_info_line"
local KEY_KEYBOARD_SCALE = "keyboard_scale"
local KEY_KEYBOARD_LOW_NOTE = "keyboard_low_note"
local KEY_KEYBOARD_HIGH_NOTE = "keyboard_high_note"
local KEY_MIDDLE_C_MODE = "middle_c_mode"
local KEY_MAIN_WINDOW_BG = "main_window_bg"
local KEY_HIDE_MAIN_WINDOW_TITLEBAR = "hide_main_window_titlebar"
local KEY_HIDE_ZONE_TOOLTIP = "hide_zone_tooltip"
local KEY_HIDE_TRIGGER_NOTES = "hide_trigger_notes"
local KEY_HIDE_KEY_LABELS = "hide_key_labels"
local KEY_ZONE_COLOR_STRENGTH = "zone_color_strength"
local KEY_DEFAULT_ZONE_COLOR = "default_zone_color"
local KEY_TRIGGER_NOTE_COLOR = "trigger_note_color"

local MIDDLE_C_OPTIONS = {
  { value = 3, label = "C3" },
  { value = 4, label = "C4" }
}

-- Shared minimum size for square color picker trigger buttons.
local COLOR_PICKER_BUTTON_SIZE = 18

local KEYBOARD_RANGE_INPUT_W = 40

-- Padding inside the Settings window.
local SETTINGS_WINDOW_PAD_X = 20
local SETTINGS_WINDOW_PAD_Y = 20

local function get_color_picker_button_size(ctx)
  local frame_h = ImGui.GetFrameHeight(ctx)
  return math.max(frame_h, COLOR_PICKER_BUTTON_SIZE)
end

---@generic T
---@param key string
---@param default T
---@return T
local function load_ext_state(key, default)
  local raw = reaper.GetExtState(EXT_SECTION, key)
  if raw == "" then return default end

  local default_type = type(default)
  if default_type == "boolean" then
    return (raw == "1" or raw == "true")
  elseif default_type == "number" then
    local n = tonumber(raw)
    return (n == nil) and default or n
  end

  return raw
end

local function save_ext_state(key, value)
  local raw
  if type(value) == "boolean" then
    raw = value and "1" or "0"
  else
    raw = tostring(value)
  end

  reaper.SetExtState(EXT_SECTION, key, raw, true)
end

local settings = {
  is_open = false,
  hide_info_line = load_ext_state(KEY_HIDE_INFO_LINE, false),
  hide_zone_tooltip = load_ext_state(KEY_HIDE_ZONE_TOOLTIP, false),
  hide_trigger_notes = load_ext_state(KEY_HIDE_TRIGGER_NOTES, false),
  hide_key_labels = load_ext_state(KEY_HIDE_KEY_LABELS, false),
  keyboard_scale = load_ext_state(KEY_KEYBOARD_SCALE, 1.00),
  keyboard_low_note = load_ext_state(KEY_KEYBOARD_LOW_NOTE, 0),
  keyboard_high_note = load_ext_state(KEY_KEYBOARD_HIGH_NOTE, 127),
  middle_c_mode = load_ext_state(KEY_MIDDLE_C_MODE, 3),
  main_window_bg = load_ext_state(KEY_MAIN_WINDOW_BG, constants.ui.MAIN_WINDOW_BG),
  hide_main_window_titlebar = load_ext_state(KEY_HIDE_MAIN_WINDOW_TITLEBAR, false),
  zone_color_strength = load_ext_state(KEY_ZONE_COLOR_STRENGTH, constants.zones.COLOR_STRENGTH_DEFAULT),
  default_zone_color = load_ext_state(KEY_DEFAULT_ZONE_COLOR, constants.zones.DEFAULT_COLOR),
  trigger_note_color = load_ext_state(KEY_TRIGGER_NOTE_COLOR, constants.keyboard.TRIGGER_NOTE_COLOR)
}

local function draw_reset_button(ctx, id, ext_key, settings_key, default_val, opts)
  if button.draw(ctx, "Reset##" .. id, opts) then
    settings[settings_key] = default_val
    save_ext_state(ext_key, settings[settings_key])
    return true
  end
  return false
end


local function middle_c_label(mode)
  return mode == 4 and "C4" or "C3"
end

local function draw_middle_c_combo(ctx)
  local preview = middle_c_label(settings.middle_c_mode)
  if ImGui.BeginCombo(ctx, "Middle C", preview) then
    for _, opt in ipairs(MIDDLE_C_OPTIONS) do
      local selected = (settings.middle_c_mode == opt.value)
      if ImGui.Selectable(ctx, opt.label, selected) then
        settings.middle_c_mode = opt.value
        save_ext_state(KEY_MIDDLE_C_MODE, opt.value)
      end
      if selected then
        ImGui.SetItemDefaultFocus(ctx)
      end
    end
    ImGui.EndCombo(ctx)
  end
end

local function draw_scale_slider(ctx)
  local pct = mathx.clamp_int(mathx.round((settings.keyboard_scale or 1) * 100), 50, 200)
  local changed, new_pct = ImGui.SliderInt(ctx, "Keyboard Scale", pct, 50, 200, "%d%%")
  if changed then
    settings.keyboard_scale = new_pct / 100
    save_ext_state(KEY_KEYBOARD_SCALE, settings.keyboard_scale)
  end
end


local function normalize_keyboard_range()
  local lo = math.floor(tonumber(settings.keyboard_low_note) or 0)
  local hi = math.floor(tonumber(settings.keyboard_high_note) or 127)
  lo = math.max(0, math.min(127, lo))
  hi = math.max(0, math.min(127, hi))
  if lo > hi then
    hi = lo
  end
  settings.keyboard_low_note = lo
  settings.keyboard_high_note = hi
end

local function draw_keyboard_range(ctx)
  normalize_keyboard_range()

  ImGui.SetNextItemWidth(ctx, KEYBOARD_RANGE_INPUT_W)
  local c_lo, new_lo = input_note.draw(ctx, "##keyboard_low_note", settings.keyboard_low_note, {
    middle_c_mode = settings.middle_c_mode,
    midi_learn = true,
    commit_while_active = true,
  })

  if c_lo then
    settings.keyboard_low_note = new_lo
    if settings.keyboard_low_note > settings.keyboard_high_note then
      settings.keyboard_high_note = settings.keyboard_low_note
      save_ext_state(KEY_KEYBOARD_HIGH_NOTE, settings.keyboard_high_note)
    end
    save_ext_state(KEY_KEYBOARD_LOW_NOTE, settings.keyboard_low_note)
  end

  ImGui.SameLine(ctx)
  ImGui.Text(ctx, "to")
  ImGui.SameLine(ctx)

  ImGui.SetNextItemWidth(ctx, KEYBOARD_RANGE_INPUT_W)
  local c_hi, new_hi = input_note.draw(ctx, "##keyboard_high_note", settings.keyboard_high_note, {
    middle_c_mode = settings.middle_c_mode,
    midi_learn = true,
    commit_while_active = true,
  })

  if c_hi then
    settings.keyboard_high_note = new_hi
    if settings.keyboard_high_note < settings.keyboard_low_note then
      settings.keyboard_low_note = settings.keyboard_high_note
      save_ext_state(KEY_KEYBOARD_LOW_NOTE, settings.keyboard_low_note)
    end
    save_ext_state(KEY_KEYBOARD_HIGH_NOTE, settings.keyboard_high_note)
  end


  ImGui.SameLine(ctx)
  ImGui.AlignTextToFramePadding(ctx)
  ImGui.Text(ctx, "Keyboard Range")

end

local function draw_main_background_setting(ctx, label_x)
  local picker_size = get_color_picker_button_size(ctx)

  ImGui.AlignTextToFramePadding(ctx)
  ImGui.Text(ctx, "Main Background")
  ImGui.SameLine(ctx, label_x)

  local changed, new_color = color_picker.draw(ctx, "main_window_bg", settings.main_window_bg, {
    width = picker_size,
    height = picker_size,
    enable_alpha = true
  })
  if changed then
    settings.main_window_bg = new_color
    save_ext_state(KEY_MAIN_WINDOW_BG, new_color)
  end

  ImGui.SameLine(ctx)
  draw_reset_button(ctx, "main_window_bg", KEY_MAIN_WINDOW_BG, "main_window_bg", constants.ui.MAIN_WINDOW_BG, { h = picker_size })
end

local function draw_default_zone_color_setting(ctx, label_x)
  local picker_size = get_color_picker_button_size(ctx)

  ImGui.AlignTextToFramePadding(ctx)
  ImGui.Text(ctx, "Default Zone Color")
  ImGui.SameLine(ctx, label_x)

  local changed, new_color = color_preset_picker.draw(ctx, "default_zone_color", settings.default_zone_color, {
    w = picker_size,
    h = picker_size
  })
  if changed then
    settings.default_zone_color = new_color
    save_ext_state(KEY_DEFAULT_ZONE_COLOR, new_color)
  end

  ImGui.SameLine(ctx)
  draw_reset_button(ctx, "default_zone_color", KEY_DEFAULT_ZONE_COLOR, "default_zone_color", constants.zones.DEFAULT_COLOR, { h = picker_size })
end

local function draw_trigger_note_color_setting(ctx, label_x)
  local picker_size = get_color_picker_button_size(ctx)

  ImGui.AlignTextToFramePadding(ctx)
  ImGui.Text(ctx, "Trigger Note Color")
  ImGui.SameLine(ctx, label_x)

  local changed, new_color = color_preset_picker.draw(ctx, "trigger_note_color", settings.trigger_note_color, {
    w = picker_size,
    h = picker_size
  })
  if changed then
    settings.trigger_note_color = new_color
    save_ext_state(KEY_TRIGGER_NOTE_COLOR, new_color)
  end

  ImGui.SameLine(ctx)
  draw_reset_button(ctx, "trigger_note_color", KEY_TRIGGER_NOTE_COLOR, "trigger_note_color", constants.keyboard.TRIGGER_NOTE_COLOR, { h = picker_size })
end

local function draw_zone_color_strength_slider(ctx)
  settings.zone_color_strength = mathx.clamp_int(settings.zone_color_strength, 0, 100)
  local changed, new_val = ImGui.SliderInt(ctx, "Zone Color Strength", settings.zone_color_strength, 0, 100, "%d%%")
  if changed then
    settings.zone_color_strength = new_val
    save_ext_state(KEY_ZONE_COLOR_STRENGTH, new_val)
  end
end

local function draw_theme_section(ctx)
  header.draw(ctx, "THEMING")

  local spacing_x, _ = ImGui.GetStyleVar(ctx, ImGui.StyleVar_ItemSpacing)
  local w1 = select(1, ImGui.CalcTextSize(ctx, "Main Background"))
  local w2 = select(1, ImGui.CalcTextSize(ctx, "Default Zone Color"))
  local w3 = select(1, ImGui.CalcTextSize(ctx, "Trigger Note Color"))
  local label_x = math.max(w1, math.max(w2, w3)) + spacing_x + 22

  draw_zone_color_strength_slider(ctx)

  ImGui.Spacing(ctx)

  draw_main_background_setting(ctx, label_x)
  draw_default_zone_color_setting(ctx, label_x)
  draw_trigger_note_color_setting(ctx, label_x)
end

local window_flags = ImGui.WindowFlags_NoDocking | ImGui.WindowFlags_AlwaysAutoResize

function settings.draw(ctx)
  ImGui.SetNextWindowBgAlpha(ctx, 1)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, SETTINGS_WINDOW_PAD_X, SETTINGS_WINDOW_PAD_Y)
  local visible, open = ImGui.Begin(ctx, "Settings", settings.is_open, window_flags)
  if visible then
    header.draw(ctx, "UI SETTINGS")

    -- Give the settings window a bit more breathing room.
    local spacing_x, spacing_y = ImGui.GetStyleVar(ctx, ImGui.StyleVar_ItemSpacing)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_ItemSpacing, spacing_x, math.max(spacing_y, 6))

    ImGui.Spacing(ctx)
    ImGui.SeparatorText(ctx, "DISPLAY")

    local changed_title, new_title = ImGui.Checkbox(ctx, "Hide Main Window Title Bar", settings.hide_main_window_titlebar)
    if changed_title then
      settings.hide_main_window_titlebar = new_title
      save_ext_state(KEY_HIDE_MAIN_WINDOW_TITLEBAR, new_title)
    end

    local changed, new_val = ImGui.Checkbox(ctx, "Hide Info Line", settings.hide_info_line)
    if changed then
      settings.hide_info_line = new_val
      save_ext_state(KEY_HIDE_INFO_LINE, new_val)
    end



    ImGui.Spacing(ctx)
    ImGui.SeparatorText(ctx, "KEYBOARD")

    local changed_labels, new_labels = ImGui.Checkbox(ctx, "Hide Key Labels", settings.hide_key_labels)
    if changed_labels then
      settings.hide_key_labels = new_labels
      save_ext_state(KEY_HIDE_KEY_LABELS, new_labels)
    end

    local changed_tt, new_tt = ImGui.Checkbox(ctx, "Hide Tooltips", settings.hide_zone_tooltip)
    if changed_tt then
      settings.hide_zone_tooltip = new_tt
      save_ext_state(KEY_HIDE_ZONE_TOOLTIP, new_tt)
    end

    local changed_trig, new_trig = ImGui.Checkbox(ctx, "Hide Trigger Notes", settings.hide_trigger_notes)
    if changed_trig then
      settings.hide_trigger_notes = new_trig
      save_ext_state(KEY_HIDE_TRIGGER_NOTES, new_trig)
    end

    ImGui.Spacing(ctx)

    draw_middle_c_combo(ctx)
    draw_scale_slider(ctx)
    draw_keyboard_range(ctx)

    ImGui.Spacing(ctx)

    draw_theme_section(ctx)

    ImGui.PopStyleVar(ctx)

    ImGui.End(ctx)
  end

  ImGui.PopStyleVar(ctx)

  settings.is_open = open
end

return settings
