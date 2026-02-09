-- @noindex

local reaticulate_importer = {}

local articulations = require("data.articulations")
local constants = require("data.constants")
local midi_input = require("midi.input")
local reaticulate = require("data.reaticulate")
local settings = require("UI.settings.settings")

local button = require("UI.widgets.button")
local color_preset_picker = require("UI.widgets.color_preset_picker")
local input_note = require("UI.widgets.input_note")

local MIN_W, MIN_H = 250, 250
local MAX_W, MAX_H = 1000, 800

local WINDOW_FLAGS = ImGui.WindowFlags_NoDocking | ImGui.WindowFlags_AlwaysAutoResize

local IMPORT_MODE = { replace = 1, append = 2 }

local state = {
  open_requested = false,
  is_open = false,

  -- Loaded preset trees
  user_root = nil,
  factory_root = nil,
  load_error = nil,

  -- Confirm modal
  selected_preset = nil,
  confirm_requested = false,

  import_mode = IMPORT_MODE.replace,
  set_default_zone = false,
  zone_color = (settings.default_zone_color or constants.zones.DEFAULT_COLOR),
  zone_label = "",
  zone_start = 60,
  zone_end = 60,
  zone_mode = constants.zone_mode.chromatic,

  assign_keyswitches = false,
  keyswitch_start = 60,
  keyswitch_pattern = constants.zone_mode.chromatic
}

local ZONE_MODE_OPTIONS = {
  { value = constants.zone_mode.chromatic, label = "Chromatic" },
  { value = constants.zone_mode.white, label = "White Keys" },
  { value = constants.zone_mode.black, label = "Black Keys" }
}

local function flag(v)
  if type(v) == "function" then
    v = v()
  end
  return (type(v) == "number") and v or 0
end

local function new_node()
  return { children = {}, presets = {} }
end

