-- @noindex

local articulation_editor_trigger = {}

local header = require("UI.widgets.header")

local articulations = require("data.articulations")
local midi_input = require("midi.input")
local input_note = require("UI.widgets.input_note")
local input_midi = require("UI.widgets.input_midi")
local settings = require("UI.settings.settings")

local child_flags = ImGui.ChildFlags_Borders

-- Keep label column width stable so all rows (Type/Note/Velocity/etc.) align.
local LABEL_W = 70

-- Fixed width for trigger editor inputs (note/cc/pc/velocity).
local INPUT_W = 50

-- Extra spacing between the trigger type radio buttons.
local RADIO_GAP = 20

-- Fixed height for the Trigger section.
local TRIGGER_EDITOR_H = 131

local TEXT_FLAGS = ImGui.InputTextFlags_AutoSelectAll

local function is_off_type(t)
  return t ~= midi_input.MSG_TYPE.note_on and t ~= midi_input.MSG_TYPE.cc and t ~= midi_input.MSG_TYPE.pc
end

---@param art Articulation
---@return ArticulationTrigger|nil trigger
---@return integer trigger_type
local function get_trigger_state(art)
  local trigger = (type(art.trigger) == "table") and art.trigger or nil
  local t = trigger and trigger.type or -1
  return trigger, t
end

local function begin_row(ctx, label)
  local start_x = ImGui.GetCursorPosX(ctx)

  ImGui.AlignTextToFramePadding(ctx)
  ImGui.Text(ctx, label)
  ImGui.SameLine(ctx)

  local control_x = start_x + LABEL_W
  if ImGui.GetCursorPosX(ctx) < control_x then
    ImGui.SetCursorPosX(ctx, control_x)
  end
end

local function draw_type_row(ctx, index, art, trigger, t)
  begin_row(ctx, "Type:")

  if ImGui.RadioButton(ctx, "Note", t == midi_input.MSG_TYPE.note_on) then
    articulations.set_trigger(index, midi_input.MSG_TYPE.note_on)
    trigger, t = get_trigger_state(art)
  end

  ImGui.SameLine(ctx, 0, RADIO_GAP)
  if ImGui.RadioButton(ctx, "CC", t == midi_input.MSG_TYPE.cc) then
    articulations.set_trigger(index, midi_input.MSG_TYPE.cc)
    trigger, t = get_trigger_state(art)
  end

  ImGui.SameLine(ctx, 0, RADIO_GAP)
  if ImGui.RadioButton(ctx, "PC", t == midi_input.MSG_TYPE.pc) then
    articulations.set_trigger(index, midi_input.MSG_TYPE.pc)
    trigger, t = get_trigger_state(art)
  end

  ImGui.SameLine(ctx, 0, RADIO_GAP)
  if ImGui.RadioButton(ctx, "Off", is_off_type(t)) then
    articulations.set_trigger(index, -1)
    trigger, t = get_trigger_state(art)
  end

  return trigger, t
end

local function refresh_trigger(art)
  return (type(art.trigger) == "table") and art.trigger or nil
end

local function normalize_range(old_min, old_max, min_changed, new_min, max_changed, new_max)
  local out_min = min_changed and new_min or old_min
  local out_max = max_changed and new_max or old_max

  if out_min > out_max then
    if min_changed and not max_changed then
      out_max = out_min
    elseif max_changed and not min_changed then
      out_min = out_max
    else
      out_min, out_max = out_max, out_min
    end
  end

  return out_min, out_max
end

local function draw_range_inputs(ctx, id_min, id_max, min_val, max_val, clamp_min, clamp_max)
  ImGui.SetNextItemWidth(ctx, INPUT_W)
  local cmin, new_min = input_midi.draw(ctx, id_min, min_val, clamp_min, clamp_max, {
    flags = TEXT_FLAGS
  })

  ImGui.SameLine(ctx)
  ImGui.Text(ctx, "to")
  ImGui.SameLine(ctx)

  ImGui.SetNextItemWidth(ctx, INPUT_W)
  local cmax, new_max = input_midi.draw(ctx, id_max, max_val, clamp_min, clamp_max, {
    flags = TEXT_FLAGS
  })

  if cmin or cmax then
    local out_min, out_max = normalize_range(min_val, max_val, cmin, new_min, cmax, new_max)
    return true, out_min, out_max
  end

  return false, min_val, max_val
end

