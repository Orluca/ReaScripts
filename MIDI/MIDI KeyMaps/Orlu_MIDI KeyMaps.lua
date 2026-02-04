-- @description MIDI KeyMaps
-- @version 1.02
-- @author Orlu
-- @about
--   Dockable on-screen MIDI keyboard allowing you to visualize which keys of the selected track/VST
--   instrument have samples mapped to them. Support for instruments with multiple articulations, and 
--   auto-switching those articulations via MIDI triggers.
--   Requires ReaImGui to be installed.
-- @provides
--   [nomain] data/articulations.lua
--   [nomain] data/constants.lua
--   [nomain] data/presets.lua
--   [nomain] data/reaticulate.lua
--   [nomain] midi/input.lua
--   [nomain] midi/notes.lua
--   [nomain] UI/editor/components/articulation_editor.lua
--   [nomain] UI/editor/components/articulation_editor_name.lua
--   [nomain] UI/editor/components/articulation_editor_trigger.lua
--   [nomain] UI/editor/components/articulation_editor_zones.lua
--   [nomain] UI/editor/components/articulation_manager.lua
--   [nomain] UI/editor/components/articulation_manager_footer.lua
--   [nomain] UI/editor/components/articulation_manager_list.lua
--   [nomain] UI/editor/components/articulation_manager_menu.lua
--   [nomain] UI/editor/components/articulation_manager_reaticulate_importer.lua
--   [nomain] UI/editor/editor.lua
--   [nomain] UI/main/components/info_line.lua
--   [nomain] UI/main/components/keyboard.lua
--   [nomain] UI/main/components/menu.lua
--   [nomain] UI/main/main.lua
--   [nomain] UI/settings/settings.lua
--   [nomain] UI/widgets/button.lua
--   [nomain] UI/widgets/color_picker.lua
--   [nomain] UI/widgets/color_preset_picker.lua
--   [nomain] UI/widgets/header.lua
--   [nomain] UI/widgets/input_midi.lua
--   [nomain] UI/widgets/input_note.lua
--   [nomain] utils/json.lua
--   [nomain] utils/math.lua
--   [nomain] utils/path.lua
--   [nomain] utils/serialize.lua
-- @changelog
--   Reaticulate Importer: Fixed bug where start note and end note changed just from activating the inputs
--   Reaticulate Importer: When start note exceeds end note adjust end note accordingly, and vice versa


local script_path = debug.getinfo(1, 'S').source:match([[^@?(.*[\\/])[^\\/]-$]])
package.path = script_path .. "?.lua;" .. package.path
local sep = package.config:sub(1, 1)
local imgui_path = reaper.ImGui_GetBuiltinPath()
if imgui_path then
  package.path = imgui_path .. sep .. "?.lua;" .. package.path
end

ImGui = require 'imgui' '0.10'

local main = require("UI.main.main")
local midi_input = require("midi.input")
local articulations = require("data.articulations")
local settings = require("UI.settings.settings")

local ENABLE_PROFILER = false
local defer = reaper.defer

local profiler = nil
if ENABLE_PROFILER then
  profiler = dofile(reaper.GetResourcePath() .. '/Scripts/ReaTeam Scripts/Development/cfillion_Lua profiler.lua')
  defer = profiler.defer
end

local ctx = ImGui.CreateContext('Orlu MIDI KeyMaps')

local last_move_titlebar_only = nil

-- Keep toolbar button "on" while the script is running.
local function set_toolbar_toggle_state(state)
  local _, _, section_id, cmd_id = reaper.get_action_context()
  if not section_id or not cmd_id or cmd_id == 0 then
    return
  end
  reaper.SetToggleCommandState(section_id, cmd_id, state and 1 or 0)
  reaper.RefreshToolbar2(section_id, cmd_id)
end

set_toolbar_toggle_state(true)
reaper.atexit(function()
  set_toolbar_toggle_state(false)
end)

local function loop()
  articulations.check_track_change()
  midi_input.update()
  midi_input.set_learn_active(false)
  local move_titlebar_only = settings.hide_main_window_titlebar and 0 or 1
  if move_titlebar_only ~= last_move_titlebar_only then
    ImGui.SetConfigVar(ctx, ImGui.ConfigVar_WindowsMoveFromTitleBarOnly, move_titlebar_only)
    last_move_titlebar_only = move_titlebar_only
  end
  local open = main.draw(ctx)
  if not midi_input.is_learn_active() then
    articulations.apply_midi_triggers()
  end
  if open then
    defer(loop)
  end
end

defer(loop)

if ENABLE_PROFILER and profiler then
  profiler.attachToWorld()
  profiler.run()
end
