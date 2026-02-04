-- @noindex

local path = {}

local SEP = package.config:sub(1, 1)

---Join path segments using the OS separator.
---Strips any trailing slashes/backslashes from each segment before joining.
---@param ... any
---@return string
function path.join(...)
  local parts = {...}
  for i = 1, #parts do
    parts[i] = tostring(parts[i] or ''):gsub('[/\\]+$', '')
  end
  return table.concat(parts, SEP)
end

return path
