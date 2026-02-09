-- @noindex

-- Articulation state + (optional) LuaLS/EmmyLua annotations.

local serialize = require("utils.serialize")
local midi_input = require("midi.input")
local constants = require("data.constants")
local settings = require("UI.settings.settings")

local TRACK_EXT_KEY = "P_EXT:Orlu_MIDIKeyMaps"
local last_track = nil
local last_track_guid = nil

---@alias MidiMsgType integer
---@alias ColorU32 integer  -- 0xRRGGBBAA
---@alias ZoneMode integer  -- constants.zone_mode.*

---@class ArticulationTrigger
---@field type MidiMsgType
---@field val1 integer
---@field val2min integer
---@field val2max integer
---@field keyswitch_note? integer

---@class ArticulationZone
---@field label string
---@field mode ZoneMode
---@field color ColorU32
---@field start_note integer
---@field end_note integer

---@class Articulation
---@field name string
---@field trigger ArticulationTrigger
---@field zones ArticulationZone[]

local articulations = {
  ---@type Articulation[]
  items = {},

  -- 1-based index into items (0 = none).
  active_index = 0
}

-- In-memory zone clipboard for Copy/Paste Zones (not persisted).
---@type ArticulationZone[]|nil
local zones_clipboard = nil

local function select_first_if_any()
  articulations.active_index = (#articulations.items > 0) and 1 or 0
end


-- Optional: send the active articulation's trigger when switching via UI.
-- We still guard this by the Settings checkbox + an explicit flag on set_active().
local MIDI_MODE = 0
local MIDI_CHANNEL = 0
local STATUS_NOTE_ON = 0x90 + MIDI_CHANNEL
local STATUS_NOTE_OFF = 0x80 + MIDI_CHANNEL
local STATUS_CC = 0xB0 + MIDI_CHANNEL
local STATUS_PC = 0xC0 + MIDI_CHANNEL

-- When we switch articulations via UI we may optionally send the articulation's trigger.
-- That MIDI can show up again in MIDI_GetRecentInputEvent, so we ignore the next
-- matching event briefly to avoid immediately re-selecting the first articulation
-- that shares the same trigger.
local IGNORE_SELF_TRIGGER_SEC = 0.25

---@class IgnoredMidiTrigger
---@field msg_type integer
---@field val1 integer
---@field val2 integer
---@field channel integer
---@field expires_at number

---@type IgnoredMidiTrigger|nil
local ignored_trigger = nil

local function now_time()
  if type(reaper.time_precise) == "function" then
    return reaper.time_precise()
  end
  return os.clock()
end

local function ignore_next_trigger_event(msg_type, val1, val2, channel)
  ignored_trigger = {
    msg_type = msg_type,
    val1 = val1,
    val2 = val2,
    channel = channel,
    expires_at = now_time() + IGNORE_SELF_TRIGGER_SEC
  }
end

local function should_ignore_trigger_event(ev)
  if not ignored_trigger then
    return false
  end

  if now_time() > ignored_trigger.expires_at then
    ignored_trigger = nil
    return false
  end

  if type(ev) ~= "table" then
    return false
  end

  if ev.msg_type ~= ignored_trigger.msg_type then return false end
  if ev.val1 ~= ignored_trigger.val1 then return false end
  if ev.val2 ~= ignored_trigger.val2 then return false end
  if ev.channel ~= ignored_trigger.channel then return false end

  -- Consume it so we don't ignore unrelated future input.
  ignored_trigger = nil
  return true
end

local function get_target_track()
  if reaper.CountSelectedTracks(0) == 0 then
    return nil
  end

  local tr
  if type(reaper.GetSelectedTrack2) == "function" then
    tr = reaper.GetSelectedTrack2(0, 0, true)
  else
    tr = reaper.GetSelectedTrack(0, 0)
  end

  if not tr then
    return nil
  end

  local master = reaper.GetMasterTrack(0)
  if master and tr == master then
    return nil
  end

  return tr
end

local function send_trigger_for_articulation(art)
  if type(art) ~= "table" then
    return
  end

  local trig = art.trigger
  if type(trig) ~= "table" then
    return
  end

  local t = tonumber(trig.type) or -1

  if t == midi_input.MSG_TYPE.note_on then
    local note = math.floor(tonumber(trig.val1) or -1)
    if note < 0 or note > 127 then
      return
    end

    local vel = math.floor(tonumber(trig.val2min) or 1)
    vel = math.max(1, math.min(127, vel))

    ignore_next_trigger_event(midi_input.MSG_TYPE.note_on, note, vel, MIDI_CHANNEL + 1)
    reaper.StuffMIDIMessage(MIDI_MODE, STATUS_NOTE_ON, note, vel)
    reaper.defer(function()
      reaper.StuffMIDIMessage(MIDI_MODE, STATUS_NOTE_OFF, note, 0)
    end)
    return
  end

  if t == midi_input.MSG_TYPE.cc then
    local cc = math.floor(tonumber(trig.val1) or -1)
    if cc < 0 or cc > 127 then
      return
    end

    local val = math.floor(tonumber(trig.val2min) or 0)
    val = math.max(0, math.min(127, val))

    ignore_next_trigger_event(midi_input.MSG_TYPE.cc, cc, val, MIDI_CHANNEL + 1)
    reaper.StuffMIDIMessage(MIDI_MODE, STATUS_CC, cc, val)
    return
  end

  if t == midi_input.MSG_TYPE.pc then
    local pc = math.floor(tonumber(trig.val1) or -1)
    if pc < 0 or pc > 127 then
      return
    end

    ignore_next_trigger_event(midi_input.MSG_TYPE.pc, pc, 0, MIDI_CHANNEL + 1)
    reaper.StuffMIDIMessage(MIDI_MODE, STATUS_PC, pc, 0)
  end
end

---Set the active articulation index (1-based). Saves immediately when changed.
---@param index integer 1-based (0 clears selection)
---@param send_trigger boolean|nil When true, sends the articulation's trigger (if enabled in Settings).
function articulations.set_active(index, send_trigger)
  local items = articulations.items or {}
  local n = (type(items) == "table") and #items or 0

  local i = tonumber(index) or 0
  i = math.floor(i)

  if i < 0 then i = 0 end
  if i > 0 and (i < 1 or i > n) then
    return
  end

  if articulations.active_index == i then
    return
  end

  articulations.active_index = i
  articulations.save()

  if send_trigger and settings.send_trigger_on_switch and i > 0 then
    if get_target_track() then
      send_trigger_for_articulation(items[i])
    end
  end
end

---@return Articulation|nil
function articulations.get_active()
  local items = articulations.items or {}
  local sel = articulations.active_index
  if type(sel) ~= "number" or sel < 1 or sel > #items then
    return nil
  end

  local art = items[sel]
  if type(art) ~= "table" then
    return nil
  end

  return art
end

---@return string|nil
function articulations.get_active_name()
  local art = articulations.get_active()
  if not art then
    return nil
  end

  local name = art.name
  if type(name) ~= "string" or name == "" then
    return nil
  end

  return name
end

---Clear all articulations (saves immediately).
function articulations.clear_all()
  articulations.items = {}
  articulations.active_index = 0
  articulations.save()
end

---Replace all articulations with a new list (saves immediately).
---@param items Articulation[]
function articulations.replace_all(items)
  if type(items) ~= "table" then
    items = {}
  end

  articulations.items = items
  articulations.active_index = (#items > 0) and 1 or 0
  articulations.save()
end

---Append multiple articulations to the end of the list (saves immediately).
---@param items Articulation[]
function articulations.append_multiple(items)
  if type(items) ~= "table" then
    return
  end

  local list = articulations.items
  if type(list) ~= "table" then
    return
  end

  local start_n = #list
  for _, art in ipairs(items) do
    if type(art) == "table" then
      list[#list + 1] = art
    end
  end

  if articulations.active_index == 0 and #list > start_n then
    articulations.active_index = start_n + 1
  end
  articulations.save()
end

function articulations.save()
  local track = reaper.GetSelectedTrack(0, 0)
  if not track then
    return
  end

  local payload = { version = 1, items = articulations.items, active_index = articulations.active_index }
  local str = serialize.serialize(payload)
  reaper.GetSetMediaTrackInfo_String(track, TRACK_EXT_KEY, str, true)
end

function articulations.load()
  local track = reaper.GetSelectedTrack(0, 0)
  if track then
    local rv, str = reaper.GetSetMediaTrackInfo_String(track, TRACK_EXT_KEY, "", false)
    if rv and str ~= "" then
      local data = serialize.deserialize(str)
      if type(data) == "table" then
        -- New format: { version = 1, items = {...}, active_index = n }
        if type(data.items) == "table" then
          articulations.items = data.items

          local idx = tonumber(data.active_index) or 0
          idx = math.floor(idx)
          if idx < 0 then idx = 0 end
          if idx > #articulations.items then
            idx = (#articulations.items > 0) and 1 or 0
          end
          articulations.active_index = idx
          return
        end

        -- Legacy format: the saved value is the items array.
        articulations.items = data
        select_first_if_any()
        return
      end
    end
  end

  articulations.items = {}
  articulations.active_index = 0
end

---Checks if the selected track changed and loads articulations once per change.
---@return boolean changed
function articulations.check_track_change()
  local track = reaper.GetSelectedTrack(0, 0)
  if track == last_track then
    return false
  end

  last_track = track

  local guid = track and reaper.GetTrackGUID(track) or nil
  if guid ~= last_track_guid then
    last_track_guid = guid
    articulations.load()
    return true
  end

  return false
end

---Rename an articulation (saves immediately).
---@param index integer 1-based index
---@param name string
function articulations.rename(index, name)
  local items = articulations.items
  if type(items) ~= "table" or type(index) ~= "number" then
    return
  end

  local art = items[index]
  if type(art) ~= "table" then
    return
  end

  art.name = tostring(name or "")
  articulations.save()
end




---Set/clear the optional keyswitch note alias (saves immediately).
---@param index integer 1-based index
---@param note integer|nil MIDI note 0-127 (nil disables)
function articulations.set_keyswitch_note(index, note)
  local items = articulations.items
  if type(items) ~= "table" or type(index) ~= "number" then
    return
  end

  local art = items[index]
  if type(art) ~= "table" then
    return
  end

  local trig = (type(art.trigger) == "table") and art.trigger or nil
  if type(trig) ~= "table" then
    return
  end

  local t = tonumber(trig.type) or -1
  if t ~= midi_input.MSG_TYPE.note_on and t ~= midi_input.MSG_TYPE.cc and t ~= midi_input.MSG_TYPE.pc then
    return
  end

  if note == nil then
    if trig.keyswitch_note == nil then
      return
    end
    trig.keyswitch_note = nil
    articulations.save()
    return
  end

  local n = tonumber(note)
  if type(n) ~= "number" then
    return
  end

  n = math.floor(n)
  if n < 0 then n = 0 end
  if n > 127 then n = 127 end

  if trig.keyswitch_note == n then
    return
  end

  trig.keyswitch_note = n
  articulations.save()
end

--- Set/replace the trigger for an articulation (saves immediately).
---@param index integer 1-based index
---@param trigger ArticulationTrigger|MidiMsgType|nil
function articulations.set_trigger(index, trigger)
  local items = articulations.items
  if type(items) ~= "table" or type(index) ~= "number" then
    return
  end

  local art = items[index]
  if type(art) ~= "table" then
    return
  end

  local cur = (type(art.trigger) == "table") and art.trigger or nil
  local cur_keyswitch = (type(cur) == "table") and cur.keyswitch_note or nil

  local function default_trigger_for_type(t)
    if t == midi_input.MSG_TYPE.note_on then
      return {type = t, val1 = 60, val2min = 1, val2max = 127, keyswitch_note = cur_keyswitch}
    end
    if t == midi_input.MSG_TYPE.cc then
      return {type = t, val1 = 1, val2min = 0, val2max = 127, keyswitch_note = cur_keyswitch}
    end
    if t == midi_input.MSG_TYPE.pc then
      return {type = t, val1 = 1, val2min = -1, val2max = -1, keyswitch_note = cur_keyswitch}
    end
    return {type = -1, val1 = -1, val2min = -1, val2max = -1}
  end

  local function supports_keyswitch_note(t)
    return t == midi_input.MSG_TYPE.note_on or t == midi_input.MSG_TYPE.cc or t == midi_input.MSG_TYPE.pc
  end

  if type(trigger) == "table" then
    local new_trig = trigger
    local t = tonumber(new_trig.type) or -1

    if supports_keyswitch_note(t) then
      -- Preserve keyswitch note by default for triggers that support it.
      if new_trig.keyswitch_note == nil and cur_keyswitch ~= nil then
        new_trig.keyswitch_note = cur_keyswitch
      end
    else
      -- Off: clear any keyswitch field.
      new_trig.keyswitch_note = nil
    end

    art.trigger = new_trig
  elseif type(trigger) == "number" then
    local t = math.floor(trigger)
    if cur and cur.type == t then
      return
    end
    art.trigger = default_trigger_for_type(t)
  else
    art.trigger = default_trigger_for_type(-1)
  end

  articulations.save()
end

---Move an articulation within the list.
---@param from integer 1-based source index
---@param to integer 1-based destination index
function articulations.move(from, to)
  local items = articulations.items
  if type(items) ~= "table" then
    return
  end

  if type(from) ~= "number" or type(to) ~= "number" then
    return
  end

  local n = #items
  if from < 1 or from > n or to < 1 or to > n or from == to then
    return
  end

  local item = table.remove(items, from)
  table.insert(items, to, item)

  -- Keep the active index pointing at the same logical item.
  local sel = articulations.active_index
  if type(sel) == "number" and sel ~= 0 then
    if sel == from then
      articulations.active_index = to
    elseif from < to then
      if sel > from and sel <= to then
        articulations.active_index = sel - 1
      end
    else -- to < from
      if sel >= to and sel < from then
        articulations.active_index = sel + 1
      end
    end
  end

  articulations.save()
end

---Add a new articulation to the end of the list.
function articulations.add()
  local items = articulations.items
  if type(items) ~= "table" then
    return
  end

  local name = (#items == 0) and "Default" or "Unnamed"
  items[#items + 1] = {
    name = name,
    -- type -1 means "no trigger" for now.
    trigger = {type = -1, val1 = -1, val2min = -1, val2max = -1},
    zones = {{
      label = "",
      mode = constants.zone_mode.chromatic,
      color = (settings.default_zone_color or constants.zones.DEFAULT_COLOR),
      start_note = 0,
      end_note = 0
    }}
  }

  articulations.active_index = #items
  articulations.save()
end

---Delete an articulation by index.
---@param index integer 1-based index
function articulations.delete(index)
  local items = articulations.items
  if type(items) ~= "table" then
    return
  end

  if type(index) ~= "number" then
    return
  end

  local n = #items
  if index < 1 or index > n then
    return
  end

  table.remove(items, index)

  local new_n = #items
  if new_n == 0 then
    articulations.active_index = 0
    articulations.save()
    return
  end

  local sel = articulations.active_index
  if type(sel) == "number" and sel ~= 0 then
    if sel == index then
      -- Select the row that shifted into this index, or the last row if we deleted the last.
      articulations.active_index = math.min(index, new_n)
    elseif sel > index then
      articulations.active_index = sel - 1
    end
  end

  articulations.save()
end

local function deep_copy(v)
  if type(v) ~= "table" then
    return v
  end

  local out = {}

  -- Preserve array order.
  local n = #v
  for i = 1, n do
    out[i] = deep_copy(v[i])
  end

  -- Copy remaining keys.
  for k, vv in pairs(v) do
    if not (type(k) == "number" and k >= 1 and k <= n and k % 1 == 0) then
      out[deep_copy(k)] = deep_copy(vv)
    end
  end

  return out
end

---Returns true if there are copied zones available to paste.
---@return boolean
function articulations.has_copied_zones()
  return zones_clipboard ~= nil
end

---Copy the zones from an articulation into the in-memory clipboard.
---@param index integer 1-based index
function articulations.copy_zones(index)
  local items = articulations.items
  if type(items) ~= "table" or type(index) ~= "number" then
    return
  end

  local art = items[index]
  if type(art) ~= "table" then
    return
  end

  local zones = art.zones
  if type(zones) ~= "table" then
    zones_clipboard = {}
    return
  end

  zones_clipboard = deep_copy(zones)
end

---Paste the copied zones onto an articulation (saves immediately).
---@param index integer 1-based index
function articulations.paste_zones(index)
  if zones_clipboard == nil then
    return
  end

  local items = articulations.items
  if type(items) ~= "table" or type(index) ~= "number" then
    return
  end

  local art = items[index]
  if type(art) ~= "table" then
    return
  end

  art.zones = deep_copy(zones_clipboard)
  articulations.save()
end

---Duplicate an articulation by index (inserts the copy after the original).
---@param index integer 1-based index
function articulations.duplicate(index)
  local items = articulations.items
  if type(items) ~= "table" then
    return
  end

  if type(index) ~= "number" then
    return
  end

  local n = #items
  if index < 1 or index > n then
    return
  end

  local src = items[index]
  if type(src) ~= "table" then
    return
  end

  local copy = deep_copy(src)
  local insert_at = index + 1
  table.insert(items, insert_at, copy)
  articulations.active_index = insert_at
  articulations.save()
end


---Add a new zone to an articulation (saves immediately).
---@param index integer 1-based index
function articulations.add_zone(index)
  local items = articulations.items
  if type(items) ~= "table" or type(index) ~= "number" then
    return
  end

  local art = items[index]
  if type(art) ~= "table" then
    return
  end

  if type(art.zones) ~= "table" then
    art.zones = {}
  end

  art.zones[#art.zones + 1] = {
    label = "",
    mode = constants.zone_mode.chromatic,
    color = (settings.default_zone_color or constants.zones.DEFAULT_COLOR),
    start_note = 0,
    end_note = 0
  }

  articulations.save()
end


---Delete a zone by index (saves immediately).
---@param art_index integer 1-based articulation index
---@param zone_index integer 1-based zone index
function articulations.delete_zone(art_index, zone_index)
  local items = articulations.items
  if type(items) ~= "table" or type(art_index) ~= "number" or type(zone_index) ~= "number" then
    return
  end

  local art = items[art_index]
  if type(art) ~= "table" or type(art.zones) ~= "table" then
    return
  end

  if zone_index < 1 or zone_index > #art.zones then
    return
  end

  table.remove(art.zones, zone_index)
  articulations.save()
end

---Duplicate a zone by index (inserts the copy after the original, saves immediately).
---@param art_index integer 1-based articulation index
---@param zone_index integer 1-based zone index
function articulations.duplicate_zone(art_index, zone_index)
  local items = articulations.items
  if type(items) ~= "table" or type(art_index) ~= "number" or type(zone_index) ~= "number" then
    return
  end

  local art = items[art_index]
  if type(art) ~= "table" or type(art.zones) ~= "table" then
    return
  end

  local zones = art.zones
  if zone_index < 1 or zone_index > #zones then
    return
  end

  local src = zones[zone_index]
  if type(src) ~= "table" then
    return
  end

  local copy = deep_copy(src)
  table.insert(zones, zone_index + 1, copy)
  articulations.save()
end

---Move a zone within an articulation (saves immediately).
---@param art_index integer 1-based articulation index
---@param from integer 1-based source index
---@param to integer 1-based destination index
function articulations.move_zone(art_index, from, to)
  local items = articulations.items
  if type(items) ~= "table" then
    return
  end

  if type(art_index) ~= "number" or type(from) ~= "number" or type(to) ~= "number" then
    return
  end

  local art = items[art_index]
  if type(art) ~= "table" or type(art.zones) ~= "table" then
    return
  end

  local zones = art.zones
  local n = #zones
  if from < 1 or from > n or to < 1 or to > n or from == to then
    return
  end

  local item = table.remove(zones, from)
  table.insert(zones, to, item)
  articulations.save()
end


local function event_matches_trigger(ev, trig)
  if type(ev) ~= "table" or type(trig) ~= "table" then
    return false
  end

  local t = trig.type

  if t == midi_input.MSG_TYPE.note_on then
    if ev.msg_type ~= midi_input.MSG_TYPE.note_on then
      return false
    end

    local note = tonumber(trig.val1)
    if type(note) ~= "number" or ev.val1 ~= note then
      return false
    end

    local vel = tonumber(ev.val2) or 0
    if vel <= 0 then
      return false
    end

    local vmin = tonumber(trig.val2min) or 1
    local vmax = tonumber(trig.val2max) or 127
    if vmin > vmax then
      vmin, vmax = vmax, vmin
    end

    return vel >= vmin and vel <= vmax
  end

  if t == midi_input.MSG_TYPE.cc then
    if ev.msg_type ~= midi_input.MSG_TYPE.cc then
      return false
    end

    local cc = tonumber(trig.val1)
    if type(cc) ~= "number" or ev.val1 ~= cc then
      return false
    end

    local val = tonumber(ev.val2) or 0
    local vmin = tonumber(trig.val2min) or 0
    local vmax = tonumber(trig.val2max) or 127
    if vmin > vmax then
      vmin, vmax = vmax, vmin
    end

    return val >= vmin and val <= vmax
  end

  if t == midi_input.MSG_TYPE.pc then
    if ev.msg_type ~= midi_input.MSG_TYPE.pc then
      return false
    end

    local pc = tonumber(trig.val1)
    if type(pc) ~= "number" then
      return false
    end

    return ev.val1 == pc
  end

  return false
end

local function event_matches_keyswitch(ev, trig)
  if type(ev) ~= "table" or type(trig) ~= "table" then
    return false
  end

  local t = trig.type
  if t ~= midi_input.MSG_TYPE.note_on and t ~= midi_input.MSG_TYPE.cc and t ~= midi_input.MSG_TYPE.pc then
    return false
  end

  local ks = tonumber(trig.keyswitch_note)
  if type(ks) ~= "number" then
    return false
  end
  ks = math.floor(ks)
  if ks < 0 or ks > 127 then
    return false
  end

  if ev.msg_type ~= midi_input.MSG_TYPE.note_on then
    return false
  end

  local vel = tonumber(ev.val2) or 0
  if vel <= 0 then
    return false
  end

  return ev.val1 == ks
end

---Applies incoming MIDI events to switch the active articulation.
---
---This is evaluated every frame after midi_input.update(), using only the
---events captured during that update.
function articulations.apply_midi_triggers()
  if midi_input.is_learn_active and midi_input.is_learn_active() then
    return
  end

  local events = midi_input.get_recent_events()
  if type(events) ~= "table" or #events == 0 then
    return
  end

  local items = articulations.items
  if type(items) ~= "table" or #items == 0 then
    return
  end

  local new_active = nil
  local via_keyswitch = false

  -- Process from oldest -> newest so the newest matching event wins.
  for i = #events, 1, -1 do
    local ev = events[i]
    if type(ev) == "table" and not should_ignore_trigger_event(ev) then
      for idx, art in ipairs(items) do
        local trig = (type(art) == "table") and art.trigger or nil
        if event_matches_trigger(ev, trig) then
          new_active = idx
          via_keyswitch = false
          break
        end
        if event_matches_keyswitch(ev, trig) then
          new_active = idx
          via_keyswitch = true
          break
        end
      end
    end
  end

  if type(new_active) == "number" and new_active ~= articulations.active_index then
    articulations.set_active(new_active, via_keyswitch)
  end
end

return articulations


