-- @noindex

local articulation_editor_name = {}

local header = require("UI.widgets.header")

local articulations = require("data.articulations")

local child_flags = ImGui.ChildFlags_Borders | ImGui.ChildFlags_AutoResizeY

function articulation_editor_name.draw(ctx)
  if ImGui.BeginChild(ctx, "articulation_editor_name", 0, 0, child_flags) then
    header.draw(ctx, "Articulation Name")

    local art = articulations.get_active()

    if not art then
      ImGui.EndChild(ctx)
      return
    end

    ImGui.SetNextItemWidth(ctx, -1)

    local _, buf = ImGui.InputText(ctx, "##articulation_name", art.name or "", ImGui.InputTextFlags_AutoSelectAll)
    if ImGui.IsItemDeactivatedAfterEdit(ctx) then
      articulations.rename(articulations.active_index, buf)
    end

    ImGui.EndChild(ctx)
  end
end

return articulation_editor_name
