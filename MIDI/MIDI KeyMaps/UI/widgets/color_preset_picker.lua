-- @noindex

local constants = require("data.constants")
local math_utils = require("utils.math")

local color_picker = require("UI.widgets.color_picker")

local color_preset_picker = {}

-- Per-widget instance state keyed by `id`.
local state = {}

local PRESET_SELECTED_BORDER_SIZE = 1.5

local function ensure_state(id)
  local st = state[id]
  if not st then
    st = {
      preset_popup_open = false,
      picker_start_color = nil,
    }
    state[id] = st
  end
  return st
end

local function lighten_color(color, amount)
  local r = (color >> 24) & 0xFF
  local g = (color >> 16) & 0xFF
  local b = (color >> 8) & 0xFF
  local a = color & 0xFF

  local function mix(c)
    return math_utils.clamp_byte(c + ((255 - c) * amount))
  end

  r = mix(r)
  g = mix(g)
  b = mix(b)

  return (r << 24) | (g << 16) | (b << 8) | a
end

local function contrast_border_color(color)
  local r = (color >> 24) & 0xFF
  local g = (color >> 16) & 0xFF
  local b = (color >> 8) & 0xFF
  local luminance = (0.299 * r) + (0.587 * g) + (0.114 * b)
  if luminance < 50 then
    return 0x666666FF
  end
  return 0x000000FF
end

local function draw_preset_grid(ctx, id, presets, grid_w, button_size, spacing, selected_color)
  if #presets == 0 then
    return false, nil
  end

  ImGui.PushStyleVar(ctx, ImGui.StyleVar_ItemSpacing, spacing, spacing)

  for i = 1, #presets do
    local col = presets[i]
    local selected = (type(selected_color) == "number") and (col == selected_color) or false

    if selected then
      ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameBorderSize, PRESET_SELECTED_BORDER_SIZE)
      ImGui.PushStyleColor(ctx, ImGui.Col_Border, 0xFFFFFFFF)
    end

    ImGui.PushStyleColor(ctx, ImGui.Col_Button, col)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, lighten_color(col, 0.1))
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, lighten_color(col, 0.1))
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameRounding, button_size / 2)

    if ImGui.Button(ctx, "##" .. id .. "_preset_" .. tostring(i), button_size, button_size) then
      ImGui.PopStyleVar(ctx)
      ImGui.PopStyleColor(ctx, 3)
      if selected then
        ImGui.PopStyleColor(ctx)
        ImGui.PopStyleVar(ctx)
      end
      ImGui.PopStyleVar(ctx)
      return true, col
    end

    if ImGui.IsItemHovered(ctx) then
      ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_Hand)
    end

    ImGui.PopStyleVar(ctx)
    ImGui.PopStyleColor(ctx, 3)
    if selected then
      ImGui.PopStyleColor(ctx)
      ImGui.PopStyleVar(ctx)
    end

    if i % grid_w ~= 0 and i < #presets then
      ImGui.SameLine(ctx)
    end
  end

  ImGui.PopStyleVar(ctx)
  return false, nil
end

