-- @noindex

local articulation_manager_footer = {}

local articulation_manager_list = require("UI.editor.components.articulation_manager_list")
local button = require("UI.widgets.button")

function articulation_manager_footer.draw(ctx)
  local spacing_x, _ = ImGui.GetStyleVar(ctx, ImGui.StyleVar_ItemSpacing)
  local button_w = math.max(0, (ImGui.GetContentRegionAvail(ctx) - spacing_x) * 0.5)

  if button.draw(ctx, "Add", { w = button_w }) then
    articulation_manager_list.add()
  end
  ImGui.SameLine(ctx)

  local has_active = articulation_manager_list.has_active()
  if type(ImGui.BeginDisabled) == "function" and type(ImGui.EndDisabled) == "function" then
    ImGui.BeginDisabled(ctx, not has_active)
  end

  if button.draw(ctx, "Delete", { w = button_w }) then
    articulation_manager_list.delete_active()
  end

  if type(ImGui.BeginDisabled) == "function" and type(ImGui.EndDisabled) == "function" then
    ImGui.EndDisabled(ctx)
  end
end

return articulation_manager_footer
