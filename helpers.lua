local mp = require('mp')
local msg = require('mp.msg')

local unpack = unpack and unpack or table.unpack

local function is_empty(var)
  return var == nil or var == '' or (type(var) == 'table' and next(var) == nil)
end

local function get_episode_number(filename)
  -- Reverses the filename to start the search from the end as the media title might contain similar numbers.
  local filename_reversed = filename:reverse()

  local ep_num_patterns = {
      "[%s_](%d?%d?%d)[pP]?[eE]", -- Starting with E or EP (case-insensitive). "Example Series S01E01 [94Z295D1]"
      "^(%d?%d?%d)[pP]?[eE]", -- Starting with E or EP (case-insensitive) at the end of filename. "Example Series S01E01"
      "%)(%d?%d?%d)%(", -- Surrounded by parentheses. "Example Series (12)"
      "%](%d?%d?%d)%[", -- Surrounded by brackets. "Example Series [01]"
      "%s(%d?%d?%d)%s", -- Surrounded by whitespace. "Example Series 124 [1080p 10-bit]"
      "_(%d?%d?%d)_", -- Surrounded by underscores. "Example_Series_04_1080p"
      "^(%d?%d?%d)[%s_]", -- Ending to the episode number. "Example Series 124"
      "(%d?%d?%d)%-edosipE", -- Prepended by "Episode-". "Example Episode-165"
  }

  local s, e, episode_num
  for _, pattern in pairs(ep_num_patterns) do
      s, e, episode_num = string.find(filename_reversed, pattern)
      if not is_empty(episode_num) then
          return #filename - e, #filename - s, episode_num:reverse()
      end
  end
end

local function notify(message, level, duration)
    level = level or 'info'
    duration = duration or 1
    msg[level](message)
    mp.osd_message(message, duration)
end

return {
  is_empty = is_empty,
  get_episode_number = get_episode_number,
  notify = notify,
  unpack = unpack,
}