---Draw a zone-color button that opens a popup with preset colors and a custom picker.
---
---Popup contents:
---- Grid of round preset buttons: selecting one applies immediately and closes the popup.
---- A custom picker button (uses `UI.widgets.color_picker`):
---  - changes stream live while open
---  - Confirm closes BOTH picker and preset popup
---  - Cancel closes only the picker and reverts
---
---If the preset popup is closed while the picker is open (click outside), this reverts
---to the color that was active when the picker was opened.
---@class ColorPresetPickerOptions
---@field w? number Trigger button width in px. Default: 20
---@field h? number Trigger button height in px. Default: w
---@field border_size? number Trigger button border size. Default: 1
---@field border_color? integer RGBA border color. Default: auto-contrast
---@field hover_lighten? number Lighten amount for hovered state (0-1). Default: 0.1
---@field presets? integer[] Preset colors as RGBA (0xRRGGBBAA). Default: constants.zones.COLOR_PRESETS
---@field presets_grid_w? integer Presets per row. Default: 5
---@field preset_button_size? number Preset button size in px. Default: 25
---@field preset_spacing? number Preset grid spacing in px. Default: 8
---@field picker_button_h? number Custom picker trigger button height. Default: 20
---@field enable_alpha? boolean Enable alpha editing in the custom picker. Default: false
---@param ctx ImGui_Context
---@param id string Unique id for this widget instance
---@param color integer Current RGBA color (0xRRGGBBAA)
---@param opts? ColorPresetPickerOptions
---@return boolean changed True when the returned `color` should be applied immediately
---@return integer|nil color Updated RGBA color
---@return boolean committed True when a preset was chosen or Confirm was pressed in the picker
function color_preset_picker.draw(ctx, id, color, opts)
  opts = opts or {}

  local st = ensure_state(id)
  st.preset_popup_open = false

  local w = opts.w or 20
  local h = opts.h or w
  local border_size = opts.border_size or 1
  local border_color = opts.border_color or contrast_border_color(color)
  local hover_lighten = opts.hover_lighten or 0.1

  local presets = opts.presets or (constants.zones.COLOR_PRESETS or {})
  local grid_w = opts.presets_grid_w or 5
  local preset_button_size = opts.preset_button_size or 25
  local preset_spacing = opts.preset_spacing or 8

  local picker_button_h = opts.picker_button_h or 20
  local popup_id = "##" .. id .. "_presets_popup"

  -- Trigger button
  local hovered_col = lighten_color(color, hover_lighten)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameBorderSize, border_size)
  ImGui.PushStyleColor(ctx, ImGui.Col_Border, border_color)
  ImGui.PushStyleColor(ctx, ImGui.Col_Button, color)
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, hovered_col)
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, hovered_col)

  if ImGui.Button(ctx, "##" .. id, w, h) then
    st.picker_start_color = nil
    ImGui.OpenPopup(ctx, popup_id)
  end

  if ImGui.IsItemHovered(ctx) then
    ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_Hand)
  end

  ImGui.PopStyleColor(ctx, 4)
  ImGui.PopStyleVar(ctx)

  local changed = false
  local committed = false

  if ImGui.BeginPopup(ctx, popup_id) then
    st.preset_popup_open = true

    local preset_clicked, preset_color = draw_preset_grid(ctx, id, presets, grid_w, preset_button_size, preset_spacing, color)
    if preset_clicked and type(preset_color) == "number" then
      committed = true
      st.picker_start_color = nil
      if preset_color ~= color then
        color = preset_color
        changed = true
      end
      ImGui.CloseCurrentPopup(ctx)
      ImGui.EndPopup(ctx)
      return changed, color, committed
    end

    ImGui.Spacing(ctx)

    local picker_id = id .. "_custom"
    local picker_changed, picker_color, picker_committed, picker_opened = color_picker.draw(ctx, picker_id, color, {
      width = -1,
      height = picker_button_h,
      rounding = picker_button_h / 2,
      enable_alpha = opts.enable_alpha == true,
    })

    if picker_opened then
      st.picker_start_color = color
    end

    if picker_changed and type(picker_color) == "number" and picker_color ~= color then
      color = picker_color
      changed = true
    end

    if picker_committed then
      committed = true
      st.picker_start_color = nil
      ImGui.CloseCurrentPopup(ctx) -- close preset popup too
    end

    -- If the picker closed (Cancel or click-outside) while the preset popup is still open,
    -- we can drop the session so closing the preset popup won't revert anything.
    if st.picker_start_color then
      local picker_popup_id = "##" .. picker_id .. "_picker"
      if not ImGui.IsPopupOpen(ctx, picker_popup_id) then
        st.picker_start_color = nil
      end
    end

    ImGui.EndPopup(ctx)
  end

  -- If the preset popup closed while the picker was open, revert like Cancel.
  if st.picker_start_color and not st.preset_popup_open then
    if color ~= st.picker_start_color then
      color = st.picker_start_color
      changed = true
    end
    st.picker_start_color = nil
  end

  return changed, color, committed
end

return color_preset_picker
