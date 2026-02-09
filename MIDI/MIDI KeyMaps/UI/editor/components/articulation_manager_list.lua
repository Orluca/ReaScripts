-- @noindex

local articulation_manager_list = {}

local articulations = require("data.articulations")
local midi_input = require("midi.input")
local midi_notes = require("midi.notes")
local settings = require("UI.settings.settings")

local ARTICULATION_LIST_PAD_X = 4
local DND_ARTIC_MOVE_PAYLOAD = "DND_ARTIC_MOVE"

-- Trigger label view mode in the list: show canonical triggers or keyswitch notes.
local show_keyswitches = false

local rename_state = {
  index = 0,
  buf = "",
  focus = false,
  pending_index = 0
}

local function reset_edit_state()
  rename_state.index = 0
  rename_state.buf = ""
  rename_state.focus = false
  rename_state.pending_index = 0
end

local function has_active()
  local items = articulations.items or {}
  local sel = articulations.active_index
  return type(sel) == "number" and sel >= 1 and sel <= #items
end

local function is_shift_held(ctx)
  return ImGui.IsKeyDown(ctx, ImGui.Mod_Shift)
end

local function format_value_suffix(prefix, vmin, vmax, full_min, full_max)
  if type(vmin) ~= "number" or type(vmax) ~= "number" then
    return prefix
  end

  if vmin == full_min and vmax == full_max then
    return prefix
  end
  if vmin == vmax then
    return prefix .. " | " .. tostring(vmin)
  end
  return prefix .. " | " .. tostring(vmin) .. ", " .. tostring(vmax)
end

local function format_trigger(trigger)
  if type(trigger) ~= "table" then
    return ""
  end

  local t = trigger.type
  local v1 = trigger.val1
  local vmin = trigger.val2min
  local vmax = trigger.val2max

  if t == midi_input.MSG_TYPE.note_on then
    local note = midi_notes.note_to_name(v1, settings.middle_c_mode)
    return format_value_suffix(note, vmin, vmax, 1, 127)
  end

  if t == midi_input.MSG_TYPE.cc then
    local cc = "CC" .. tostring(v1)

    if type(vmin) == "number" and type(vmax) == "number" then
      -- Treat 0-127 and 1-127 as "full" to avoid redundant "| 1, 127".
      local is_full = (vmin == 0 and vmax == 127) or (vmin == 1 and vmax == 127)
      if is_full then
        return cc
      end
      if vmin == vmax then
        return cc .. " | " .. tostring(vmin)
      end
      return cc .. " | " .. tostring(vmin) .. ", " .. tostring(vmax)
    end

    return cc
  end

  if t == midi_input.MSG_TYPE.pc then
    return "PC" .. tostring(v1)
  end

  return ""
end

local function format_keyswitch(trigger)
  if type(trigger) ~= "table" then
    return ""
  end

  local t = trigger.type

  local note = nil
  if t == midi_input.MSG_TYPE.note_on then
    -- Only show a note here if a custom keyswitch note is assigned.
    note = trigger.keyswitch_note
  elseif t == midi_input.MSG_TYPE.cc or t == midi_input.MSG_TYPE.pc then
    note = trigger.keyswitch_note
  else
    return ""
  end

  note = tonumber(note)
  note = note and math.floor(note)
  if type(note) ~= "number" then
    return ""
  end

  return midi_notes.note_to_name(note, settings.middle_c_mode)
end

local function delete_active_articulation()
  if not has_active() then
    return
  end

  articulations.delete(articulations.active_index)
  reset_edit_state()
end

local function duplicate_active_articulation()
  if not has_active() then
    return
  end

  articulations.duplicate(articulations.active_index)
  reset_edit_state()
end

local function add_new_articulation()
  articulations.add()
  reset_edit_state()
end

local function clear_all_articulations()
  articulations.clear_all()
  reset_edit_state()
end

