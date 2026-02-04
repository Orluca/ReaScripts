-- @noindex

local json = require("utils.json")
local path = require("utils.path")
local articulations = require("data.articulations")

local presets = {}


local function parent_dir(path)
  return (type(path) == 'string') and path:match('^(.*)[/\\][^/\\]+$') or nil
end

local function ensure_dir(path)
  if type(path) ~= 'string' or path == '' then
    return
  end
  reaper.RecursiveCreateDirectory(path, 0)
end

local function ensure_json_ext(path)
  if type(path) ~= 'string' then
    return path
  end
  if not path:lower():match('%.json$') then
    return path .. '.json'
  end
  return path
end

local function sanitize_component(s)
  s = tostring(s or '')
  -- Sanitize a single path component (no separators).
  s = s:gsub('[<>:"|?*/\\]', '_')
  s = s:gsub('^%s+', ''):gsub('%s+$', '')
  if s == '' then
    s = 'Preset'
  end
  return s
end

local function get_script_dir()
  local _, filename = reaper.get_action_context()
  if type(filename) ~= 'string' or filename == '' then
    return nil
  end
  return filename:match('^(.*)[/\\]')
end

local function get_presets_dir()
  local script_dir = get_script_dir()
  if not script_dir then
    return nil
  end
  return path.join(script_dir, 'presets')
end

local function build_payload()
  return {
    version = 1,
    articulations = articulations.items or {}
  }
end

local function default_filename()
  local track = reaper.GetSelectedTrack(0, 0)
  if track then
    local _, name = reaper.GetTrackName(track)
    if type(name) == 'string' and name ~= '' then
      return sanitize_component(name) .. '.json'
    end
  end
  return 'Preset.json'
end

local function browse_save_file(initial_dir, initial_file)
  local default_name = tostring(initial_file or 'Preset.json'):gsub('%.json$', '')

  -- NOTE: We intentionally avoid reaper.JS_Dialog_BrowseForSaveFile here.
  -- Some users reported hard-freezes in REAPER when performing file operations
  -- (e.g. deleting files) inside the native OS dialog.
  --
  -- This text-based path dialog is simple but stable, and still allows users
  -- to organize presets via slash-separated subfolders.
  local ok, csv = reaper.GetUserInputs(
    'Save Preset',
    1,
    'Path (use / for folders):,extrawidth=220',
    default_name
  )
  if not ok or type(csv) ~= 'string' or csv == '' then
    return nil
  end

  local rel = csv:gsub('\\', '/')
  local parts = {}
  for part in rel:gmatch('[^/]+') do
    parts[#parts + 1] = sanitize_component(part)
  end
  if #parts == 0 then
    return nil
  end

  local file = ensure_json_ext(parts[#parts])
  parts[#parts] = nil

  local dir = initial_dir
  for _, p in ipairs(parts) do
    dir = path.join(dir, p)
  end

  return path.join(dir, file)
end

local function write_file(path, data)
  local f, err = io.open(path, 'w')
  if not f then
    return false, err
  end
  f:write(data)
  f:close()
  return true
end

function presets.save_current()
  local presets_dir = get_presets_dir()
  if not presets_dir then
    reaper.ShowMessageBox('Could not determine script directory (get_action_context filename missing).', 'Save Preset', 0)
    return false
  end

  ensure_dir(presets_dir)

  local file = browse_save_file(presets_dir, default_filename())
  if not file then
    return false
  end

  file = ensure_json_ext(file)

  local dir = parent_dir(file)
  if dir then
    ensure_dir(dir)
  end

  local payload = build_payload()
  local ok, encoded = pcall(json.encode, payload)
  if not ok then
    reaper.ShowMessageBox('Failed to encode preset JSON:\n\n' .. tostring(encoded), 'Save Preset', 0)
    return false
  end

  local ok_write, err = write_file(file, encoded)
  if not ok_write then
    reaper.ShowMessageBox('Failed to write preset file:\n\n' .. tostring(err), 'Save Preset', 0)
    return false
  end

  return true
end


local function sort_ci(a, b)
  return tostring(a.name):lower() < tostring(b.name):lower()
end

---Get the root presets directory for this script (creates it if missing).
---@return string|nil dir
function presets.get_dir()
  local dir = get_presets_dir()
  if dir then
    ensure_dir(dir)
  end
  return dir
end

---List preset subdirectories and .json preset files in a directory.
---@param dir string
---@return table dirs {name=string, path=string}[]
---@return table files {name=string, path=string}[]
function presets.list_dir(dir, refresh)
  if type(dir) ~= 'string' or dir == '' then
    return {}, {}
  end
  if refresh then
    -- Refresh REAPER's directory cache when explicitly requested.
    reaper.EnumerateSubdirectories(dir, -1)
    reaper.EnumerateFiles(dir, -1)
  end

  local dirs = {}
  for i = 0, math.huge do
    local name = reaper.EnumerateSubdirectories(dir, i)
    if not name then
      break
    end
    dirs[#dirs + 1] = { name = name, path = path.join(dir, name) }
  end

  local files = {}
  for i = 0, math.huge do
    local name = reaper.EnumerateFiles(dir, i)
    if not name then
      break
    end
    if tostring(name):lower():match('%.json$') then
      files[#files + 1] = { name = name, path = path.join(dir, name) }
    end
  end

  table.sort(dirs, sort_ci)
  table.sort(files, sort_ci)
  return dirs, files
end

local function read_file(path)
  local f, err = io.open(path, 'r')
  if not f then
    return nil, err
  end
  local content = f:read('*a')
  f:close()
  return content
end

---Load a preset JSON file and replace the current track's articulations.
---@param path string
---@return boolean ok
function presets.load_file(path)
  if type(path) ~= 'string' or path == '' then
    return false
  end

  local content, err = read_file(path)
  if not content then
    reaper.ShowMessageBox('Failed to read preset file:\n\n' .. tostring(err), 'Load Preset', 0)
    return false
  end

  local ok, decoded = pcall(json.decode, content)
  if not ok then
    reaper.ShowMessageBox('Failed to parse preset JSON:\n\n' .. tostring(decoded), 'Load Preset', 0)
    return false
  end

  local items = nil
  if type(decoded) == 'table' then
    if type(decoded.articulations) == 'table' then
      items = decoded.articulations
    elseif decoded[1] ~= nil then
      -- Allow presets that are just a raw articulations array.
      items = decoded
    end
  end

  if type(items) ~= 'table' then
    reaper.ShowMessageBox('Invalid preset file: missing articulations array.', 'Load Preset', 0)
    return false
  end

  articulations.replace_all(items)
  return true
end


---Build a snapshot tree of the presets directory. Intended for UI menus.
---This scans the directory structure once and returns a nested table.
---@param root_dir string
---@return table tree {path=string, dirs=table, files=table}
function presets.build_tree(root_dir)
  if type(root_dir) ~= 'string' or root_dir == '' then
    return { path = '', dirs = {}, files = {} }
  end

  local dirs, files = presets.list_dir(root_dir, true)
  local tree = { path = root_dir, dirs = {}, files = files }

  for _, d in ipairs(dirs) do
    tree.dirs[#tree.dirs + 1] = {
      name = d.name,
      path = d.path,
      node = presets.build_tree(d.path)
    }
  end

  return tree
end

return presets