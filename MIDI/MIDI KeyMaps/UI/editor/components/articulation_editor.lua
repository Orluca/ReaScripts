-- @noindex

local articulation_editor = {}

local articulations = require("data.articulations")

local articulation_editor_name = require("UI.editor.components.articulation_editor_name")
local articulation_editor_trigger = require("UI.editor.components.articulation_editor_trigger")
local articulation_editor_zones = require("UI.editor.components.articulation_editor_zones")

local child_flags = ImGui.ChildFlags_Borders

function articulation_editor.draw(ctx)
  if ImGui.BeginChild(ctx, "articulation_editor", 0, 0, child_flags) then
    if not articulations.get_active() then
      ImGui.EndChild(ctx)
      return
    end

    articulation_editor_name.draw(ctx)
    ImGui.Spacing(ctx)

    articulation_editor_trigger.draw(ctx)
    ImGui.Spacing(ctx)

    articulation_editor_zones.draw(ctx)

    ImGui.EndChild(ctx)
  end
end

return articulation_editor
