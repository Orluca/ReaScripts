-- @noindex

local midi = {}

midi.MSG_TYPE = {
  note_off = 8,
  note_on = 9,
  aftertouch = 10,
  cc = 11,
  pc = 12,
  channel_pressure = 13,
  pitch_bend = 14,
  sysex = 15
}

local MAX_RECENT_EVENTS = 20
local last_seq = 0
local recent_events = {}
local active_notes = {}
local last_note_on_seq = 0
local last_note_on_note = nil
local last_note_on_vel = nil
local last_note_on_channel = nil
local last_cc_seq = 0
local last_cc_num = nil
local last_cc_val = nil
local last_cc_channel = nil
local last_pc_seq = 0
local last_pc_num = nil
local last_pc_channel = nil
local learn_active = false

---Unpack raw MIDI bytes.
---@param msg string
---@return number msg_type
---@return number val1
---@return number val2
---@return number channel 1-16
local function unpack_midi_message(msg)
  if msg == nil or #msg < 1 then
    return -1, -1, -1, -1
  end

  local status = msg:byte(1)
  local msg_type = status >> 4
  local msg_channel = (status & 0x0F) + 1
  local val1 = msg:byte(2) or 0
  local val2 = msg:byte(3) or 0

  return msg_type, val1, val2, msg_channel
end

local function apply_event(ev)
  if ev.msg_type == midi.MSG_TYPE.note_on then
    if ev.val2 == 0 then
      active_notes[ev.val1] = nil
    else
      active_notes[ev.val1] = ev.val2
      last_note_on_seq = ev.seq
      last_note_on_note = ev.val1
      last_note_on_vel = ev.val2
      last_note_on_channel = ev.channel
    end
  elseif ev.msg_type == midi.MSG_TYPE.note_off then
    active_notes[ev.val1] = nil
  elseif ev.msg_type == midi.MSG_TYPE.cc then
    last_cc_seq = ev.seq
    last_cc_num = ev.val1
    last_cc_val = ev.val2
    last_cc_channel = ev.channel
  elseif ev.msg_type == midi.MSG_TYPE.pc then
    last_pc_seq = ev.seq
    last_pc_num = ev.val1
    last_pc_channel = ev.channel
  end
end

local function get_new_events(prev_seq)
  local events = {}

  for idx = 0, MAX_RECENT_EVENTS - 1 do
    local seq, buf = reaper.MIDI_GetRecentInputEvent(idx)
    if seq == 0 or seq == prev_seq then
      break
    end

    local msg_type, val1, val2, channel = unpack_midi_message(buf)
    if msg_type >= 0 then
      events[#events + 1] = {
        seq = seq,
        msg_type = msg_type,
        val1 = val1,
        val2 = val2,
        channel = channel,
        raw = buf
      }
    end
  end

  return events
end

---Polls new MIDI input events and updates active note state.
function midi.update()
  local latest_seq = reaper.MIDI_GetRecentInputEvent(0)
  if latest_seq == 0 or latest_seq == last_seq then
    recent_events = {}
    return
  end

  local events = get_new_events(last_seq)
  recent_events = events

  for i = #events, 1, -1 do
    apply_event(events[i])
  end

  last_seq = latest_seq
end

---Returns events captured by the last midi.update() call.
---@return table
function midi.get_recent_events()
  return recent_events
end

---Set whether a MIDI-learn input is currently active (set each frame).
---@param active boolean
function midi.set_learn_active(active)
  learn_active = (active == true)
end

---@return boolean
function midi.is_learn_active()
  return learn_active
end


---Return last received Note On (velocity>0). Returns seq=0 if none.
---@return integer seq
---@return integer|nil note
---@return integer|nil velocity
---@return integer|nil channel
function midi.get_last_note_on()
  return last_note_on_seq, last_note_on_note, last_note_on_vel, last_note_on_channel
end

---Return last received event for a given message type. Returns seq=0 if none.
---@param msg_type integer
---@return integer seq
---@return integer|nil val1
---@return integer|nil val2
---@return integer|nil channel
function midi.get_last_event(msg_type)
  local t = tonumber(msg_type)
  if t == midi.MSG_TYPE.note_on then
    return last_note_on_seq, last_note_on_note, last_note_on_vel, last_note_on_channel
  end
  if t == midi.MSG_TYPE.cc then
    return last_cc_seq, last_cc_num, last_cc_val, last_cc_channel
  end
  if t == midi.MSG_TYPE.pc then
    return last_pc_seq, last_pc_num, nil, last_pc_channel
  end
  return 0, nil, nil, nil
end

---Return the active notes table (note -> velocity).
---@return table
function midi.get_active_notes()
  return active_notes
end

return midi