local function draw_articulation_context_menu(ctx, row_i)
  if ImGui.BeginPopupContextItem(ctx) then
    -- Right-click should also activate the row it belongs to.
    articulations.set_active(row_i, false)

    if ImGui.MenuItem(ctx, "Delete") then
      delete_active_articulation()
    end
    if ImGui.MenuItem(ctx, "Duplicate") then
      duplicate_active_articulation()
    end

    ImGui.Separator(ctx)

    if ImGui.MenuItem(ctx, "Copy Zones") then
      articulations.copy_zones(row_i)
    end

    local can_paste = articulations.has_copied_zones()
    if ImGui.MenuItem(ctx, "Paste Zones", nil, nil, can_paste) then
      articulations.paste_zones(row_i)
    end

    ImGui.EndPopup(ctx)
  end
end

local function handle_articulation_drag_drop(ctx, row_i, art)
  if ImGui.BeginDragDropSource(ctx) then
    ImGui.SetDragDropPayload(ctx, DND_ARTIC_MOVE_PAYLOAD, tostring(row_i))
    local name = (type(art) == "table" and art.name) or ("Articulation " .. tostring(row_i))
    ImGui.Text(ctx, "Move: " .. name)
    ImGui.EndDragDropSource(ctx)
  end

  if ImGui.BeginDragDropTarget(ctx) then
    local rv, payload = ImGui.AcceptDragDropPayload(ctx, DND_ARTIC_MOVE_PAYLOAD)
    if rv then
      local from_i = tonumber(payload)
      if from_i and from_i ~= row_i then
        articulations.move(from_i, row_i)
        -- Reordering while renaming is confusing; just exit edit mode for now.
        reset_edit_state()
      end
    end
    ImGui.EndDragDropTarget(ctx)
  end
end

local function draw_rename_input(ctx, i)
  -- Match the InputText height more closely to the non-edit row.
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding, ARTICULATION_LIST_PAD_X, 0)

  if rename_state.focus then
    ImGui.SetKeyboardFocusHere(ctx)
    rename_state.focus = false
  end

  ImGui.SetNextItemWidth(ctx, -1)

  -- Don't use EnterReturnsTrue here: we want the input buffer to update while typing
  -- so TAB can commit the latest value.
  local flags = ImGui.InputTextFlags_AutoSelectAll
  local _, buf = ImGui.InputText(ctx, "##rename_art_" .. tostring(i), rename_state.buf, flags)
  if type(buf) == "string" then
    rename_state.buf = buf
  end

  local key_tab = ImGui.Key_Tab
  if type(key_tab) == "function" then
    key_tab = key_tab()
  end

  local key_enter = ImGui.Key_Enter
  if type(key_enter) == "function" then
    key_enter = key_enter()
  end

  if key_tab and ImGui.IsKeyPressed(ctx, key_tab) then
    articulations.rename(i, rename_state.buf)
    rename_state.index = 0
    rename_state.pending_index = i + (is_shift_held(ctx) and -1 or 1)
    ImGui.PopStyleVar(ctx)
    return
  end

  if key_enter and ImGui.IsKeyPressed(ctx, key_enter) then
    articulations.rename(i, rename_state.buf)
    rename_state.index = 0
    ImGui.PopStyleVar(ctx)
    return
  end

  if ImGui.IsItemDeactivatedAfterEdit(ctx) then
    articulations.rename(i, rename_state.buf)
    rename_state.index = 0
  elseif ImGui.IsItemDeactivated(ctx) then
    -- Clicked away without edits: cancel.
    rename_state.index = 0
  end

  ImGui.PopStyleVar(ctx)
end

