-- @noindex

local articulation_editor_zones = {}

local articulations = require("data.articulations")
local constants = require("data.constants")
local settings = require("UI.settings.settings")

local header = require("UI.widgets.header")
local button = require("UI.widgets.button")
local color_preset_picker = require("UI.widgets.color_preset_picker")
local input_note = require("UI.widgets.input_note")

local child_flags = ImGui.ChildFlags_Borders

local TABLE_ROW_H = 40
local CELL_PADDING_X = 1
local CELL_PADDING_Y = 2
local COLOR_BUTTON_W = 20

local copied_zone_color = nil

local ZONE_MODE_OPTIONS = {"Chromatic", "White Keys", "Black Keys"}
local DND_ZONE_PAYLOAD = "DND_ZONE_REORDER"

local FOOTER_BUTTON_W = 80
local FOOTER_BUTTON_H = 30



local function row_pady(ctx)
  local font_h = ImGui.GetTextLineHeight(ctx)
  return (TABLE_ROW_H / 2) - (font_h / 2)
end

local function draw_row_overlay(ctx, row_i, zone, actions)
  ImGui.TableNextRow(ctx, 0, TABLE_ROW_H)
  ImGui.TableSetColumnIndex(ctx, 0)

  local c_x = ImGui.GetCursorPosX(ctx)
  local c_y = ImGui.GetCursorPosY(ctx)

  local selectable_flags = ImGui.SelectableFlags_SpanAllColumns | ImGui.SelectableFlags_AllowOverlap
  ImGui.PushStyleColor(ctx, ImGui.Col_HeaderHovered, 0)
  ImGui.PushStyleColor(ctx, ImGui.Col_HeaderActive, 0)
  ImGui.Selectable(ctx, "##zone_row_drop" .. tostring(row_i), false, selectable_flags, 0, TABLE_ROW_H)
  ImGui.PopStyleColor(ctx, 2)

  if ImGui.BeginPopupContextItem(ctx, "ZoneRowContextMenu" .. tostring(row_i)) then
    local label = (type(zone) == "table" and zone.label) or ""

    ImGui.PushStyleVar(ctx, ImGui.StyleVar_SeparatorTextAlign, 0.5, 0.5)
    ImGui.SeparatorText(ctx, "Zone: " .. tostring(label))
    ImGui.PopStyleVar(ctx)

    if ImGui.MenuItem(ctx, "Delete") then
      actions.delete_index = row_i
    end

    if ImGui.MenuItem(ctx, "Duplicate") then
      actions.duplicate_index = row_i
    end

    ImGui.Separator(ctx)

    if ImGui.MenuItem(ctx, "Copy Color") then
      local c = (type(zone) == "table" and tonumber(zone.color))
      if c == nil then
        c = settings.default_zone_color or constants.zones.DEFAULT_COLOR
      end
      copied_zone_color = c
    end

    local can_paste_color = (type(copied_zone_color) == "number")
    if ImGui.MenuItem(ctx, "Paste Color", nil, nil, can_paste_color) then
      if type(zone) == "table" and can_paste_color then
        zone.color = copied_zone_color
        articulations.save()
      end
    end

    ImGui.EndPopup(ctx)
  end

  if ImGui.BeginDragDropTarget(ctx) then
    local rv, payload = ImGui.AcceptDragDropPayload(ctx, DND_ZONE_PAYLOAD)
    if rv then
      actions.move_from = tonumber(payload)
      actions.move_to = row_i
    end
    ImGui.EndDragDropTarget(ctx)
  end

  -- Reset cursor to draw the actual content of Column 1 (the color button) on top.
  ImGui.SetCursorPosX(ctx, c_x)
  ImGui.SetCursorPosY(ctx, c_y)
end

local function draw_column_color(ctx, row_i, zone)
  local color = (type(zone) == "table" and zone.color) or (settings.default_zone_color or constants.zones.DEFAULT_COLOR)

  local changed, new_color = color_preset_picker.draw(ctx, "zone_color_" .. tostring(row_i), color, {
    w = COLOR_BUTTON_W,
    h = TABLE_ROW_H
  })

  if changed and type(zone) == "table" then
    zone.color = new_color
    articulations.save()
  end
end

