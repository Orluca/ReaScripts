-- @noindex

local constants = {
  keyboard = {
    WHITE_FILL = 0xFFFFFFFF,
    BLACK_FILL = 0x202020FF,
    BORDER = 0x000000FF,
    C_LABEL = 0x000000CC,
    TRIGGER_NOTE_COLOR = 0xFF6B6BFF
  },
  ui = {
    BUTTON_ROUNDING = 2,
    MAIN_WINDOW_BG = 0x101010FF
  },
  zones = {
    DEFAULT_COLOR = 0x5CC8FFFF,
    COLOR_STRENGTH_DEFAULT = 70,
    COLOR_PRESETS = {
      -- Reds (light -> dark)
      0xFF9A9AFF, 0xFF6B6BFF, 0xFF4B4BFF, 0xCC2F2FFF, 0x991F1FFF,

      -- Oranges (light -> dark)
      0xFFC58AFF, 0xFFA64BFF, 0xFF8C1AFF, 0xCC6F14FF, 0x99520EFF,

      -- Yellows (light -> dark)
      0xFFF59AFF, 0xFFE95CFF, 0xFFD500FF, 0xCCAA00FF, 0x997F00FF,

      -- Olive / Moss (light -> dark)
      0xD6E6B3FF, 0xBFD98CFF, 0xA6CC66FF, 0x80994DFF, 0x5A6633FF,

      -- Greens (light -> dark)
      0xA6F4B6FF, 0x66E087FF, 0x33CC66FF, 0x26994DFF, 0x1A6633FF,

      -- Teal-Blue Hybrid (light -> dark)
      0xA6E6E6FF, 0x66CCCCFF, 0x33B2B2FF, 0x268C8CFF, 0x1A6666FF,

      -- Ice / Frost Blue (light -> dark)
      0xE6F7FFFF, 0xCCEFFFFF, 0x99E0FFFF, 0x66CCFFFF, 0x3399CCFF,

      -- Cyans / Blues (light -> dark)
      0x9AE6FFFF, 0x5CC8FFFF, 0x33AADDFF, 0x267FBBFF, 0x1A5A88FF,

      -- Purples (light -> dark)
      0xD6A6FFFF, 0xB366FFFF, 0x914DCCFF, 0x6A3699FF, 0x4A2466FF,

      -- Pink (light -> dark)
      0xFFB3DAFF, 0xFF80C8FF, 0xFF4DB5FF, 0xCC3399FF, 0x991F73FF,

      -- Warm Browns (light -> dark)
      0xD9B38CFF, 0xBF8C5FFF, 0xA66A3FFF, 0x804D2AFF, 0x59331AFF,

      -- Charcoal / Utility Dark (light -> dark)
      0x666666FF, 0x4D4D4DFF, 0x404040FF, 0x2B2B2BFF, 0x1A1A1AFF,
    }
  },
  zone_mode = {chromatic = 1, white = 2, black = 3}
}

return constants
