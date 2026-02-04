-- @noindex

local reaticulate = {}

local path = require("utils.path")

-- Parses Reaticulate .reabank files into preset/bank definitions.
--
-- A bank starts with a metadata line like:
--   //! g="Vendor/Lib" n="Preset Name"
-- and contains articulation rows like:
--   20 Some articulation name
-- where the leading number is the Program Change value.

local function read_file(path)
  local f = io.open(path, 'r')
  if not f then
    return nil
  end

  local lines = {}
  for line in f:lines() do
    -- Normalize Windows CRLF.
    lines[#lines + 1] = (line:gsub('\r$', ''))
  end
  f:close()
  return lines
end

local function parse_attrs(line)
  local attrs = {}
  for k, v in line:gmatch('(%w+)="([^"]*)"') do
    attrs[k] = v
  end
  return attrs
end

local function parse_reabank_lines(lines, source)
  local presets = {}
  local current = nil

  for _, line in ipairs(lines or {}) do
    if type(line) == 'string' then
      if line:match('^//!') then
        local attrs = parse_attrs(line)
        if attrs.g and attrs.n then
          if current then
            presets[#presets + 1] = current
          end
          current = {
            source = source,
            group = attrs.g,
            name = attrs.n,
            id = nil,
            articulations = {}
          }
        else
          local id = line:match('^//!%s*id=([%w%-]+)')
          if id and current then
            current.id = id
          end
        end
      elseif current then
        local pc, art_name = line:match('^(%d+)%s+(.+)$')
        if pc and art_name then
          pc = tonumber(pc)
          if pc and pc >= 0 and pc <= 127 then
            current.articulations[#current.articulations + 1] = {
              pc = pc,
              name = art_name
            }
          end
        end
      end
    end
  end

  if current then
    presets[#presets + 1] = current
  end

  return presets
end


---Load all available Reaticulate banks.
---@return table user_presets
---@return table factory_presets
function reaticulate.load_presets()
  local resource = reaper.GetResourcePath()

  local user_path = path.join(resource, 'Data', 'Reaticulate.reabank')
  local factory_path = path.join(resource, 'Scripts', 'Reaticulate', 'Reaticulate-factory.reabank')

  local user_lines = read_file(user_path)
  local factory_lines = read_file(factory_path)

  local user_presets = user_lines and parse_reabank_lines(user_lines, 'user') or {}
  local factory_presets = factory_lines and parse_reabank_lines(factory_lines, 'factory') or {}

  return user_presets, factory_presets
end

return reaticulate

