-- @noindex

local constants = require("data.constants")

local button = {}

---@class ButtonColors
---@field button? integer RGBA color for default state
---@field hovered? integer RGBA color when hovered
---@field active? integer RGBA color when held/pressed
---@field text? integer RGBA color for text
---@field border? integer RGBA color for border

---@class ButtonOptions
---@field w? number Button width in pixels (nil = auto)
---@field h? number Button height in pixels (nil = auto)
---@field rounding? number Frame rounding. Default: constants.ui.BUTTON_ROUNDING
---@field border_size? number Frame border size in pixels
---@field colors? ButtonColors Style color overrides

---Draw a rounded button with optional style overrides.
---@param ctx ImGui_Context
---@param label string
---@param opts? ButtonOptions
---@return boolean clicked
function button.draw(ctx, label, opts)
  opts = opts or {}
  local w = opts.w
  local h = opts.h
  local rounding = opts.rounding or constants.ui.BUTTON_ROUNDING
  local border_size = opts.border_size
  local colors = opts.colors

  local pushed_vars = 0
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameRounding, rounding)
  pushed_vars = pushed_vars + 1
  if border_size ~= nil then
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameBorderSize, border_size)
    pushed_vars = pushed_vars + 1
  end

  local pushed_colors = 0
  if colors then
    if colors.button then
      ImGui.PushStyleColor(ctx, ImGui.Col_Button, colors.button)
      pushed_colors = pushed_colors + 1
    end
    if colors.hovered then
      ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, colors.hovered)
      pushed_colors = pushed_colors + 1
    end
    if colors.active then
      ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, colors.active)
      pushed_colors = pushed_colors + 1
    end
    if colors.text then
      ImGui.PushStyleColor(ctx, ImGui.Col_Text, colors.text)
      pushed_colors = pushed_colors + 1
    end
    if colors.border then
      ImGui.PushStyleColor(ctx, ImGui.Col_Border, colors.border)
      pushed_colors = pushed_colors + 1
    end
  end

  local clicked = ImGui.Button(ctx, label, w, h)

  if ImGui.IsItemHovered(ctx) then
    ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_Hand)
  end

  if pushed_colors > 0 then
    ImGui.PopStyleColor(ctx, pushed_colors)
  end
  ImGui.PopStyleVar(ctx, pushed_vars)

  return clicked
end

return button