-- @noindex

local articulation_manager = {}

local articulation_manager_menu = require("UI.editor.components.articulation_manager_menu")
local articulation_manager_list = require("UI.editor.components.articulation_manager_list")
local articulation_manager_footer = require("UI.editor.components.articulation_manager_footer")

local LEFT_SIDE_W = 250
local child_flags = ImGui.ChildFlags_Borders

function articulation_manager.draw(ctx, modal_center_x, modal_center_y)
  local window_flags = ImGui.WindowFlags_MenuBar
  if ImGui.BeginChild(ctx, "articulation_manager", LEFT_SIDE_W, 0, child_flags, window_flags) then
    articulation_manager_menu.draw(ctx, modal_center_x, modal_center_y)

    local footer_h = ImGui.GetFrameHeightWithSpacing(ctx)
    if ImGui.BeginChild(ctx, "articulation_manager_list", 0, -footer_h) then
      articulation_manager_list.draw(ctx)
      ImGui.EndChild(ctx)
    end

    articulation_manager_footer.draw(ctx)

    ImGui.EndChild(ctx)
  end
end

return articulation_manager
