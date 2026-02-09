-- @noindex

local info_line = {}

local articulations = require("data.articulations")
local keyboard = require("UI.main.components.keyboard")

function info_line.draw(ctx)
  local parts = {}

  local active_name = articulations.get_active_name()
  if active_name then
    parts[#parts + 1] = "Articulation: " .. active_name
  else
    parts[#parts + 1] = "No active articulation"
  end

  local zone_label = keyboard.get_hovered_zone_label() or keyboard.get_played_zone_label()
  if zone_label then
    parts[#parts + 1] = "Zone: " .. zone_label
  end

  local trigger_name = keyboard.get_hovered_trigger_articulation_name()
  if trigger_name then
    parts[#parts + 1] = "KS: " .. trigger_name
  end

  ImGui.Text(ctx, table.concat(parts, " | "))
end

return info_line
