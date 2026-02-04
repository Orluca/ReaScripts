-- @noindex

local keyboard = require("UI.main.components.keyboard")
local info_line = require("UI.main.components.info_line")
local menu = require("UI.main.components.menu")
local settings = require("UI.settings.settings")
local editor = require("UI.editor.editor")

local main = {}

function main.draw(ctx)
  local window_flags = ImGui.WindowFlags_NoResize |
                       ImGui.WindowFlags_AlwaysAutoResize

  if settings.hide_main_window_titlebar then
    window_flags = window_flags | ImGui.WindowFlags_NoTitleBar
  end

  ImGui.PushStyleColor(ctx, ImGui.Col_WindowBg, settings.main_window_bg)
  local visible, open = ImGui.Begin(ctx, "MIDI KeyMaps", true, window_flags)
  if visible then
    -- Some math to ensure the contents of the main window are always horizontally centered (for when the GUI is docked in REAPER)
    local spacing_x, _ = ImGui.GetStyleVar(ctx, ImGui.StyleVar_ItemSpacing)
    local scale = settings.keyboard_scale
    local kb_w, kb_h, sizes = keyboard.get_dimensions(scale, settings.keyboard_low_note, settings.keyboard_high_note)
    local menu_w, _ = menu.get_size(ctx)
    local content_w = kb_w + spacing_x + menu_w
    local avail_w = ImGui.GetContentRegionAvail(ctx)

    local start_x, start_y = ImGui.GetCursorPos(ctx)
    local offset_x = math.max(0, (avail_w - content_w) * 0.5)

    ImGui.SetCursorPos(ctx, start_x + offset_x, start_y)

    ImGui.BeginGroup(ctx)
      keyboard.draw(ctx, sizes, {
        scale = scale,
        low_note = settings.keyboard_low_note,
        high_note = settings.keyboard_high_note,
        middle_c_mode = settings.middle_c_mode,
        zone_color_strength = settings.zone_color_strength,
        hide_zone_tooltip = settings.hide_zone_tooltip,
        hide_trigger_notes = settings.hide_trigger_notes,
        hide_key_labels = settings.hide_key_labels,
        trigger_note_color = settings.trigger_note_color
      })
      ImGui.Dummy(ctx, kb_w, kb_h)
      ImGui.SameLine(ctx)
      menu.draw(ctx)
      if not settings.hide_info_line then
        info_line.draw(ctx)
      end
    ImGui.EndGroup(ctx)

    ImGui.End(ctx)
  end
  ImGui.PopStyleColor(ctx)

  if settings.is_open then
    settings.draw(ctx)
  end

  if editor.is_open then
    editor.draw(ctx)
  end

  return open
end

return main
