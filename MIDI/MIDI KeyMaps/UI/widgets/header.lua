-- @noindex

local header = {}

local DEFAULT_SCALE = 1.25

---@class HeaderOptions
---@field scale? number Font scale multiplier. Default: 1.25

---Draw a section header with larger text.
---@param ctx ImGui_Context
---@param label string
---@param opts? HeaderOptions
function header.draw(ctx, label, opts)
  opts = opts or {}
  local scale = opts.scale or DEFAULT_SCALE

  local base = ImGui.GetFontSize(ctx)
  ImGui.PushFont(ctx, nil, base * scale)
  ImGui.SeparatorText(ctx, label)
  ImGui.PopFont(ctx)
end

return header
