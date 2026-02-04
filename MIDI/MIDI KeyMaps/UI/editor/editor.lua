-- @noindex

local editor = {
  is_open = false
}

---@type { draw: fun(ctx: ImGui_Context, modal_center_x: number, modal_center_y: number) }
local articulation_manager = require("UI.editor.components.articulation_manager")
local articulation_editor = require("UI.editor.components.articulation_editor")

local window_flags = ImGui.WindowFlags_NoDocking

local MIN_W, MIN_H = 750, 500
local MAX_W, MAX_H = 1000, 1000

local function get_target_track()
  if reaper.CountSelectedTracks(0) == 0 then
    return nil
  end

  local tr
  if type(reaper.GetSelectedTrack2) == "function" then
    tr = reaper.GetSelectedTrack2(0, 0, true)
  else
    tr = reaper.GetSelectedTrack(0, 0)
  end

  if not tr then
    return nil
  end

  local master = reaper.GetMasterTrack(0)
  if master and tr == master then
    return nil
  end

  return tr
end

local function draw_select_track_modal(ctx, center_x, center_y)
  local popup_id = "Select Track##editor_select_track"

  if not ImGui.IsPopupOpen(ctx, popup_id) then
    ImGui.OpenPopup(ctx, popup_id)
  end

  local flags = ImGui.WindowFlags_AlwaysAutoResize

  local cond = ImGui.Cond_Appearing
  if type(cond) == "function" then
    cond = cond()
  end
  ImGui.SetNextWindowPos(ctx, center_x or 0, center_y or 0, cond, 0.5, 0.5)

  local visible, open = ImGui.BeginPopupModal(ctx, popup_id, true, flags)
  if visible then
    ImGui.Text(ctx, "Please select a track to start editing.")
    ImGui.Spacing(ctx)

    local close_editor = false

    if ImGui.Button(ctx, "Close Editor") then
      close_editor = true
      ImGui.CloseCurrentPopup(ctx)
    end

    ImGui.EndPopup(ctx)
    return close_editor
  end

  return false
end

function editor.draw(ctx)
  ImGui.SetNextWindowBgAlpha(ctx, 1)
  ImGui.SetNextWindowSizeConstraints(ctx, MIN_W, MIN_H, MAX_W, MAX_H)
  local visible, open = ImGui.Begin(ctx, "Editor", editor.is_open, window_flags)
  if visible then
    local wx, wy = ImGui.GetWindowPos(ctx)
    local ww, wh = ImGui.GetWindowSize(ctx)
    local center_x = wx + (ww * 0.5)
    local center_y = wy + (wh * 0.5)

    local tr = get_target_track()
    if not tr then
      local close_editor = draw_select_track_modal(ctx, center_x, center_y)
      if close_editor then
        open = false
      end
      ImGui.End(ctx)
      editor.is_open = open
      return
    end

    articulation_manager.draw(ctx, center_x, center_y)
    ImGui.SameLine(ctx)
    articulation_editor.draw(ctx)

    ImGui.End(ctx)
  end

  editor.is_open = open
end

return editor
