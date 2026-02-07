--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Various helper functions.
]]

local mp = require('mp')
local msg = require('mp.msg')
local utils = require('mp.utils')
local this = {}

this.unpack = unpack and unpack or table.unpack

function this.noop()
    return
end

function this.remove_all_spaces(str)
    return str:gsub('%s*', '')
end

function this.as_callback(fn, ...)
    --- Convenience utility.
    local args = { ... }
    return function()
        return fn(this.unpack(args))
    end
end

function this.table_get(table, key, default)
    if table[key] == nil then
        return default or 'nil'
    else
        return table[key]
    end
end

function this.max_num(table)
    local max = table[1]
    for _, value in ipairs(table) do
        if value > max then
            max = value
        end
    end
    return max
end

function this.get_last_n_added_notes(note_ids, n)
    table.sort(note_ids)
    return { this.unpack(note_ids, math.max(#note_ids - n + 1, 1), #note_ids) }
end

function this.contains(table, element)
    for _, contained in pairs(table) do
        if element == contained then
            return true
        end
    end
    return false
end

function this.minutes_ago(m)
    return (os.time() - 60 * m) * 1000
end

function this.is_wayland()
    return os.getenv('WAYLAND_DISPLAY') ~= nil
end

function this.is_win()
    return mp.get_property('options/vo-mmcss-profile') ~= nil
end

function this.is_mac()
    return mp.get_property('options/macos-force-dedicated-gpu') ~= nil
end

function this.is_gnu()
    return not this.is_win() and not this.is_mac()
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

function this.subprocess(args, completion_fn, override_settings)
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

function this.subprocess_detached(args, completion_fn)
    local overwrite_settings = {
        detach = true,
        capture_stdout = false,
        capture_stderr = false,
    }
    return this.subprocess(args, completion_fn, overwrite_settings)
end

function this.is_empty(var)
    return var == nil or var == '' or (type(var) == 'table' and next(var) == nil)
end

function this.contains_non_latin_letters(str)
    return str:match("[^%c%p%s%w—]")
end

function this.capitalize_first_letter(string)
    return string:gsub("^%l", string.upper)
end

function this.remove_leading_trailing_spaces(str)
    return str:gsub('^%s*(.-)%s*$', '%1')
end

function this.remove_leading_trailing_dashes(str)
    return str:gsub('^[%-_]*(.-)[%-_]*$', '%1')
end

function this.remove_text_in_parentheses(str)
    -- Remove text like （泣き声） or （ドアの開く音）
    -- No deletion is performed if there's no text after the parentheses.
    -- Note: the modifier `-´ matches zero or more occurrences.
    -- However, instead of matching the longest sequence, it matches the shortest one.
    return str:gsub('(%b())(.)', '%2'):gsub('(（.-）)(.)', '%2')
end

function this.remove_newlines(str)
    return str:gsub('[\n\r]+', ' ')
end

function this.normalize_spaces(str)
    -- replace sequences of ASCII spaces or full-width ideographic spaces with a single ASCII space
    return str:gsub('　+', ' '):gsub('  +', " ")
end

function this.trim(str)
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

function this.remove_extension(filename)
    return filename:gsub('%.%w+$', '')
end

function this.remove_special_characters(str)
    return str:gsub('[%c%p%s]', ''):gsub('　', '')
end

function this.remove_text_in_brackets(str)
    return str:gsub('%b[]', ''):gsub('【.-】', '')
end

function this.remove_filename_text_in_parentheses(str)
    return str:gsub('%b()', ''):gsub('（.-）', '')
end

function this.remove_common_resolutions(str)
    -- Also removes empty leftover parentheses and brackets.
    return str:gsub("2160p", ""):gsub("1080p", ""):gsub("720p", ""):gsub("576p", ""):gsub("480p", ""):gsub("%(%)", ""):gsub("%[%]", "")
end

function this.human_readable_time(seconds)
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

function this.get_episode_number(filename)
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

function this.notify(message, level, duration)
    level = level or 'info'
    duration = duration or 1
    msg[level](message)
    mp.osd_message(message, duration)
end

function this.get_active_track(track_type)
    -- track_type == audio|sub
    for _, track in pairs(mp.get_property_native('track-list')) do
        if track.type == track_type and track.selected == true then
            return track
        end
    end
    return nil
end

function this.has_video_track()
    return mp.get_property_native('vid') ~= false
end

function this.has_audio_track()
    return mp.get_property_native('aid') ~= false
end

function this.str_contains(str, pattern, search_plain)
    --- Return True if 'pattern' can be found in 'str'.
    --- Matching is case-insensitive.
    --- If 'search_plain' is True, turns off the pattern matching facilities.
    return not this.is_empty(str) and string.find(string.lower(str), string.lower(pattern), 1, search_plain) ~= nil
end

function this.is_substr(str, substr)
    --- Return True if 'substr' is a substring of 'str'.
    --- Matching is case-insensitive.
    --- Plain search is used == turns off the pattern matching facilities.
    return this.str_contains(str, substr, true)
end

function this.filter(arr, func)
    local filtered = {}
    for _, elem in ipairs(arr) do
        if func(elem) == true then
            table.insert(filtered, elem)
        end
    end
    return filtered
end

function this.file_exists(filepath)
    if not this.is_empty(filepath) then
        local info = utils.file_info(filepath)
        if info and info.is_file and info.size > 0 then
            return true
        end
    end
    return false
end

function this.equal(first, last)
    --- Test whether two values are equal
    if type(last) == 'table' then
        return (utils.format_json(first) == utils.format_json(last))
    else
        return (first == last)
    end
end

function this.get_loaded_tracks(track_type)
    --- Return all sub tracks, audio tracks, etc.
    local function tracks_equal(track)
        return track.type == track_type
    end
    return this.filter(mp.get_property_native('track-list'), tracks_equal)
end

function this.assert_equals(actual, expected)
    if this.equal(actual, expected) == false then
        error(string.format("TEST FAILED: Expected '%s', got '%s'", expected, actual))
    end
end

function this.deep_copy(obj, seen)
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

function this.shallow_copy(from, to)
    if type(from) ~= 'table' then
        return from
    end
    to = to or {}
    for key, value in pairs(from) do
        to[key] = value
    end
    return to
end

function this.find_mpv_scripts_dir()
    local this_dir = mp.get_script_directory() -- this_dir points to ~/.config/mpv/scripts/subs2srs (where mpvacious is installed)
    local scripts_dir, _ = utils.split_path(this_dir) -- scripts_dir points to  ~/.config/mpv/scripts/
    return scripts_dir:gsub("/$", "")
end

function this.find_mpv_config_directory()
    --- Return the directory where mpv.conf and input.conf are saved.
    local mpv_config_dir, _ = utils.split_path(this.find_mpv_scripts_dir()) -- mpv_config_dir points to ~/.config/mpv/
    return mpv_config_dir:gsub("/$", "")
end

function this.find_mpv_script_opts_directory()
    --- Return the directory where mpv user-scripts store their config files.
    --- Example: ~/.config/mpv/script-opts
    return utils.join_path(this.find_mpv_config_directory(), "script-opts")
end

function this.maybe_require(module_name)
    --- Example: ~/.config/mpv/subs2srs_sub_filter/subs2srs_sub_filter.lua

    -- Make path to directory ~/.config/mpv/subs2srs_sub_filter
    local external_scripts_path = utils.join_path(this.find_mpv_config_directory(), module_name)
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
        this.notify(
                string.format(
                        "Failed to load module '%s' from '%s'. Error: %s",
                        module_name,
                        module_path,
                        tostring(loaded_module)
                ),
                "error",
                5
        )
        return nil
    end

    return loaded_module
end

function this.combine_lists(...)
    -- take many lists and output one list.
    local output = {}
    for _, list in ipairs({ ... }) do
        for _, item in ipairs(list) do
            table.insert(output, item)
        end
    end
    return output
end

function this.find_insertion_point(list, new)
    local low = 1
    local high = #list + 1
    while low < high do
        local mid = math.floor((low + high) / 2)
        if list[mid] > new then
            high = mid
        else
            low = mid + 1
        end
    end
    return low
end

function this.adjacent_items(list, index, before_count, after_count)
    local ret = {}
    local start_idx = index - before_count
    local end_idx = index + after_count
    if start_idx < 1 then
        end_idx = end_idx + math.abs(1 - start_idx)
    end
    if end_idx > #list then
        start_idx = start_idx - math.abs(#list - end_idx)
    end
    for idx = math.max(1, start_idx), math.min(end_idx, #list) do
        table.insert(ret, { idx = idx, item = list[idx] })
    end
    return ret
end

function this.is_lower(s)
    return string.lower(s) == s
end

--- Get byte count of utf-8 character at index i in str
--- https://github.com/tomasklaen/uosc/blob/bc6cf419ba820a80df33960789813dad8e6f34a2/src/uosc/lib/text.lua#L52
function this.utf8_char_bytes(str, i)
    local char_byte = str:byte(i)
    local max_bytes = #str - i + 1
    if char_byte < 0xC0 then
        return math.min(max_bytes, 1)
    elseif char_byte < 0xE0 then
        return math.min(max_bytes, 2)
    elseif char_byte < 0xF0 then
        return math.min(max_bytes, 3)
    elseif char_byte < 0xF8 then
        return math.min(max_bytes, 4)
    else
        return math.min(max_bytes, 1)
    end
end

--- Creates an iterator for an utf-8 encoded string
--- Iterates over utf-8 characters instead of bytes
--- https://github.com/tomasklaen/uosc/blob/bc6cf419ba820a80df33960789813dad8e6f34a2/src/uosc/lib/text.lua#L72
function this.utf8_iter(str)
    local byte_start = 1
    return function()
        local start = byte_start
        if #str < start then
            return nil
        end
        local byte_count = this.utf8_char_bytes(str, start)
        byte_start = start + byte_count
        return start, str:sub(start, start + byte_count - 1)
    end
end

--- Like str[:n_chars] in python, but adds "…" at the end if the string is longer than n_chars.
function this.str_limit(str, n_chars)
    local ret = {}
    local size = 0
    for idx, char in this.utf8_iter(str) do
        table.insert(ret, char)
        size = size + 1
        if size >= n_chars then
            if #str > (idx + #char) then
                table.insert(ret, "…")
            end
            break
        end
    end
    return table.concat(ret)
end

function this.run_tests()
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

    this.assert_equals(this.combine_lists({ 1, 2 }, { 3 }, {}, { 4, 5 }), { 1, 2, 3, 4, 5 })

    local t1 = { 1, 2, 3 }
    local t2 = { 3, 4, 5 }
    this.shallow_copy(t1, t2)
    this.assert_equals(t2, t1)

    local function find_insertion_point_linear(list, new)
        for idx, value in ipairs(list) do
            if new < value then
                return idx
            end
        end
        return #list + 1
    end

    local insertion_cases = {
        { { 1, 2, 4, 5 }, 3, 3 },
        { { 1, 2, 4, 5 }, 99, 5 },
        { { 1, 2, 4, 5 }, 0, 1 },
        { { 1, 2, 4, 5 }, 2, 3 },
        { { 1, 2, 4, 5 }, 5, 5 },
        { {}, 5, 1 },
        { { 2, 2, 2, 2, 2, 2 }, 5, 7 },
    }
    for _, case in ipairs(insertion_cases) do
        local list, new_value, expected = this.unpack(case)
        local r1 = find_insertion_point_linear(list, new_value)
        local r2 = this.find_insertion_point(list, new_value)
        this.assert_equals(r1, r2)
        this.assert_equals(r2, expected)
    end

    local function _items(items)
        local ret = {}
        for _, val in ipairs(items) do
            table.insert(ret, val.item)
        end
        return ret
    end
    this.assert_equals(_items(this.adjacent_items({ 1, 2, 3 }, 2, 1, 1)), { 1, 2, 3 })
    this.assert_equals(_items(this.adjacent_items({ 1, 2, 3 }, 2, 10, 10)), { 1, 2, 3 })
    this.assert_equals(_items(this.adjacent_items({ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 }, 10, 4, 4)), { 2, 3, 4, 5, 6, 7, 8, 9, 10 })
    this.assert_equals(_items(this.adjacent_items({ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 }, 9, 3, 3)), { 4, 5, 6, 7, 8, 9, 10 })
    this.assert_equals(_items(this.adjacent_items({ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 }, 1, 3, 3)), { 1, 2, 3, 4, 5, 6, 7 })

    -- GNU only:
    if this.is_gnu() then
        this.assert_equals(this.find_mpv_scripts_dir(), utils.join_path(os.getenv("HOME") or "~", '.config/mpv/scripts'))
        this.assert_equals(this.find_mpv_config_directory(), utils.join_path(os.getenv("HOME") or "~", '.config/mpv'))
    end

    this.assert_equals(this.str_limit("報連相", 3), "報連相")
    this.assert_equals(this.str_limit("報連相", 2), "報連…")
    this.assert_equals(this.str_limit("報連相", 1), "報…")
    this.assert_equals(this.str_limit("報連相", 33), "報連相")
end

return this
