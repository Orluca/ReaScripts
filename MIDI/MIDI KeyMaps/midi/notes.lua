-- @noindex

local notes = {}

local NOTE_NAMES = {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"}
local NOTE_INDEX = {C = 0, D = 2, E = 4, F = 5, G = 7, A = 9, B = 11}

---@param note number
---@param middle_c_mode number?  -- 4 means MIDI note 60 is C4, otherwise treat it as C3
---@return string
function notes.note_to_name(note, middle_c_mode)
  if type(note) ~= "number" then
    return tostring(note)
  end

  local base = (middle_c_mode == 4) and -1 or -2
  local name = NOTE_NAMES[(note % 12) + 1]
  local octave = math.floor(note / 12) + base
  return name .. tostring(octave)
end

---@param name string
---@param middle_c_mode number?  -- 4 means MIDI note 60 is C4, otherwise treat it as C3
---@return integer|nil note MIDI note 0-127
function notes.name_to_note(name, middle_c_mode)
  if type(name) ~= "string" then
    return nil
  end

  local s = name:match("^%s*(.-)%s*$")
  local letter, accidental, octave_str = s:match("^([A-Ga-g])([#bB]?)(%-?%d+)$")
  if not letter then
    return nil
  end

  local semi = NOTE_INDEX[letter:upper()]
  if not semi then
    return nil
  end

  accidental = accidental or ""
  if accidental == "#" then
    semi = semi + 1
  elseif accidental == "b" or accidental == "B" then
    semi = semi - 1
  end
  semi = semi % 12

  local octave = tonumber(octave_str)
  if not octave then
    return nil
  end

  local base = (middle_c_mode == 4) and -1 or -2
  local note = (octave - base) * 12 + semi
  if note < 0 or note > 127 then
    return nil
  end

  return note
end

return notes
