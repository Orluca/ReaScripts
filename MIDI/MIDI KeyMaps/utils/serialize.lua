-- @noindex

local M = {}

local function is_int(n)
  return type(n) == "number" and n % 1 == 0
end

local function is_ident(s)
  return type(s) == "string" and s:match("^[A-Za-z_][A-Za-z0-9_]*$") ~= nil
end

local function serialize_value(v, seen)
  local t = type(v)
  if t == "nil" then
    return "nil"
  elseif t == "number" or t == "boolean" then
    return tostring(v)
  elseif t == "string" then
    return string.format("%q", v)
  elseif t ~= "table" then
    -- Unsupported value type (function, userdata, thread).
    return "nil"
  end

  if seen[v] then
    -- Cycles are not expected in our data; avoid infinite recursion.
    return "nil"
  end
  seen[v] = true

  local parts = {}

  -- Array part first (preserve order).
  local n = #v
  for i = 1, n do
    parts[#parts + 1] = serialize_value(v[i], seen)
  end

  -- Key/value part.
  for k, vv in pairs(v) do
    if not (is_int(k) and k >= 1 and k <= n) then
      local key
      if is_ident(k) then
        key = k
      else
        key = "[" .. serialize_value(k, seen) .. "]"
      end
      parts[#parts + 1] = key .. "=" .. serialize_value(vv, seen)
    end
  end

  seen[v] = nil
  return "{" .. table.concat(parts, ",") .. "}"
end

---Serialize a Lua value (tables with numbers/booleans/strings) into a Lua literal.
---@param v any
---@return string
function M.serialize(v)
  return serialize_value(v, {})
end

---Deserialize a Lua literal (created by M.serialize) back into a Lua value.
---Uses a sandboxed environment.
---@param s string
---@return any|nil
function M.deserialize(s)
  if type(s) ~= "string" or s == "" then
    return nil
  end

  local chunk = load("return " .. s, "orlu_midi_keymaps_deserialize", "t", {})
  if not chunk then
    return nil
  end

  local ok, res = pcall(chunk)
  if not ok then
    return nil
  end

  return res
end

return M
