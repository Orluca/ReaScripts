-- @noindex

local input_note = {}

local midi_input = require("midi.input")
local midi_notes = require("midi.notes")

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

local function ensure_refresh_fn(st)
  if st.refresh_fn and not ImGui.ValidatePtr(st.refresh_fn, "ImGui_Function*") then
    st.refresh_fn = nil
  end
  if st.refresh_fn then
    return
  end

  -- IMPORTANT: this function must be per-input instance.
  -- If shared, pending buffer refreshes (wheel/MIDI-learn) can be applied to a
  -- different input that becomes active on the next frame.
  st.refresh_fn = ImGui.CreateFunctionFromEEL([[
    u_trigger == 1 ? (
      InputTextCallback_DeleteChars(0, strlen(#Buf));
      InputTextCallback_InsertChars(0, u_note_name);
      u_trigger = 0;
    );
  ]])
end

local function push_text(st, text)
  local fn = st.refresh_fn
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
    st = { last_learn_seq = 0, refresh_fn = nil, was_active = false, last_value = nil }
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

  local st = get_state(label)
  ensure_refresh_fn(st)

  local learn = (opts.midi_learn ~= false)

  local note = clamp_note(math.floor(tonumber(value) or 0))
  local current_name = midi_notes.note_to_name(note, opts.middle_c_mode)

  -- Keep internal InputText buffer in sync when value changes externally (e.g. after reset).
  if st.last_value ~= note then
    push_text(st, current_name)
  end

  local inp_flags = flag(ImGui.InputTextFlags_CallbackAlways) | flag(opts.flags)
  local text_changed, buf = ImGui.InputText(ctx, label, current_name, inp_flags, st.refresh_fn)

  local was_active = (st.was_active == true)
  local is_active = ImGui.IsItemActive(ctx)
  local activated = ImGui.IsItemActivated(ctx)

  local function finish(changed, new_val)
    st.was_active = is_active
    st.last_value = new_val
    return changed, new_val
  end

  if learn and is_active then
    midi_input.set_learn_active(true)

    -- Snapshot current input so MIDI learn only reacts to notes played AFTER focusing.
    if (not was_active) or activated then
      local seq = midi_input.get_last_note_on()
      if type(seq) == "number" then
        st.last_learn_seq = seq
      end
    end
  end

  -- 0) COMMIT WHILE ACTIVE (optional)
  if opts.commit_while_active and is_active and text_changed and type(buf) == "string" then
    local to_num = tonumber(buf)
    if to_num then
      local n = clamp_note(math.floor(to_num))
      return finish(true, n)
    end

    local parsed = midi_notes.name_to_note(buf, opts.middle_c_mode)
    if type(parsed) == "number" then
      return finish(true, parsed)
    end
  end

  -- 1) MIDI LEARN
  if learn and is_active then
    local seq, learned_note = midi_input.get_last_note_on()
    if type(seq) == "number" and seq ~= 0 and seq ~= st.last_learn_seq and type(learned_note) == "number" then
      st.last_learn_seq = seq
      learned_note = clamp_note(learned_note)
      push_text(st, midi_notes.note_to_name(learned_note, opts.middle_c_mode))
      return finish(true, learned_note)
    end
  end

  -- 2) MOUSE WHEEL
  if is_active and ImGui.IsItemHovered(ctx) then
    local wheel = ImGui.GetMouseWheel(ctx)
    if wheel ~= 0 then
      local direction = wheel > 0 and 1 or -1
      local new_note = clamp_note(note + direction)
      if new_note ~= note then
        push_text(st, midi_notes.note_to_name(new_note, opts.middle_c_mode))
        return finish(true, new_note)
      end
    end
  end

  -- 3) VALIDATION ON DEACTIVATE
  if ImGui.IsItemDeactivated(ctx) then
    if type(buf) == "string" then
      local to_num = tonumber(buf)
      if to_num then
        return finish(true, clamp_note(math.floor(to_num)))
      end

      local parsed = midi_notes.name_to_note(buf, opts.middle_c_mode)
      if type(parsed) == "number" then
        return finish(true, parsed)
      end
    end

    -- Snap-back if invalid
    push_text(st, current_name)
  end

  return finish(false, note)
end

return input_note
