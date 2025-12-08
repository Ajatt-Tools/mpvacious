--[[
Copyright: Ren Tatsumoto and contributors
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Various helper functions.
]]

local mp = require('mp')
local msg = require('mp.msg')
local utils = require('mp.utils')
local this = {}

this.unpack = unpack and unpack or table.unpack

this.remove_all_spaces = function(str)
    return str:gsub('%s*', '')
end

this.as_callback = function(fn, ...)
    --- Convenience utility.
    local args = { ... }
    return function()
        return fn(this.unpack(args))
    end
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

this.get_last_n_added_notes = function(note_ids, n)
    table.sort(note_ids)
    return { this.unpack(note_ids, math.max(#note_ids - n + 1, 1), #note_ids) }
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
    local function single_quote(str)
        return string.format("'%s'", str)
    end
    return table.concat(map(args, single_quote), " ")
end

this.subprocess = function(args, completion_fn, override_settings)
    -- if `completion_fn` is passed, the command is ran asynchronously,
    -- and upon completion, `completion_fn` is called to process the results.
    msg.info("Executing: " .. args_as_str(args))
    local command_native = type(completion_fn) == 'function' and mp.command_native_async or mp.command_native
    local command_table = {
        name = "subprocess",
        playback_only = false,
        capture_stdout = true,
        capture_stderr = true,
        args = args
    }
    if not this.is_empty(override_settings) then
        for k, v in pairs(override_settings) do
            command_table[k] = v
        end
    end
    return command_native(command_table, completion_fn)
end

this.subprocess_detached = function(args, completion_fn)
    local overwrite_settings = {
        detach = true,
        capture_stdout = false,
        capture_stderr = false,
    }
    return this.subprocess(args, completion_fn, overwrite_settings)
end

this.is_empty = function(var)
    return var == nil or var == '' or (type(var) == 'table' and next(var) == nil)
end

this.contains_non_latin_letters = function(str)
    return str:match("[^%c%p%s%w—]")
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

this.normalize_spaces = function(str)
    -- replace sequences of ASCII spaces or full-width ideographic spaces with a single ASCII space
    return str:gsub('　+', ' '):gsub('  +', " ")
end

this.trim = function(str)
    str = this.remove_leading_trailing_spaces(str)
    str = this.remove_text_in_parentheses(str)
    str = this.remove_newlines(str)
    str = this.normalize_spaces(str)
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

this.str_contains = function(str, pattern, search_plain)
    --- Return True if 'pattern' can be found in 'str'.
    --- Matching is case-insensitive.
    --- If 'search_plain' is True, turns off the pattern matching facilities.
    return not this.is_empty(str) and string.find(string.lower(str), string.lower(pattern), 1, search_plain) ~= nil
end

this.is_substr = function(str, substr)
    --- Return True if 'substr' is a substring of 'str'.
    --- Matching is case-insensitive.
    --- Plain search is used == turns off the pattern matching facilities.
    return this.str_contains(str, substr, true)
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

this.file_exists = function(filepath)
    if not this.is_empty(filepath) then
        local info = utils.file_info(filepath)
        if info and info.is_file and info.size > 0 then
            return true
        end
    end
    return false
end

this.equal = function(first, last)
    --- Test whether two values are equal
    if type(last) == 'table' then
        return (utils.format_json(first) == utils.format_json(last))
    else
        return (first == last)
    end
end

this.get_loaded_tracks = function(track_type)
    --- Return all sub tracks, audio tracks, etc.
    local function tracks_equal(track)
        return track.type == track_type
    end
    return this.filter(mp.get_property_native('track-list'), tracks_equal)
end

this.assert_equals = function(actual, expected)
    if this.equal(actual, expected) == false then
        mp.commandv("quit")
        error(string.format("TEST FAILED: Expected '%s', got '%s'", expected, actual))
    end
end

this.run_tests = function()
    this.assert_equals(this.is_substr("abcd", "bc"), true)
    this.assert_equals(this.is_substr("abcd", "xyz"), false)
    this.assert_equals(this.is_substr("abcd", "^.*d.*$"), false)
    this.assert_equals(this.str_contains("abcd", "^.*d.*$"), true)
    this.assert_equals(this.str_contains("abcd", "^.*z.*$"), false)

    local ep_num_to_filename = {
        { nil, "A Whisker Away.mkv" },
        { nil, "[Placeholder] Gekijouban SHIROBAKO [Ma10p_1080p][x265_flac]" },
        { "06", "[Placeholder] Sono Bisque Doll wa Koi wo Suru - 06 [54E495D0]" },
        { "02", "(Hi10)_Kobayashi-san_Chi_no_Maid_Dragon_-_02_(BD_1080p)_(Placeholder)_(12C5D2B4)" },
        { "01", "[Placeholder] Koi to Yobu ni wa Kimochi Warui - 01 (1080p) [D517C9F0]" },
        { "01", "[Placeholder] Tsukimonogatari 01 [BD 1080p x264 10-bit FLAC] [5CD88145]" },
        { "01", "[Placeholder] 86 - Eighty Six - 01 (1080p) [1B13598F]" },
        { "00", "[Placeholder] Fate Stay Night - Unlimited Blade Works - 00 (BD 1080p Hi10 FLAC) [95590B7F]" },
        { "01", "House, M.D. S01E01 Pilot - Everybody Lies (1080p x265 Placeholder)" },
        { "165", "A Generic Episode-165" }
    }

    for _, case in pairs(ep_num_to_filename) do
        local expected, filename = this.unpack(case)
        local _, _, episode_num = this.get_episode_number(filename)
        this.assert_equals(episode_num, expected)
    end
end

this.deep_copy = function(obj, seen)
    -- Handle non-tables and previously-seen tables.
    if type(obj) ~= 'table' then
        return obj
    end
    if seen and seen[obj] then
        return seen[obj]
    end

    -- New table; mark it as seen and copy recursively.
    local s = seen or {}
    local res = {}
    s[obj] = res
    for k, v in pairs(obj) do
        res[this.deep_copy(k, s)] = this.deep_copy(v, s)
    end
    return setmetatable(res, getmetatable(obj))
end

this.maybe_require = function(module_name)
    -- ~/.config/mpv/scripts/ and the mpvacious dir
    local parent, child = utils.split_path(mp.get_script_directory())
    -- ~/.config/mpv/ and "scripts"
    parent, child = utils.split_path(parent:gsub("/$", ""))
    -- ~/.config/mpv/subs2srs_sub_filter
    local external_scripts_path = utils.join_path(parent, "subs2srs_sub_filter")

    local search_template = external_scripts_path .. "/?.lua;"
    local module_path = package.searchpath(module_name, search_template)

    if not module_path then
        return nil
    end

    local original_package_path = package.path
    package.path = search_template .. package.path

    local ok, loaded_module = pcall(require, module_name)

    package.path = original_package_path

    if not ok then
        error(string.format("Failed to load module '%s' from '%s'. Error: %s",
        module_name,
        module_path,
        tostring(loaded_module)))
    end

    return loaded_module
end

return this
