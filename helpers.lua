--[[
Copyright: Ren Tatsumoto and contributors
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Various helper functions.
]]

local mp = require('mp')
local msg = require('mp.msg')
local this = {}

this.unpack = unpack and unpack or table.unpack

this.remove_all_spaces = function(str)
    return str:gsub('%s*', '')
end

this.table_get = function(table, key, default)
    if table[key] == nil then
        return default or 'nil'
    else
        return table[key]
    end
end

this.max_num = function(table)
    local max = table[1]
    for _, value in ipairs(table) do
        if value > max then
            max = value
        end
    end
    return max
end

this.contains = function(table, element)
    for _, value in pairs(table) do
        if value == element then
            return true
        end
    end
    return false
end

this.minutes_ago = function(m)
    return (os.time() - 60 * m) * 1000
end

this.is_wayland = function()
    return os.getenv('WAYLAND_DISPLAY') ~= nil
end

this.is_win = function()
    return mp.get_property('options/vo-mmcss-profile') ~= nil
end

this.is_mac = function()
    return mp.get_property('options/macos-force-dedicated-gpu') ~= nil
end

local function map(tab, func)
    local t = {}
    for k, v in pairs(tab) do
        t[k] = func(v)
    end
    return t
end

local function args_as_str(args)
    return table.concat(map(args, function(str) return string.format("'%s'", str) end), " ")
end

this.subprocess = function(args, completion_fn)
    -- if `completion_fn` is passed, the command is ran asynchronously,
    -- and upon completion, `completion_fn` is called to process the results.
    msg.info("Executing: " .. args_as_str(args))
    local command_native = type(completion_fn) == 'function' and mp.command_native_async or mp.command_native
    local command_table = {
        name = "subprocess",
        playback_only = false,
        capture_stdout = true,
        args = args
    }
    return command_native(command_table, completion_fn)
end

this.is_empty = function(var)
    return var == nil or var == '' or (type(var) == 'table' and next(var) == nil)
end

this.contains_non_latin_letters = function(str)
    return str:match("[^%c%p%s%w]")
end

this.capitalize_first_letter = function(string)
    return string:gsub("^%l", string.upper)
end

this.remove_leading_trailing_spaces = function(str)
    return str:gsub('^%s*(.-)%s*$', '%1')
end

this.remove_leading_trailing_dashes = function(str)
    return str:gsub('^[%-_]*(.-)[%-_]*$', '%1')
end

this.remove_text_in_parentheses = function(str)
    -- Remove text like （泣き声） or （ドアの開く音）
    -- No deletion is performed if there's no text after the parentheses.
    -- Note: the modifier `-´ matches zero or more occurrences.
    -- However, instead of matching the longest sequence, it matches the shortest one.
    return str:gsub('(%b())(.)', '%2'):gsub('(（.-）)(.)', '%2')
end

this.remove_newlines = function(str)
    return str:gsub('[\n\r]+', ' ')
end

this.trim = function(str)
    str = this.remove_leading_trailing_spaces(str)
    str = this.remove_text_in_parentheses(str)
    str = this.remove_newlines(str)
    return str
end

this.escape_special_characters = (function()
    local entities = {
        ['&'] = '&amp;',
        ['"'] = '&quot;',
        ["'"] = '&apos;',
        ['<'] = '&lt;',
        ['>'] = '&gt;',
    }
    return function(s)
        return s:gsub('[&"\'<>]', entities)
    end
end)()

this.remove_extension = function(filename)
    return filename:gsub('%.%w+$', '')
end

this.remove_special_characters = function(str)
    return str:gsub('[%c%p%s]', ''):gsub('　', '')
end

this.remove_text_in_brackets = function(str)
    return str:gsub('%b[]', ''):gsub('【.-】', '')
end

this.remove_filename_text_in_parentheses = function(str)
    return str:gsub('%b()', ''):gsub('（.-）', '')
end

this.remove_common_resolutions = function(str)
    -- Also removes empty leftover parentheses and brackets.
    return str:gsub("2160p", ""):gsub("1080p", ""):gsub("720p", ""):gsub("576p", ""):gsub("480p", ""):gsub("%(%)", ""):gsub("%[%]", "")
end

this.human_readable_time = function(seconds)
    if type(seconds) ~= 'number' or seconds < 0 then
        return 'empty'
    end

    local parts = {
        h = math.floor(seconds / 3600),
        m = math.floor(seconds / 60) % 60,
        s = math.floor(seconds % 60),
        ms = math.floor((seconds * 1000) % 1000),
    }

    local ret = string.format("%02dm%02ds%03dms", parts.m, parts.s, parts.ms)

    if parts.h > 0 then
        ret = string.format('%dh%s', parts.h, ret)
    end

    return ret
end

this.get_episode_number = function(filename)
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
        if not this.is_empty(episode_num) then
            return #filename - e, #filename - s, episode_num:reverse()
        end
    end
end

this.notify = function(message, level, duration)
    level = level or 'info'
    duration = duration or 1
    msg[level](message)
    mp.osd_message(message, duration)
end

this.get_active_track = function(track_type)
    -- track_type == audio|sub
    for _, track in pairs(mp.get_property_native('track-list')) do
        if track.type == track_type and track.selected == true then
            return track
        end
    end
    return nil
end

this.has_video_track = function()
    return mp.get_property_native('vid') ~= false
end

this.has_audio_track = function()
    return mp.get_property_native('aid') ~= false
end

this.str_contains = function(s, pattern)
    return not this.is_empty(s) and string.find(string.lower(s), string.lower(pattern)) ~= nil
end

this.filter = function(arr, func)
    local filtered = {}
    for _, elem in ipairs(arr) do
        if func(elem) == true then
            table.insert(filtered, elem)
        end
    end
    return filtered
end

this.get_loaded_tracks = function(track_type)
    --- Return all sub tracks, audio tracks, etc.
    return this.filter(mp.get_property_native('track-list'), function(track) return track.type == track_type end)
end

return this
