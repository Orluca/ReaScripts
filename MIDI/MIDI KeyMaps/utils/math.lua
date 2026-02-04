-- @noindex

local M = {}

---Round to nearest integer.
---@param n number
---@return number
function M.round(n)
  return math.floor(n + 0.5)
end

---Clamp a value to the byte range (0-255) after rounding.
---@param v number
---@return number
function M.clamp_byte(v)
  return math.max(0, math.min(255, M.round(v)))
end

---Clamp a value to an integer range after flooring.
---@param v number|nil
---@param lo integer
---@param hi integer
---@return integer
function M.clamp_int(v, lo, hi)
  local n = math.floor(tonumber(v) or lo)
  if n < lo then return lo end
  if n > hi then return hi end
  return n
end

return M
