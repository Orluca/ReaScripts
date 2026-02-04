-- @noindex

local input_note = {}

local midi_input = require("midi.input")
local midi_notes = require("midi.notes")

---@type ImGui_Function|nil
local refresh_note = nil
local states = {}

local function flag(v)
  if type(v) == "function" then
    v = v()
  end
  return (type(v) == "number") and v or 0
end

local function clamp_note(n)
  if n < 0 then
    return 0
  end
  if n > 127 then
    return 127
  end
  return n
end

local function ensure_refresh_fn()
  if refresh_note and not ImGui.ValidatePtr(refresh_note, "ImGui_Function*") then
    refresh_note = nil
  end

  if refresh_note then
    return
  end

  refresh_note = ImGui.CreateFunctionFromEEL([[
    u_trigger == 1 ? (
      InputTextCallback_DeleteChars(0, strlen(#Buf));
      InputTextCallback_InsertChars(0, u_note_name);
      u_trigger = 0;
    );
  ]])
end

local function push_text(text)
  local fn = refresh_note
  if not fn then
    return
  end
  ---@cast fn ImGui_Function
  ImGui.Function_SetValue_String(fn, "u_note_name", text)
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

---@class InputNoteOptions
---@field middle_c_mode? number Controls note name formatting/parsing (60=C4 if 4, else C3)
---@field midi_learn? boolean Enable MIDI learn when the input is active. Default: true
---@field commit_while_active? boolean Commit when a valid value is typed while active. Default: false
---@field flags? integer|fun():integer Extra ImGui.InputTextFlags_*

---Draw a MIDI note input that accepts note names (C#4, Db5) or numbers (0-127).
---
---Notes:
---- While the input is active, mouse wheel and MIDI learn updates keep the input active.
---- To update the visible buffer while active, this uses an InputText callback created
---  via CreateFunctionFromEEL.
---@param ctx ImGui_Context
---@param label string Unique label/ID
---@param value integer Current MIDI note (0-127)
---@param opts? InputNoteOptions
---@return boolean changed
---@return integer value
function input_note.draw(ctx, label, value, opts)
  opts = opts or {}
  ensure_refresh_fn()

  local st = get_state(label)
  local learn = (opts.midi_learn ~= false)

  local note = clamp_note(math.floor(tonumber(value) or 0))
  local current_name = midi_notes.note_to_name(note, opts.middle_c_mode)

  local inp_flags = flag(ImGui.InputTextFlags_CallbackAlways) | flag(opts.flags)
  local text_changed, buf = ImGui.InputText(ctx, label, current_name, inp_flags, refresh_note)

  local is_active = ImGui.IsItemActive(ctx)
  if learn and is_active then
    midi_input.set_learn_active(true)
  end
  local activated = ImGui.IsItemActivated(ctx)
  if learn and activated then
    -- Snapshot current input so MIDI learn only reacts to notes played AFTER focusing.
    local seq = midi_input.get_last_note_on()
    if type(seq) == "number" then
      st.last_learn_seq = seq
    end
  end

  -- 0) COMMIT WHILE ACTIVE (optional)
  if opts.commit_while_active and is_active and text_changed and type(buf) == "string" then
    local to_num = tonumber(buf)
    if to_num then
      local n = clamp_note(math.floor(to_num))
      return true, n
    end

    local parsed = midi_notes.name_to_note(buf, opts.middle_c_mode)
    if type(parsed) == "number" then
      return true, parsed
    end
  end

  -- 1) MIDI LEARN
  if learn and is_active then
    local seq, learned_note = midi_input.get_last_note_on()
    if type(seq) == "number" and seq ~= 0 and seq ~= st.last_learn_seq and type(learned_note) == "number" then
      st.last_learn_seq = seq
      learned_note = clamp_note(learned_note)
      push_text(midi_notes.note_to_name(learned_note, opts.middle_c_mode))
      return true, learned_note
    end
  end

  -- 2) MOUSE WHEEL
  if is_active and ImGui.IsItemHovered(ctx) then
    local wheel = ImGui.GetMouseWheel(ctx)
    if wheel ~= 0 then
      local direction = wheel > 0 and 1 or -1
      local new_note = clamp_note(note + direction)
      if new_note ~= note then
        push_text(midi_notes.note_to_name(new_note, opts.middle_c_mode))
        return true, new_note
      end
    end
  end

  -- 3) VALIDATION ON DEACTIVATE
  if ImGui.IsItemDeactivated(ctx) then
    if type(buf) == "string" then
      local to_num = tonumber(buf)
      if to_num then
        return true, clamp_note(math.floor(to_num))
      end

      local parsed = midi_notes.name_to_note(buf, opts.middle_c_mode)
      if type(parsed) == "number" then
        return true, parsed
      end
    end

    -- Snap-back if invalid
    push_text(current_name)
  end

  return false, note
end

return input_note
