-- @noindex

local constants = require("data.constants")
local button = require("UI.widgets.button")

local color_picker = {}
local popup_state = {}

-- ReaImGui uses RGBA (0xRRGGBBAA) when alpha is enabled.
-- When alpha is disabled, ColorPicker expects ARGB.
local function rgba_to_argb(rgba)
  return ((rgba >> 8) & 0x00FFFFFF) | ((rgba << 24) & 0xFF000000)
end

local function argb_to_rgba(argb)
  return ((argb << 8) & 0xFFFFFF00) | ((argb >> 24) & 0xFF)
end

local function ui_to_picker(ui_color, include_alpha)
  if include_alpha then
    return ui_color
  end
  return rgba_to_argb(ui_color)
end

local function picker_to_ui(picker_color, include_alpha)
  if include_alpha then
    return picker_color
  end
  return argb_to_rgba(picker_color)
end

local function ensure_state(id, color)
  local state = popup_state[id]
  if not state then
    state = { start_color = color, current_color = color }
    popup_state[id] = state
  end
  return state
end

local function build_picker_flags(enable_alpha)
  -- Keep the large side preview by only disabling the small preview.
  local flags = ImGui.ColorEditFlags_NoSmallPreview
  if not enable_alpha then
    flags = flags | ImGui.ColorEditFlags_NoAlpha
  end
  return flags
end

local function get_contrast_border_color(color)
  local r = (color >> 24) & 0xFF
  local g = (color >> 16) & 0xFF
  local b = (color >> 8) & 0xFF
  local luminance = (0.299 * r) + (0.587 * g) + (0.114 * b)
  if luminance < 50 then
    return 0x666666FF
  end
  return 0x000000FF
end

local function draw_trigger_button(ctx, id, color, width, height, rounding, border_size, border_color, popup_id)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameRounding, rounding)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameBorderSize, border_size)
  ImGui.PushStyleColor(ctx, ImGui.Col_Border, border_color)
  ImGui.PushStyleColor(ctx, ImGui.Col_Button, color)
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, color)
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, color)

  local clicked = ImGui.Button(ctx, "##" .. id, width, height)
  if clicked then
    popup_state[id] = { start_color = color, current_color = color }
    ImGui.OpenPopup(ctx, popup_id)
  end

  if ImGui.IsItemHovered(ctx) then
    ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_Hand)
  end

  ImGui.PopStyleColor(ctx, 4)
  ImGui.PopStyleVar(ctx, 2)
  return clicked
end

local function draw_picker_popup(ctx, id, popup_id, color, enable_alpha)
  local changed = false
  local committed = false

  if not ImGui.BeginPopup(ctx, popup_id) then
    return changed, color, committed
  end

  local state = ensure_state(id, color)
  local flags = build_picker_flags(enable_alpha)

  local picker_input = ui_to_picker(state.current_color, enable_alpha)
  local rv, picker_color = ImGui.ColorPicker4(ctx, "##" .. id .. "_color", picker_input, flags)
  if rv then
    state.current_color = picker_to_ui(picker_color, enable_alpha)
    if state.current_color ~= color then
      color = state.current_color
      changed = true
    end
  end

  ImGui.Separator(ctx)

  if button.draw(ctx, "Confirm##" .. id) then
    color = state.current_color
    changed = (state.current_color ~= state.start_color) or changed
    committed = true
    popup_state[id] = nil
    ImGui.CloseCurrentPopup(ctx)
  end

  ImGui.SameLine(ctx)

  if button.draw(ctx, "Cancel##" .. id) then
    color = state.start_color
    changed = (state.current_color ~= state.start_color) or changed
    popup_state[id] = nil
    ImGui.CloseCurrentPopup(ctx)
  end

  ImGui.EndPopup(ctx)
  return changed, color, committed
end

local function handle_popup_close(ctx, id, popup_id, color)
  local state = popup_state[id]
  if state and not ImGui.IsPopupOpen(ctx, popup_id) then
    popup_state[id] = nil
    if state.current_color ~= state.start_color then
      return true, state.start_color
    end
  end
  return false, color
end

---Draw a color button that opens a popup color picker.
---
---Behavior:
---- Changes stream live while the picker is open.
---- Confirm commits, Cancel reverts to the opening color.
---@class ColorPickerOptions
---@field width? number Button width in pixels. Default: 20
---@field height? number Button height in pixels. Default: width
---@field rounding? number Frame rounding. Default: constants.ui.BUTTON_ROUNDING
---@field border_size? number Frame border size in pixels. Default: 1
---@field border_color? integer RGBA border color. Default: auto-contrast
---@field enable_alpha? boolean Enable alpha editing. Default: false
---@param ctx ImGui_Context
---@param id string Unique id suffix for widget and popup ids
---@param color integer RGBA color (0xRRGGBBAA)
---@param opts? ColorPickerOptions
---@return boolean changed True when `color` should be applied immediately
---@return integer color Updated RGBA color (0xRRGGBBAA)
---@return boolean committed True only when Confirm was pressed
---@return boolean opened True when the picker popup was opened this frame
function color_picker.draw(ctx, id, color, opts)
  opts = opts or {}
  local width = opts.width or 20
  local height = opts.height or width
  local rounding = opts.rounding or constants.ui.BUTTON_ROUNDING
  local border_size = opts.border_size or 1
  local border_color = opts.border_color or get_contrast_border_color(color)
  local enable_alpha = opts.enable_alpha == true
  local popup_id = "##" .. id .. "_picker"

  local opened = draw_trigger_button(ctx, id, color, width, height, rounding, border_size, border_color, popup_id)

  local changed, new_color, committed = draw_picker_popup(ctx, id, popup_id, color, enable_alpha)
  color = new_color

  -- Handle closing via escape/click-outside: revert to opening color.
  local closed_changed, closed_color = handle_popup_close(ctx, id, popup_id, color)
  if closed_changed then
    return true, closed_color, committed, opened
  end

  return changed, color, committed, opened
end

return color_picker
