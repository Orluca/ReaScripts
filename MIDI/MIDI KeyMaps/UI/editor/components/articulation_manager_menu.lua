-- @noindex

local articulation_manager_menu = {}

local articulation_manager_list = require("UI.editor.components.articulation_manager_list")
local articulations = require("data.articulations")
local presets = require("data.presets")
local button = require("UI.widgets.button")
local reaticulate_importer = require("UI.editor.components.articulation_manager_reaticulate_importer")

local CLEAR_ALL_POPUP_ID = "Clear All Articulations"

local load_preset_tree = nil
local load_preset_open_prev = false

local function open_in_file_manager(path)
  if type(path) ~= "string" or path == "" then
    return false
  end

  if type(reaper.CF_ShellExecute) == "function" then
    reaper.CF_ShellExecute(path)
    return true
  end

  -- Last-resort fallback without extensions.
  local os_name = (type(reaper.GetOS) == "function") and reaper.GetOS() or ""
  local p = path:gsub('"', '')

  if os_name:match('Win') then
    os.execute('explorer "' .. p:gsub('/', '\\') .. '"')
  elseif os_name:match('OSX') or os_name:match('mac') then
    os.execute('open "' .. p .. '"')
  else
    os.execute('xdg-open "' .. p .. '"')
  end

  return true
end



local function draw_load_preset_menu(ctx, node)
  if type(node) ~= "table" then
    ImGui.MenuItem(ctx, "(empty)", nil, nil, false)
    return
  end

  local dirs = node.dirs or {}
  local files = node.files or {}

  if #dirs == 0 and #files == 0 then
    ImGui.MenuItem(ctx, "(empty)", nil, nil, false)
    return
  end

  for _, d in ipairs(dirs) do
    if ImGui.BeginMenu(ctx, tostring(d.name) .. "##" .. tostring(d.path), true) then
      draw_load_preset_menu(ctx, d.node)
      ImGui.EndMenu(ctx)
    end
  end

  for _, f in ipairs(files) do
    local label = tostring(f.name):gsub('%.json$', '')
    if ImGui.MenuItem(ctx, label .. "##" .. tostring(f.path)) then
      presets.load_file(f.path)
    end
  end
end

local function draw_clear_all_modal(ctx, center_x, center_y, open_requested)
  if open_requested and type(center_x) == "number" and type(center_y) == "number" then
    local cond = ImGui.Cond_Appearing
    if type(cond) == "function" then
      cond = cond()
    end
    ImGui.SetNextWindowPos(ctx, center_x, center_y, cond, 0.5, 0.5)
  end
  if ImGui.BeginPopupModal(ctx, CLEAR_ALL_POPUP_ID, nil, ImGui.WindowFlags_AlwaysAutoResize) then
    ImGui.Text(ctx, "This will delete all articulations.")
    ImGui.Text(ctx, "Are you sure you want to continue?")
    ImGui.Spacing(ctx)
    ImGui.Spacing(ctx)

    local spacing_x, _ = ImGui.GetStyleVar(ctx, ImGui.StyleVar_ItemSpacing)
    local avail_w = ImGui.GetContentRegionAvail(ctx)
    local button_w = math.max(0, (avail_w - spacing_x) * 0.5)

    if button.draw(ctx, "Confirm##clear_all", { w = button_w }) then
      articulation_manager_list.clear_all()
      ImGui.CloseCurrentPopup(ctx)
    end

    ImGui.SameLine(ctx)

    if button.draw(ctx, "Cancel##clear_all", { w = button_w }) then
      ImGui.CloseCurrentPopup(ctx)
    end

    ImGui.EndPopup(ctx)
  end
end

function articulation_manager_menu.draw(ctx, modal_center_x, modal_center_y)

  local open_clear_all = false
  local request_save_preset = false

  if ImGui.BeginMenuBar(ctx) then
    if ImGui.BeginMenu(ctx, "File", true) then
      local load_open = false
      if ImGui.BeginMenu(ctx, "Load Preset", true) then
        load_open = true

        if not load_preset_open_prev then
          local dir = presets.get_dir()
          load_preset_tree = dir and presets.build_tree(dir) or nil
        end

        if not load_preset_tree then
          ImGui.MenuItem(ctx, "(presets folder not found)", nil, nil, false)
        else
          draw_load_preset_menu(ctx, load_preset_tree)
        end

        ImGui.EndMenu(ctx)
      end

      if load_preset_open_prev and not load_open then
        load_preset_tree = nil
      end
      load_preset_open_prev = load_open


      if ImGui.MenuItem(ctx, "Save Preset") then
        request_save_preset = true
      end

      if ImGui.MenuItem(ctx, "Open Presets Folder") then
        local dir = presets.get_dir()
        if dir then
          open_in_file_manager(dir)
        else
          reaper.ShowMessageBox("Could not determine presets folder.", "Presets", 0)
        end
      end


      ImGui.Separator(ctx)
      if ImGui.MenuItem(ctx, "Import from Reaticulate") then
        reaticulate_importer.open()
      end

      ImGui.EndMenu(ctx)
    end

    if ImGui.BeginMenu(ctx, "Edit", true) then
      local has_active = articulation_manager_list.has_active()
      local has_any = articulation_manager_list.has_any()

      if ImGui.MenuItem(ctx, "Add") then
        articulation_manager_list.add()
      end
      if ImGui.MenuItem(ctx, "Delete", nil, nil, has_active) then
        articulation_manager_list.delete_active()
      end
      if ImGui.MenuItem(ctx, "Duplicate", nil, nil, has_active) then
        articulation_manager_list.duplicate_active()
      end

      ImGui.Separator(ctx)

      if ImGui.MenuItem(ctx, "Copy Zones", nil, nil, has_active) then
        articulations.copy_zones(articulations.active_index)
      end
      local can_paste = has_active and articulations.has_copied_zones()
      if ImGui.MenuItem(ctx, "Paste Zones", nil, nil, can_paste) then
        articulations.paste_zones(articulations.active_index)
      end

      ImGui.Separator(ctx)

      if ImGui.MenuItem(ctx, "Clear All", nil, nil, has_any) then
        open_clear_all = true
      end

      ImGui.EndMenu(ctx)
    end

    ImGui.EndMenuBar(ctx)
  end

  if request_save_preset then
    -- Defer the modal file dialog until after the current ImGui frame finishes.
    reaper.defer(function() presets.save_current() end)
  end

  -- Open the modal outside of the menu's ID stack, otherwise BeginPopupModal won't match.
  if open_clear_all then
    ImGui.OpenPopup(ctx, CLEAR_ALL_POPUP_ID)
  end

  draw_clear_all_modal(ctx, modal_center_x, modal_center_y, open_clear_all)

  reaticulate_importer.draw(ctx, modal_center_x, modal_center_y)
end

return articulation_manager_menu