local function draw_column_label(ctx, row_i, zone, pady)
  ImGui.TableSetColumnIndex(ctx, 1)

  local label = (type(zone) == "table" and zone.label) or ""

  ImGui.SetNextItemWidth(ctx, -1)
  ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg, 0)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding, 5, pady)

  local _, new_label = ImGui.InputText(ctx, "##zone_label" .. tostring(row_i), label, ImGui.InputTextFlags_AutoSelectAll)

  if type(zone) == "table" and type(new_label) == "string" then
    zone.label = new_label
  end

  if ImGui.IsItemDeactivatedAfterEdit(ctx) then
    articulations.save()
  end

  ImGui.PopStyleVar(ctx)
  ImGui.PopStyleColor(ctx)
end

local function draw_column_start_note(ctx, row_i, zone, pady, actions)
  ImGui.TableSetColumnIndex(ctx, 2)

  local start_note = (type(zone) == "table" and tonumber(zone.start_note)) or 60

  ImGui.SetNextItemWidth(ctx, -1)
  ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg, 0)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding, 4, pady)

  local changed, new_note = input_note.draw(ctx, "##zone_start_note" .. tostring(row_i), start_note, {
    middle_c_mode = settings.middle_c_mode,
    flags = ImGui.InputTextFlags_AutoSelectAll
  })

  if actions and ImGui.IsItemActive(ctx) and ImGui.IsItemHovered(ctx) then
    actions.lock_scroll_wheel = true
  end

  if changed and type(zone) == "table" then
    zone.start_note = new_note
    local cur_end = tonumber(zone.end_note) or new_note
    if new_note > cur_end then
      zone.end_note = new_note
    end
    articulations.save()
  end

  ImGui.PopStyleVar(ctx)
  ImGui.PopStyleColor(ctx)
end

local function draw_column_end_note(ctx, row_i, zone, pady, actions)
  ImGui.TableSetColumnIndex(ctx, 3)

  local end_note = (type(zone) == "table" and tonumber(zone.end_note)) or 60

  ImGui.SetNextItemWidth(ctx, -1)
  ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg, 0)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding, 4, pady)

  local changed, new_note = input_note.draw(ctx, "##zone_end_note" .. tostring(row_i), end_note, {
    middle_c_mode = settings.middle_c_mode,
    flags = ImGui.InputTextFlags_AutoSelectAll
  })

  if actions and ImGui.IsItemActive(ctx) and ImGui.IsItemHovered(ctx) then
    actions.lock_scroll_wheel = true
  end

  if changed and type(zone) == "table" then
    zone.end_note = new_note
    local cur_start = tonumber(zone.start_note) or new_note
    if new_note < cur_start then
      zone.start_note = new_note
    end
    articulations.save()
  end

  ImGui.PopStyleVar(ctx)
  ImGui.PopStyleColor(ctx)
end

local function draw_column_mode(ctx, row_i, zone, pady)
  ImGui.TableSetColumnIndex(ctx, 4)

  local mode = (type(zone) == "table" and tonumber(zone.mode)) or constants.zone_mode.chromatic
  if mode < 1 or mode > #ZONE_MODE_OPTIONS then
    mode = constants.zone_mode.chromatic
  end

  ImGui.SetNextItemWidth(ctx, -1)
  ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg, 0)
  ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgHovered, 0)
  ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgActive, 0)
  ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0)
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0)
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, 0)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding, 4, pady)

  if ImGui.BeginCombo(ctx, "##zone_mode" .. tostring(row_i), ZONE_MODE_OPTIONS[mode]) then
    for j, opt in ipairs(ZONE_MODE_OPTIONS) do
      local is_selected = (mode == j)
      if ImGui.Selectable(ctx, opt, is_selected) then
        if type(zone) == "table" then
          zone.mode = j
          articulations.save()
        end
        mode = j
      end
      if is_selected then
        ImGui.SetItemDefaultFocus(ctx)
      end
    end
    ImGui.EndCombo(ctx)
  end

  if ImGui.IsItemHovered(ctx) then
    ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_Hand)
  end

  ImGui.PopStyleVar(ctx)
  ImGui.PopStyleColor(ctx, 6)
end

local function draw_column_dnd_handle(ctx, row_i, pady)
  ImGui.TableSetColumnIndex(ctx, 5)

  ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding, 4, pady)
  ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0)
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0)
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, 0)

  ImGui.Button(ctx, "::##reorder_zone_handle" .. tostring(row_i), -1)

  ImGui.PopStyleColor(ctx, 3)
  ImGui.PopStyleVar(ctx)

  if ImGui.IsItemHovered(ctx) then
    ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_ResizeNS)
  end

  if ImGui.BeginDragDropSource(ctx) then
    ImGui.SetDragDropPayload(ctx, DND_ZONE_PAYLOAD, tostring(row_i))
    ImGui.Text(ctx, "Move Zone " .. tostring(row_i))
    ImGui.EndDragDropSource(ctx)
  end