local function draw_note_section(ctx, index, art, trigger)
  begin_row(ctx, "Note:")
  ImGui.SetNextItemWidth(ctx, INPUT_W)

  local note = (trigger and tonumber(trigger.val1)) or 60
  local note_changed, new_note = input_note.draw(ctx, "##trigger_note", note, {
    middle_c_mode = settings.middle_c_mode,
    flags = TEXT_FLAGS
  })

  if note_changed then
    local vmin = (trigger and tonumber(trigger.val2min)) or 1
    local vmax = (trigger and tonumber(trigger.val2max)) or 127

    articulations.set_trigger(index, {
      type = midi_input.MSG_TYPE.note_on,
      val1 = new_note,
      val2min = vmin,
      val2max = vmax
    })

    trigger = refresh_trigger(art)
  end

  begin_row(ctx, "Velocity:")

  local note_now = (trigger and tonumber(trigger.val1)) or note
  local vmin = (trigger and tonumber(trigger.val2min)) or 1
  local vmax = (trigger and tonumber(trigger.val2max)) or 127

  local range_changed, out_min, out_max = draw_range_inputs(
    ctx,
    "##trigger_vel_min",
    "##trigger_vel_max",
    vmin,
    vmax,
    1,
    127
  )

  if range_changed then
    articulations.set_trigger(index, {
      type = midi_input.MSG_TYPE.note_on,
      val1 = note_now,
      val2min = out_min,
      val2max = out_max
    })

    trigger = refresh_trigger(art)
  end

  return trigger
end

local function draw_cc_section(ctx, index, art, trigger)
  begin_row(ctx, "CC:")
  ImGui.SetNextItemWidth(ctx, INPUT_W)

  local cc_num = (trigger and tonumber(trigger.val1)) or 1
  local num_changed, new_cc_num = input_midi.draw(ctx, "##trigger_cc_num", cc_num, 0, 127, {
    learn_msg_type = midi_input.MSG_TYPE.cc,
    flags = TEXT_FLAGS
  })

  if num_changed then
    local vmin = (trigger and tonumber(trigger.val2min)) or 0
    local vmax = (trigger and tonumber(trigger.val2max)) or 127

    articulations.set_trigger(index, {
      type = midi_input.MSG_TYPE.cc,
      val1 = new_cc_num,
      val2min = vmin,
      val2max = vmax
    })

    trigger = refresh_trigger(art)
  end

  begin_row(ctx, "Value:")

  local cc_now = (trigger and tonumber(trigger.val1)) or cc_num
  local vmin = (trigger and tonumber(trigger.val2min)) or 0
  local vmax = (trigger and tonumber(trigger.val2max)) or 127

  local range_changed, out_min, out_max = draw_range_inputs(
    ctx,
    "##trigger_cc_min",
    "##trigger_cc_max",
    vmin,
    vmax,
    0,
    127
  )

  if range_changed then
    articulations.set_trigger(index, {
      type = midi_input.MSG_TYPE.cc,
      val1 = cc_now,
      val2min = out_min,
      val2max = out_max
    })

    trigger = refresh_trigger(art)
  end

  return trigger
end

local function draw_pc_section(ctx, index, art, trigger)
  begin_row(ctx, "PC:")
  ImGui.SetNextItemWidth(ctx, INPUT_W)

  local pc_num = (trigger and tonumber(trigger.val1)) or 1
  local changed, new_pc_num = input_midi.draw(ctx, "##trigger_pc_num", pc_num, 0, 127, {
    learn_msg_type = midi_input.MSG_TYPE.pc,
    flags = TEXT_FLAGS
  })

  if changed then
    articulations.set_trigger(index, {
      type = midi_input.MSG_TYPE.pc,
      val1 = new_pc_num,
      val2min = -1,
      val2max = -1
    })

    trigger = refresh_trigger(art)
  end

  return trigger
end

function articulation_editor_trigger.draw(ctx)
  if not ImGui.BeginChild(ctx, "articulation_editor_trigger", 0, TRIGGER_EDITOR_H, child_flags) then
    return
  end

  header.draw(ctx, "Trigger")

  local art = articulations.get_active()
  if art then
    local index = articulations.active_index
    local trigger, t = get_trigger_state(art)

    trigger, t = draw_type_row(ctx, index, art, trigger, t)

    -- Don't draw a separator in "Off" mode (no inputs shown below).
    if not is_off_type(t) then
      ImGui.Spacing(ctx)
      ImGui.Separator(ctx)
      ImGui.Spacing(ctx)
    end

    if t == midi_input.MSG_TYPE.note_on then
      draw_note_section(ctx, index, art, trigger)
    elseif t == midi_input.MSG_TYPE.cc then
      draw_cc_section(ctx, index, art, trigger)
    elseif t == midi_input.MSG_TYPE.pc then
      draw_pc_section(ctx, index, art, trigger)
    end
  end

  ImGui.EndChild(ctx)
end

return articulation_editor_trigger