function articulation_manager_list.draw(ctx)
  local items = articulations.items or {}
  if #items == 0 then
    reset_edit_state()
    ImGui.Text(ctx, "No articulations")
    return
  end

  -- Something changed while editing (delete, track switch, etc.).
  if rename_state.index > #items then
    reset_edit_state()
  end

  if rename_state.pending_index > 0 then
    local next_i = rename_state.pending_index
    rename_state.pending_index = 0

    if next_i >= 1 and next_i <= #items then
      articulations.set_active(next_i, false)
      rename_state.index = next_i

      local next_art = items[next_i]
      local next_name = (type(next_art) == "table" and next_art.name) or ("Articulation " .. tostring(next_i))
      rename_state.buf = next_name
      rename_state.focus = true
    end
  end

  local table_flags = ImGui.TableFlags_SizingStretchProp | ImGui.TableFlags_NoSavedSettings
  if ImGui.BeginTable(ctx, "articulation_list_table", 2, table_flags) then
    ImGui.TableSetupColumn(ctx, "##name", ImGui.TableColumnFlags_WidthStretch)
    ImGui.TableSetupColumn(ctx, "##trigger", ImGui.TableColumnFlags_WidthFixed, 90)

    local trigger_color = ImGui.GetStyleColor(ctx, ImGui.Col_TextDisabled)

    for i, art in ipairs(items) do
      ImGui.TableNextRow(ctx)

      ImGui.TableSetColumnIndex(ctx, 0)
      local name = (type(art) == "table" and art.name) or ("Articulation " .. tostring(i))
      local is_active = (articulations.active_index == i)

      if rename_state.index == i then
        draw_rename_input(ctx, i)
      else
        local sel_flags = ImGui.SelectableFlags_SpanAllColumns | ImGui.SelectableFlags_AllowDoubleClick
        if ImGui.Selectable(ctx, "##art_row_" .. tostring(i), is_active, sel_flags) then
          articulations.set_active(i, true)
          rename_state.index = 0
        end

        if ImGui.IsItemHovered(ctx) and ImGui.IsMouseDoubleClicked(ctx, ImGui.MouseButton_Left) then
          articulations.set_active(i, true)
          rename_state.index = i
          rename_state.buf = name
          rename_state.focus = true
        end

        handle_articulation_drag_drop(ctx, i, art)
        draw_articulation_context_menu(ctx, i)

        -- Draw the visible label on top of the Selectable for easier padding control.
        ImGui.SameLine(ctx, 0, 0)
        local x, y = ImGui.GetCursorPos(ctx)
        ImGui.SetCursorPos(ctx, x + ARTICULATION_LIST_PAD_X, y)
        ImGui.Text(ctx, name)
      end

      ImGui.TableSetColumnIndex(ctx, 1)
      local trig = ""
      if type(art) == "table" then
        if show_keyswitches then
          trig = format_keyswitch(art.trigger)
          if trig == "" then
            trig = format_trigger(art.trigger)
          end
        else
          trig = format_trigger(art.trigger)
        end
      end

      if trig ~= "" then
        local text_w = ImGui.CalcTextSize(ctx, trig)
        local x, y = ImGui.GetCursorPos(ctx)
        local avail_w = ImGui.GetContentRegionAvail(ctx)
        ImGui.SetCursorPos(ctx, x + math.max(0, avail_w - text_w - ARTICULATION_LIST_PAD_X), y)

        ImGui.PushStyleColor(ctx, ImGui.Col_Text, trigger_color)
        ImGui.Text(ctx, trig)
        ImGui.PopStyleColor(ctx)
      end
    end

    ImGui.EndTable(ctx)
  end
end

function articulation_manager_list.has_active()
  return has_active()
end

function articulation_manager_list.has_any()
  local items = articulations.items or {}
  return #items > 0
end

function articulation_manager_list.reset_edit_state()
  reset_edit_state()
end

function articulation_manager_list.add()
  add_new_articulation()
end

function articulation_manager_list.clear_all()
  clear_all_articulations()
end

function articulation_manager_list.delete_active()
  delete_active_articulation()
end

function articulation_manager_list.duplicate_active()
  duplicate_active_articulation()
end

function articulation_manager_list.get_show_keyswitches()
  return show_keyswitches
end

function articulation_manager_list.set_show_keyswitches(v)
  show_keyswitches = not not v
end

return articulation_manager_list