end

local function draw_zones_table(ctx, art)
  local zones = (type(art) == "table" and type(art.zones) == "table") and art.zones or {}
  local actions = { move_from = nil, move_to = nil, delete_index = nil, duplicate_index = nil, lock_scroll_wheel = false }

  local scroll_y_before = ImGui.GetScrollY(ctx)

  local table_flags = ImGui.TableFlags_BordersOuter |
                      ImGui.TableFlags_BordersInnerH |
                      ImGui.TableFlags_SizingStretchProp |
                      ImGui.TableFlags_NoSavedSettings

  ImGui.PushStyleVar(ctx, ImGui.StyleVar_CellPadding, CELL_PADDING_X, CELL_PADDING_Y)

  if ImGui.BeginTable(ctx, "zones_table", 6, table_flags) then
    ImGui.TableSetupColumn(ctx, "Color", ImGui.TableColumnFlags_WidthFixed, 40)
    ImGui.TableSetupColumn(ctx, "Label (optional)")
    ImGui.TableSetupColumn(ctx, "Start Note", ImGui.TableColumnFlags_WidthFixed, 80)
    ImGui.TableSetupColumn(ctx, "End Note", ImGui.TableColumnFlags_WidthFixed, 80)
    ImGui.TableSetupColumn(ctx, "Mode", ImGui.TableColumnFlags_WidthFixed, 130)
    ImGui.TableSetupColumn(ctx, "##Handle", ImGui.TableColumnFlags_WidthFixed, 30)
    ImGui.TableHeadersRow(ctx)

    local pady = row_pady(ctx)

    for i = 1, #zones do
      local zone = zones[i]
      draw_row_overlay(ctx, i, zone, actions)
      draw_column_color(ctx, i, zone)
      draw_column_label(ctx, i, zone, pady)
      draw_column_start_note(ctx, i, zone, pady, actions)
      draw_column_end_note(ctx, i, zone, pady, actions)
      draw_column_mode(ctx, i, zone, pady)
      draw_column_dnd_handle(ctx, i, pady)
    end
    ImGui.EndTable(ctx)
  end
  ImGui.PopStyleVar(ctx)

  local wheel = ImGui.GetMouseWheel(ctx)
  if wheel ~= 0 and not actions.lock_scroll_wheel then
    local hovered = ImGui.IsWindowHovered(ctx)
    if hovered then
      ImGui.SetScrollY(ctx, scroll_y_before - (wheel * TABLE_ROW_H))
    end
  end

  local art_index = articulations.active_index

  if actions.move_from and actions.move_to and actions.move_from ~= actions.move_to then
    articulations.move_zone(art_index, actions.move_from, actions.move_to)
  end

  if actions.duplicate_index then
    articulations.duplicate_zone(art_index, actions.duplicate_index)
  end

  if actions.delete_index then
    articulations.delete_zone(art_index, actions.delete_index)
  end
end

local function draw_footer(ctx)
  -- Right-align the footer action.
  local label = "Add Zone"
  local btn_w = FOOTER_BUTTON_W

  local start_x = ImGui.GetCursorPosX(ctx)
  local avail_w = ImGui.GetContentRegionAvail(ctx)
  local offset_x = math.max(0, avail_w - btn_w)
  ImGui.SetCursorPosX(ctx, start_x + offset_x)

  if button.draw(ctx, label, { w = FOOTER_BUTTON_W, h = FOOTER_BUTTON_H }) then
    articulations.add_zone(articulations.active_index)
  end
end

function articulation_editor_zones.draw(ctx)
  if ImGui.BeginChild(ctx, "articulation_editor_zones", 0, 0, child_flags) then
    header.draw(ctx, "Zones")
    local _, spacing_y = ImGui.GetStyleVar(ctx, ImGui.StyleVar_ItemSpacing)
    local footer_h = FOOTER_BUTTON_H + spacing_y

    if ImGui.BeginChild(ctx, "articulation_editor_zones_body", 0, -footer_h, 0, ImGui.WindowFlags_NoScrollWithMouse) then
      local art = articulations.get_active()
      if art then
        draw_zones_table(ctx, art)
      end
      ImGui.EndChild(ctx)
    end

    draw_footer(ctx)

    ImGui.EndChild(ctx)
  end
end

return articulation_editor_zones


