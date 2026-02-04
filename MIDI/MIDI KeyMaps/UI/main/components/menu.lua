-- @noindex

local button = require("UI.widgets.button")
local settings = require("UI.settings.settings")
local editor = require("UI.editor.editor")

local menu = {}

local BUTTON_SIZE = 20

local MENU_BUTTON_COLORS = {
  button = 0x1E1E1EFF,
  hovered = 0x2A2A2AFF,
  active = 0x151515FF,
  text = 0xEAEAEAFF,
  border = 0x3c3c3cFF
}

local MENU_BUTTON_STYLE = {
  w = BUTTON_SIZE,
  h = BUTTON_SIZE,
  colors = MENU_BUTTON_COLORS,
  border_size = 1
}

function menu.get_size(ctx)
  local _, spacing_y = ImGui.GetStyleVar(ctx, ImGui.StyleVar_ItemSpacing)
  local width = BUTTON_SIZE
  local height = (BUTTON_SIZE * 2) + spacing_y
  return width, height
end

function menu.draw(ctx)
  ImGui.BeginGroup(ctx)
  if button.draw(ctx, "S", MENU_BUTTON_STYLE) then
    settings.is_open = not settings.is_open
  end

  if button.draw(ctx, "E", MENU_BUTTON_STYLE) then
    editor.is_open = not editor.is_open
  end
  ImGui.EndGroup(ctx)
end

return menu