local function split_group_path(group)
  local out = {}
  for part in tostring(group or ""):gmatch("[^/]+") do
    part = part:gsub("^%s+", ""):gsub("%s+$", "")
    if part ~= "" then
      out[#out + 1] = part
    end
  end
  if #out == 0 then
    out[1] = "Uncategorized"
  end
  return out
end

local function add_preset(root, preset)
  local node = root
  for _, part in ipairs(split_group_path(preset.group)) do
    node.children[part] = node.children[part] or new_node()
    node = node.children[part]
  end
  node.presets[#node.presets + 1] = preset
end

local function build_tree(presets)
  local root = new_node()
  for _, preset in ipairs(presets or {}) do
    if type(preset) == "table" then
      add_preset(root, preset)
    end
  end
  return root
end

local function sort_ci(a, b)
  return tostring(a):lower() < tostring(b):lower()
end

local function preset_uid(p)
  if type(p) ~= "table" then
    return "preset"
  end
  return tostring(p.id or (tostring(p.source) .. ":" .. tostring(p.group) .. ":" .. tostring(p.name)))
end

local function preset_label(p)
  return (type(p) == "table" and p.name) or "Preset"
end

local reset_confirm_state

local function draw_menu_tree(ctx, node, path)
  path = tostring(path or "")

  local keys = {}
  for k in pairs(node.children or {}) do
    keys[#keys + 1] = k
  end
  table.sort(keys, sort_ci)

  for _, k in ipairs(keys) do
    local child = node.children[k]
    local child_path = (path ~= "" and (path .. "/" .. k) or k)
    if ImGui.BeginMenu(ctx, tostring(k) .. "##" .. child_path, true) then
      draw_menu_tree(ctx, child, child_path)
      ImGui.EndMenu(ctx)
    end
  end

  local presets = node.presets or {}
  table.sort(presets, function(a, b) return sort_ci(a.name or "", b.name or "") end)

  for _, p in ipairs(presets) do
    local label = preset_label(p)
    if ImGui.MenuItem(ctx, label .. "##" .. preset_uid(p)) then
      -- Reset import options for each preset selection so defaults (like zone color)
      -- pick up the latest Settings values.
      reset_confirm_state()
      state.selected_preset = p
      state.is_open = false
      state.confirm_requested = true
    end
  end
end

reset_confirm_state = function()
  state.selected_preset = nil
  state.import_mode = IMPORT_MODE.replace
  state.set_default_zone = false
  state.zone_color = (settings.default_zone_color or constants.zones.DEFAULT_COLOR)
  state.zone_label = ""
  state.zone_start = 60
  state.zone_end = 60
  state.zone_mode = constants.zone_mode.chromatic
  state.assign_keyswitches = false
  state.keyswitch_start = 60
  state.keyswitch_pattern = constants.zone_mode.chromatic
end

local function clamp_note(n)
  if n < 0 then
    return 0
  end
  if n > 127 then
    return 127
  end
  return n
end

local function normalize_range(a, b)
  if type(a) ~= "number" or type(b) ~= "number" then
    return nil, nil
  end

  a = math.floor(a)
  b = math.floor(b)

  if a > b then
    a, b = b, a
  end

  return a, b
end

local function is_black(note)
  local o = note % 12
  return o == 1 or o == 3 or o == 6 or o == 8 or o == 10
end

local function round_up_to_white(note)
  while note <= 127 and is_black(note) do
    note = note + 1
  end
  return note
end

local function adjust_note(note, pattern, zone_lo, zone_hi)
  local skipped_zone = false

  if pattern == constants.zone_mode.white then
    note = round_up_to_white(note)
  end

  if type(zone_lo) == "number" and type(zone_hi) == "number" then
    if note >= zone_lo and note <= zone_hi then
      note = zone_hi + 1
      skipped_zone = true

      if pattern == constants.zone_mode.white then
        note = round_up_to_white(note)
      end
    end
  end

  return note, skipped_zone
end

local function advance_note(note, pattern)
  note = note + 1
  if pattern == constants.zone_mode.white then
    while note <= 127 and is_black(note) do
      note = note + 1
    end
  end
  return note
end

local function keyswitch_zone_warning(start_note, pattern, zone_lo, zone_hi, count)
  if type(zone_lo) ~= "number" or type(zone_hi) ~= "number" then
    return nil
  end

  if type(count) ~= "number" or count <= 0 then
    return nil
  end

  local note = clamp_note(math.floor(tonumber(start_note) or 0))
  local skipped_zone
  note, skipped_zone = adjust_note(note, pattern, zone_lo, zone_hi)
  if skipped_zone then
    return "Starts after default zone"
  end

  for _ = 2, count do
    if note > 127 then
      break
    end

    note = advance_note(note, pattern)
    note, skipped_zone = adjust_note(note, pattern, zone_lo, zone_hi)

    if skipped_zone then
      return "Cuts into default zone"
    end
  end

  return nil
end

local function build_import_items(preset, default_zone, keyswitch_opts)
  local out = {}
  local arts = (type(preset) == "table" and type(preset.articulations) == "table") and preset.articulations or {}

  local zone_lo, zone_hi = nil, nil
  if type(default_zone) == "table" then
    zone_lo, zone_hi = normalize_range(tonumber(default_zone.start_note), tonumber(default_zone.end_note))
  end

  local ks_note = nil
  local ks_pattern = constants.zone_mode.chromatic

  if type(keyswitch_opts) == "table" then
    ks_pattern = tonumber(keyswitch_opts.pattern) or ks_pattern

    local start = tonumber(keyswitch_opts.start_note)
    if type(start) == "number" then
      ks_note = clamp_note(math.floor(start))
      ks_note, _ = adjust_note(ks_note, ks_pattern, zone_lo, zone_hi)

      if ks_note > 127 then
        ks_note = nil
      end
    end
  end

  for _, a in ipairs(arts) do
    local pc = tonumber(a.pc)
    local name = (type(a.name) == "string") and a.name or ""
    local zone = {
      label = "",
      mode = constants.zone_mode.chromatic,
      color = (settings.default_zone_color or constants.zones.DEFAULT_COLOR),
      start_note = 60,
      end_note = 60
    }

    if type(default_zone) == "table" then
      zone.label = tostring(default_zone.label or "")
      zone.mode = tonumber(default_zone.mode) or zone.mode
      zone.color = tonumber(default_zone.color) or zone.color
      zone.start_note = tonumber(default_zone.start_note) or zone.start_note
      zone.end_note = tonumber(default_zone.end_note) or zone.end_note
    end

    local zones = {zone}

    local trig = { type = midi_input.MSG_TYPE.pc, val1 = pc or 0, val2min = -1, val2max = -1 }
    if type(ks_note) == "number" and ks_note <= 127 then
      trig.keyswitch_note = ks_note

      local next_note = advance_note(ks_note, ks_pattern)
      next_note, _ = adjust_note(next_note, ks_pattern, zone_lo, zone_hi)

      if next_note > 127 then
        ks_note = nil
      else
        ks_note = next_note
      end
    end

    out[#out + 1] = {
      name = name,
      trigger = trig,
      zones = zones
    }
  end

  return out
end


local CONFIRM_POPUP_ID = "Confirm Reaticulate Import"

local function draw_confirm_modal(ctx, center_x, center_y)
  if state.confirm_requested then
    ImGui.OpenPopup(ctx, CONFIRM_POPUP_ID)
    state.confirm_requested = false
  end

  local cond = flag(ImGui.Cond_Appearing)
  if type(center_x) == "number" and type(center_y) == "number" then
    ImGui.SetNextWindowPos(ctx, center_x, center_y, cond, 0.5, 0.5)
  end

  if not ImGui.BeginPopupModal(ctx, CONFIRM_POPUP_ID, nil, ImGui.WindowFlags_AlwaysAutoResize) then
    return
  end
  local preset = state.selected_preset
  if type(preset) ~= "table" then
    ImGui.Text(ctx, "No Reaticulate preset selected")
    if button.draw(ctx, "Close##reaticulate_import") then
      reset_confirm_state()
      ImGui.CloseCurrentPopup(ctx)
    end
    ImGui.EndPopup(ctx)
    return
  end

  local count = (type(preset.articulations) == "table") and #preset.articulations or 0

  ImGui.Text(ctx, string.format("Importing %d articulations", count))
  ImGui.Separator(ctx)

  -- Mode
  ImGui.Text(ctx, "Mode:")
  ImGui.SameLine(ctx)
  if ImGui.RadioButton(ctx, "Replace", state.import_mode == IMPORT_MODE.replace) then
    state.import_mode = IMPORT_MODE.replace
  end
  ImGui.SameLine(ctx)
  if ImGui.RadioButton(ctx, "Append", state.import_mode == IMPORT_MODE.append) then
    state.import_mode = IMPORT_MODE.append
  end

  ImGui.Spacing(ctx)

  local was_default_zone = state.set_default_zone
  local rv_zone, new_zone = ImGui.Checkbox(ctx, "Set a default zone for all imported articulations", state.set_default_zone)
  if rv_zone then
    state.set_default_zone = new_zone
    -- When enabling, start from the current global default zone color.
    if new_zone and not was_default_zone then
      state.zone_color = (settings.default_zone_color or constants.zones.DEFAULT_COLOR)
    end
  end

  local LABEL_X = 120

  if state.set_default_zone then
    ImGui.Spacing(ctx)

    ImGui.AlignTextToFramePadding(ctx)
    ImGui.Text(ctx, "Color")
    ImGui.SameLine(ctx, LABEL_X)
    local changed, new_color = color_preset_picker.draw(ctx, "reaticulate_import_zone_color", state.zone_color, { w = 20, h = 20 })
    if changed then
      state.zone_color = new_color
    end

    ImGui.AlignTextToFramePadding(ctx)
    ImGui.Text(ctx, "Label (optional)")
    ImGui.SameLine(ctx, LABEL_X)
    ImGui.SetNextItemWidth(ctx, 200)
    local rv_label, new_label = ImGui.InputText(ctx, "##reaticulate_import_zone_label", state.zone_label, ImGui.InputTextFlags_AutoSelectAll)
    if rv_label and type(new_label) == "string" then
      state.zone_label = new_label
    end

    ImGui.AlignTextToFramePadding(ctx)
    ImGui.Text(ctx, "Start Note")
    ImGui.SameLine(ctx, LABEL_X)
    ImGui.SetNextItemWidth(ctx, 80)
    local rv_sn, new_sn = input_note.draw(ctx, "##reaticulate_import_zone_start", state.zone_start, { middle_c_mode = settings.middle_c_mode })
    if rv_sn then
      state.zone_start = new_sn
      if state.zone_start > state.zone_end then
        state.zone_end = state.zone_start
      end
    end

    ImGui.AlignTextToFramePadding(ctx)
    ImGui.Text(ctx, "End Note")
    ImGui.SameLine(ctx, LABEL_X)
    ImGui.SetNextItemWidth(ctx, 80)
    local rv_en, new_en = input_note.draw(ctx, "##reaticulate_import_zone_end", state.zone_end, { middle_c_mode = settings.middle_c_mode })
    if rv_en then
      state.zone_end = new_en
      if state.zone_end < state.zone_start then
        state.zone_start = state.zone_end
      end
    end

    ImGui.AlignTextToFramePadding(ctx)
    ImGui.Text(ctx, "Mode")
    ImGui.SameLine(ctx, LABEL_X)

    local preview = "Chromatic"
    for _, opt in ipairs(ZONE_MODE_OPTIONS) do
      if state.zone_mode == opt.value then
        preview = opt.label
      end
    end



    if ImGui.BeginCombo(ctx, "##reaticulate_import_zone_mode", preview) then
      for _, opt in ipairs(ZONE_MODE_OPTIONS) do
        local selected = (state.zone_mode == opt.value)
        if ImGui.Selectable(ctx, opt.label, selected) then
          state.zone_mode = opt.value
        end
        if selected then
          ImGui.SetItemDefaultFocus(ctx)
        end
      end
      ImGui.EndCombo(ctx)
    end
  end

  ImGui.Spacing(ctx)

  local was_keyswitch = state.assign_keyswitches
  local rv_ks, new_ks = ImGui.Checkbox(ctx, "Assign KS aliases to imported articulations", state.assign_keyswitches)
  if rv_ks then
    state.assign_keyswitches = new_ks
    if new_ks and not was_keyswitch then
      state.keyswitch_start = 60
      state.keyswitch_pattern = constants.zone_mode.chromatic
    end
  end

  if state.assign_keyswitches then
    ImGui.Spacing(ctx)

    ImGui.AlignTextToFramePadding(ctx)
    ImGui.Text(ctx, "Start Note")
    ImGui.SameLine(ctx, LABEL_X)
    local KEYSWITCH_START_W = 30
    ImGui.SetNextItemWidth(ctx, KEYSWITCH_START_W)
    local rv_ksn, new_ksn = input_note.draw(ctx, "##reaticulate_import_keyswitch_start", state.keyswitch_start, { middle_c_mode = settings.middle_c_mode })
    if rv_ksn then
      state.keyswitch_start = new_ksn
    end

    if state.set_default_zone and count > 0 then
      local zone_lo, zone_hi = normalize_range(state.zone_start, state.zone_end)
      local warn = keyswitch_zone_warning(state.keyswitch_start, state.keyswitch_pattern, zone_lo, zone_hi, count)
      if warn then
        ImGui.SameLine(ctx)
        ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0xFF4B4BFF)
        ImGui.Text(ctx, warn)
        ImGui.PopStyleColor(ctx)
      end
    end

    ImGui.AlignTextToFramePadding(ctx)
    ImGui.Text(ctx, "Pattern")
    ImGui.SameLine(ctx, LABEL_X)

    local ks_preview = (state.keyswitch_pattern == constants.zone_mode.white) and "White Keys" or "Chromatic"
    if ImGui.BeginCombo(ctx, "##reaticulate_import_keyswitch_pattern", ks_preview) then
      local sel_chromatic = (state.keyswitch_pattern == constants.zone_mode.chromatic)
      if ImGui.Selectable(ctx, "Chromatic", sel_chromatic) then
        state.keyswitch_pattern = constants.zone_mode.chromatic
      end
      if sel_chromatic then
        ImGui.SetItemDefaultFocus(ctx)
      end

      local sel_white = (state.keyswitch_pattern == constants.zone_mode.white)
      if ImGui.Selectable(ctx, "White Keys", sel_white) then
        state.keyswitch_pattern = constants.zone_mode.white
      end
      if sel_white then
        ImGui.SetItemDefaultFocus(ctx)
      end

      ImGui.EndCombo(ctx)
    end
  end

  ImGui.Spacing(ctx)
  ImGui.Spacing(ctx)

  local spacing_x, _ = ImGui.GetStyleVar(ctx, ImGui.StyleVar_ItemSpacing)
  local avail_w = ImGui.GetContentRegionAvail(ctx)
  local button_w = math.max(0, (avail_w - spacing_x) * 0.5)

  if button.draw(ctx, "Confirm##reaticulate_import", { w = button_w }) then
    local default_zone = nil
    if state.set_default_zone then
      default_zone = {
        label = state.zone_label,
        mode = state.zone_mode,
        color = state.zone_color,
        start_note = state.zone_start,
        end_note = state.zone_end
      }
    end

    local keyswitch_opts = nil
    if state.assign_keyswitches then
      keyswitch_opts = { start_note = state.keyswitch_start, pattern = state.keyswitch_pattern }
    end

    local items = build_import_items(preset, default_zone, keyswitch_opts)

    if state.import_mode == IMPORT_MODE.replace then
      articulations.replace_all(items)
    else
      articulations.append_multiple(items)
    end

    reset_confirm_state()
    ImGui.CloseCurrentPopup(ctx)
  end

  ImGui.SameLine(ctx)

  if button.draw(ctx, "Cancel##reaticulate_import", { w = button_w }) then
    reset_confirm_state()
    ImGui.CloseCurrentPopup(ctx)
  end

  ImGui.EndPopup(ctx)
end

local function load_data()
  local user_presets, factory_presets = reaticulate.load_presets()

  state.user_root = build_tree(user_presets)
  state.factory_root = build_tree(factory_presets)

  local any_user = (type(user_presets) == "table" and #user_presets > 0)
  local any_factory = (type(factory_presets) == "table" and #factory_presets > 0)

  if not any_user and not any_factory then
    state.load_error = "No Reaticulate presets found"
  else
    state.load_error = nil
  end
end

function reaticulate_importer.open()
  state.open_requested = true
end

function reaticulate_importer.draw(ctx, center_x, center_y)
  if state.open_requested then
    state.open_requested = false
    state.is_open = true
    load_data()
  end

  -- Confirm modal is independent of the browser window.
  draw_confirm_modal(ctx, center_x, center_y)

  if not state.is_open then
    return
  end

  ImGui.SetNextWindowSizeConstraints(ctx, MIN_W, MIN_H, MAX_W, MAX_H)

  local cond = flag(ImGui.Cond_Appearing)
  if type(center_x) == "number" and type(center_y) == "number" then
    ImGui.SetNextWindowPos(ctx, center_x, center_y, cond, 0.5, 0.5)
  end

  local visible, open = ImGui.Begin(ctx, "Reaticulate Importer", state.is_open, WINDOW_FLAGS)

  local focused_flags = flag(ImGui.FocusedFlags_RootAndChildWindows)
  local focused = ImGui.IsWindowFocused(ctx, focused_flags)

  if visible then
    if state.load_error then
      ImGui.Text(ctx, state.load_error)
    else
      -- Factory folder on top.
      local has_factory = state.factory_root and ((next(state.factory_root.children) ~= nil) or (#state.factory_root.presets > 0))
      if has_factory and ImGui.BeginMenu(ctx, "_Factory", true) then
        draw_menu_tree(ctx, state.factory_root, "_Factory")
        ImGui.EndMenu(ctx)
      end

      if state.user_root then
        draw_menu_tree(ctx, state.user_root, "")
      end
    end
  end

  ImGui.End(ctx)

  -- Auto-close when clicking away.
  if state.is_open then
    if not open or not focused then
      state.is_open = false
    else
      state.is_open = open
    end
  end
end

return reaticulate_importer

