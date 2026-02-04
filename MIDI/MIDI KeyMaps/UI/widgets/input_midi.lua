-- @noindex

local input_midi = {}

local midi_input = require("midi.input")

---@type ImGui_Function|nil
local refresh_value = nil
local states = {}

local function flag(v)
  if type(v) == "function" then
    v = v()
  end
  return (type(v) == "number") and v or 0
end

local function clamp_int(n, min_val, max_val)
  if n < min_val then
    return min_val
  end
  if n > max_val then
    return max_val
  end
  return n
end

local function ensure_refresh_fn()
  if refresh_value and not ImGui.ValidatePtr(refresh_value, "ImGui_Function*") then
    refresh_value = nil
  end

  if refresh_value then
    return
  end

  refresh_value = ImGui.CreateFunctionFromEEL([[
    // A) Force-update buffer from Lua
    u_trigger == 1 ? (
      InputTextCallback_DeleteChars(0, strlen(#Buf));
      sprintf(#temp, "%d", u_value);
      InputTextCallback_InsertChars(0, #temp);
      u_trigger = 0;
    );

    // B) Character filter (digits + '-')
    EventFlag == u_charfilter ? (
      (EventChar < '0' || EventChar > '9') && EventChar != '-' ? (
        EventChar = 0;
      );
    );
  ]])

  if refresh_value then
    local fn = refresh_value
    ---@cast fn ImGui_Function
    ImGui.Function_SetValue(fn, "u_charfilter", flag(ImGui.InputTextFlags_CallbackCharFilter))
  end
end

local function push_value(value)
  local fn = refresh_value
  if not fn then
    return
  end
  ---@cast fn ImGui_Function

  ImGui.Function_SetValue(fn, "u_value", value)
  ImGui.Function_SetValue(fn, "u_trigger", 1)
end

local function get_state(label)
  local st = states[label]
  if not st then
    st = {last_learn_seq = 0}
    states[label] = st
  end
  return st
end

---@class InputMidiOptions
---@field flags? integer|fun():integer Extra ImGui.InputTextFlags_*
---@field step? integer Mouse wheel step size. Default: 1
---@field learn_msg_type? integer Enable MIDI learn by specifying a MIDI message type (e.g. midi_input.MSG_TYPE.cc or midi_input.MSG_TYPE.pc). Learns val1.

---Draw an integer MIDI input that supports wheel increments and optional MIDI learn.
---
---To keep the field active while updating (wheel/MIDI learn), this widget uses an
---InputText callback created via CreateFunctionFromEEL to replace the active buffer.
---@param ctx ImGui_Context
---@param label string Unique label/ID
---@param value integer Current value
---@param min_val integer Clamp minimum
---@param max_val integer Clamp maximum
---@param opts? InputMidiOptions
---@return boolean changed
---@return integer value
function input_midi.draw(ctx, label, value, min_val, max_val, opts)
  opts = opts or {}
  ensure_refresh_fn()

  local st = get_state(label)
  local learn_type = tonumber(opts.learn_msg_type)

  local minv = math.floor(tonumber(min_val) or 0)
  local maxv = math.floor(tonumber(max_val) or 127)
  if maxv < minv then
    minv, maxv = maxv, minv
  end

  local val = math.floor(tonumber(value) or 0)
  val = clamp_int(val, minv, maxv)

  local current_str = tostring(val)

  local inp_flags = flag(ImGui.InputTextFlags_CallbackAlways) |
                    flag(ImGui.InputTextFlags_CallbackCharFilter) |
                    flag(opts.flags)

  local _, buf = ImGui.InputText(ctx, label, current_str, inp_flags, refresh_value)

  local is_active = ImGui.IsItemActive(ctx)
  if is_active and learn_type then
    midi_input.set_learn_active(true)
  end
  local activated = ImGui.IsItemActivated(ctx)

  if activated and learn_type then
    -- Snapshot current input so MIDI learn only reacts AFTER focusing.
    local seq = midi_input.get_last_event(learn_type)
    if type(seq) == "number" then
      st.last_learn_seq = seq
    end
  end

  -- 1) MIDI LEARN
  if is_active and learn_type then
    local seq, learned = midi_input.get_last_event(learn_type)

    if type(seq) == "number" and seq ~= 0 and seq ~= st.last_learn_seq and type(learned) == "number" then
      st.last_learn_seq = seq
      local new_val = clamp_int(math.floor(learned), minv, maxv)
      if new_val ~= val then
        push_value(new_val)
        return true, new_val
      end
    end
  end

  -- 2) MOUSE WHEEL
  if is_active and ImGui.IsItemHovered(ctx) then
    local wheel = ImGui.GetMouseWheel(ctx)
    if wheel ~= 0 then
      local step = math.max(1, math.floor(tonumber(opts.step) or 1))
      local direction = (wheel > 0) and 1 or -1
      local new_val = clamp_int(val + (direction * step), minv, maxv)
      if new_val ~= val then
        push_value(new_val)
        return true, new_val
      end
    end
  end

  -- 3) VALIDATION ON DEACTIVATE
  if ImGui.IsItemDeactivated(ctx) then
    if type(buf) == "string" then
      local to_num = tonumber(buf)
      if to_num then
        local new_val = clamp_int(math.floor(to_num), minv, maxv)
        return new_val ~= val, new_val
      end
    end

    -- Snap-back if invalid
    push_value(val)
  end

  return false, val
end

return input_midi
