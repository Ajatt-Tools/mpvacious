--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Various helper functions.
]]

local mp = require('mp')
local msg = require('mp.msg')
local utils = require('mp.utils')
local this = {}

this.unpack = unpack or table.unpack

local CharWidth = {
    normal = 1,
    wide = 2,
}

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

--- Return value clamped to the [min_value, max_value] range.
function this.clamp(value, min_value, max_value)
    return math.min(math.max(value, min_value), max_value)
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

--- Return true if two array-like tables have the same length and equal elements.
function this.list_equal(first, second)
    if #first ~= #second then
        return false
    end
    for i = 1, #first do
        if first[i] ~= second[i] then
            return false
        end
    end
    return true
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

--- Parameters: args, completion_fn, override_settings, suppress_log
--- if `completion_fn` is passed, the command is ran asynchronously,
--- and upon completion, `completion_fn` is called to process the results.
--- https://github.com/mpv-player/mpv/blob/master/DOCS/man/lua.rst#mp-functions
function this.subprocess(o)
    if not o.suppress_log then
        msg.info("Executing: " .. args_as_str(o.args))
    end
    local command_native = type(o.completion_fn) == 'function' and mp.command_native_async or mp.command_native
    local command_table = {
        name = "subprocess",
        playback_only = false,
        capture_stdout = true,
        capture_stderr = true,
        args = o.args
    }
    if not this.is_empty(o.override_settings) then
        for k, v in pairs(o.override_settings) do
            command_table[k] = v
        end
    end
    return command_native(command_table, o.completion_fn)
end

--- Parameters:, args, completion_fn, suppress_log
function this.subprocess_detached(o)
    o.override_settings = {
        detach = true,
        capture_stdout = false,
        capture_stderr = false,
    }
    return this.subprocess(o)
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

function this.remove_newlines(str, repl_char)
    repl_char = repl_char or ' '
    return str:gsub('[\n\r]+', repl_char)
end

--- Normalize CRLF and CR line endings to LF.
function this.normalize_newlines(str)
    return str:gsub('\r\n', '\n'):gsub('\r', '\n')
end

--- Split text into lines on LF. Input must be LF-normalized (see normalize_newlines).
--- Trailing empty lines are kept: "a\n" splits into {"a", ""}.
function this.split_lines(str)
    local lines = {}
    for line in (str .. '\n'):gmatch('(.-)\n') do
        table.insert(lines, line)
    end
    return lines
end

--- Keep at most max_lines lines, appending "…" to the last kept line if any were dropped.
function this.limit_lines(lines, max_lines)
    if #lines <= max_lines then
        return lines
    end
    local kept = this.itable_slice(lines, 1, max_lines)
    kept[#kept] = kept[#kept] .. "…"
    return kept
end

function this.normalize_spaces(str)
    -- Replace sequences of ASCII spaces or full-width ideographic spaces with a single ASCII space.
    return str:gsub('　+', ' '):gsub('  +', " ")
end

function this.collapse_whitespace(str)
    -- Replace sequences of any whitespace with a single ASCII space.
    return str:gsub('%s+', ' ')
end

function this.trim(str)
    str = this.remove_text_in_parentheses(str)
    str = this.remove_newlines(str)
    str = this.normalize_spaces(str)
    -- Trim after normalization so converted ideographic spaces and spaces left
    -- by parenthetical text removal are removed from the edges too.
    str = this.remove_leading_trailing_spaces(str)
    return str
end

-- Replacement rules for subtitle-text comparison. Each replacement is independent
-- (no key appears in any replacement's output), so unordered iteration via replace_key_value_pairs is safe.
local SUBTITLE_NORMALIZATION_REPLACEMENTS = {
    -- Spaces that should compare equal to a regular space.
    ['　'] = ' ', -- ideographic space
    ['\194\160'] = ' ', -- non-breaking space
    ['\226\128\175'] = ' ', -- narrow non-breaking space
    -- Invisible characters that should not affect comparison.
    ['\226\128\139'] = '', -- zero-width space
    ['\239\187\191'] = '', -- byte-order mark
    -- Quote-like punctuation normalized to a plain double quote.
    ['『'] = '"',
    ['』'] = '"',
    ['「'] = '"',
    ['」'] = '"',
    ['“'] = '"',
    ['”'] = '"',
    ['〝'] = '"',
    ['〟'] = '"',
    ['＂'] = '"',
}

--- Normalize subtitle text for duplicate comparison.
--- Strips HTML tags, maps equivalent spaces to a regular space, removes invisible
--- characters (zero-width space, BOM), maps quote-like punctuation to a plain
--- double quote, then collapses whitespace and trims. Two fields that differ only
--- by these representations compare equal, preventing duplicate sentence content.
function this.normalize_subtitle_text(text)
    text = this.remove_html_tags(text)
    text = this.replace_key_value_pairs(text, SUBTITLE_NORMALIZATION_REPLACEMENTS)
    return this.remove_leading_trailing_spaces(this.collapse_whitespace(text))
end

function this.str_replace(s, old, new, max_repl)
    if this.is_empty(old) then
        return s
    end

    local out = {}
    local search_from = 1
    local replaced_count = 0

    while true do
        -- returns the indices of s where this occurrence starts and ends. nil otherwise
        local occurrence_start, occurrence_end = string.find(s, old, search_from, true) -- plain=true for literal search
        if not occurrence_start then
            table.insert(out, s:sub(search_from))
            break
        end
        -- insert everything until the found occurrence
        table.insert(out, s:sub(search_from, occurrence_start - 1))
        -- insert the found occurrence
        table.insert(out, new)
        -- move the pointer past the found occurrence
        search_from = occurrence_end + 1
        replaced_count = replaced_count + 1
        if max_repl and replaced_count >= max_repl then
            table.insert(out, s:sub(search_from))
            break
        end
    end
    return table.concat(out)
end

function this.replace_key_value_pairs(text, entities)
    if this.is_empty(text) then
        return text
    end
    for entity, replacement in pairs(entities) do
        text = this.str_replace(text, entity, replacement)
    end
    return text
end

this.escape_special_characters = (function()
    local entities = {
        ['&'] = '&amp;',
        ['"'] = '&quot;',
        ["'"] = '&apos;',
        ['<'] = '&lt;',
        ['>'] = '&gt;',
    }
    return function(text)
        -- Unescape first to ensure idempotency. Calling escape on already-escaped text should be a no-op.
        text = this.unescape_special_characters(text)
        -- Use gsub here to avoid double-replacing, resulting in: Expected 'that&apos;s', got 'that&amp;apos;s'
        return text:gsub('[&"\'<>]', entities)
    end
end)()

this.unescape_special_characters = (function()
    local entities = {
        ['&apos;'] = "'",
        ['&#39;'] = "'",
        ['&quot;'] = '"',
        ['&lt;'] = '<',
        ['&gt;'] = '>',
        ['&amp;'] = '&',
    }
    return function(text)
        return this.replace_key_value_pairs(text, entities)
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

function this.remove_html_tags(str)
    return str:gsub('<[^<>]+>', '')
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

--- Return True if 'pattern' can be found in 'str'.
--- Matching is case-insensitive.
--- If 'search_plain' is True, turns off the pattern matching facilities.
function this.str_contains(str, pattern, search_plain)
    return not this.is_empty(str) and string.find(string.lower(str), string.lower(pattern), 1, search_plain) ~= nil
end

--- Return True if 'substr' is a substring of 'str'.
--- Matching is case-insensitive.
--- Plain search is used ==> turns off the pattern matching facilities.
function this.is_substr(str, substr)
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

function this.repr(value)
    if type(value) == 'table' then
        return utils.format_json(value)
    else
        return value
    end
end

function this.equal(first, last)
    --- Test whether two values are equal
    return this.repr(first) == this.repr(last)
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
        error(string.format("TEST FAILED: Expected '%s', got '%s'", this.repr(expected), this.repr(actual)))
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

function this.join_lists(...)
    -- take many lists and output one list.
    local result = {}
    for _, list in ipairs({ ... }) do
        for _, item in ipairs(list) do
            table.insert(result, item)
        end
    end
    return result
end

function this.join_two_sorted_lists(a1, a2)
    -- take two sorted lists and output one sorted list.
    local result = {}
    local idx1, idx2 = 1, 1

    -- Merge elements while both lists have elements
    while idx1 <= #a1 and idx2 <= #a2 do
        if a1[idx1] < a2[idx2] then
            table.insert(result, a1[idx1])
            idx1 = idx1 + 1
        else
            table.insert(result, a2[idx2])
            idx2 = idx2 + 1
        end
    end

    -- Add remaining elements from a1, if any
    while idx1 <= #a1 do
        table.insert(result, a1[idx1])
        idx1 = idx1 + 1
    end

    -- Add remaining elements from a2, if any
    while idx2 <= #a2 do
        table.insert(result, a2[idx2])
        idx2 = idx2 + 1
    end

    return result
end

function this.find_mpv_scripts_dir()
    local this_dir = mp.get_script_directory() -- this_dir points to ~/.config/mpv/scripts/mpvacious (where mpvacious is installed)
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

local function searchpath_lua51_fallback(name, path)
    --- mpv may embed Lua 5.1/LuaJIT, whe-re package.searchpath is unavailable.
    --- This affects common builds such as Homebrew mpv on macOS, which links
    --- against a Lua 5.1-compatible runtime.
    local module_file = name:gsub("%.", "/")

    for template in path:gmatch("[^;]+") do
        local candidate = template:gsub("%?", module_file)
        local file = io.open(candidate, "r")

        if file ~= nil then
            file:close()
            return candidate
        end
    end

    return nil
end

function this.maybe_require(module_name)
    --- Example: ~/.config/mpv/scripts/mpvacious_custom_subtitle_filter/custom_subtitle_filter.lua

    -- Make path to directory ~/.config/mpv/scripts/mpvacious_custom_subtitle_filter
    local external_scripts_path = utils.join_path(this.find_mpv_scripts_dir(), "mpvacious_" .. module_name)
    local search_template = external_scripts_path .. "/?.lua;"
    local searchpath = package.searchpath or searchpath_lua51_fallback
    local module_path = searchpath(module_name, search_template)

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
    return this.str_limit_width(str, n_chars, CharWidth.normal)
end

--- Truncate str so its display width is at most width_budget.
--- CJK characters count as 2 by default; narrower characters count as 1.
--- An ellipsis ("…") is appended after the budget is exhausted when truncating,
--- so the result can exceed width_budget by the ellipsis's width.
function this.str_limit_width(str, width_budget, wide_char_width)
    wide_char_width = wide_char_width or CharWidth.wide
    local ret = {}
    local used_budget = 0
    for _, char in this.utf8_iter(str) do
        local char_width = this.is_cjk_heuristic(char) and wide_char_width or CharWidth.normal
        if used_budget + char_width > width_budget then
            table.insert(ret, "…")
            break
        end
        table.insert(ret, char)
        used_budget = used_budget + char_width
    end
    return table.concat(ret)
end

--- Return true if the UTF-8 character is wider than ASCII in the OSD font (e.g. CJK).
--- A byte length of 3 or 4 means a wide character; everything else is narrow.
function this.is_cjk_heuristic(utf8_chr)
    return #utf8_chr > 2
end

--- Wrap text at whitespace when possible, otherwise at display-width boundaries.
--- Return lines joined by separator.
--- Width is approximate: 1- and 2-byte characters count as 1, wider characters as 2.
--- Input must be LF-normalized. Existing newlines become wrap points.
--- A character wider than n_chars is placed on its own line.
--- Whitespace at a wrap point is consumed.
function this.str_to_lines(str, n_chars)
    local lines = {}
    local current_line = {}
    local current_line_length = 0
    local last_space

    local function flush_line()
        table.insert(lines, table.concat(current_line))
        current_line = {}
        current_line_length = 0
        last_space = nil
    end

    local function calc_char_width(char)
        return this.is_cjk_heuristic(char) and CharWidth.wide or CharWidth.normal
    end

    local function flush_at_space()
        if last_space > 1 then
            table.insert(lines, table.concat(current_line, '', 1, last_space - 1))
        end
        local remainder = {}
        current_line_length = 0
        for index = last_space + 1, #current_line do
            local char = current_line[index]
            table.insert(remainder, char)
            current_line_length = current_line_length + calc_char_width(char)
        end
        current_line = remainder
        last_space = nil
    end

    for _, char in this.utf8_iter(str) do
        if char == '\n' then
            flush_line()
        else
            local char_width = calc_char_width(char)
            if current_line_length > 0 and current_line_length + char_width > n_chars then
                if last_space then
                    flush_at_space()
                end
                if current_line_length > 0 and current_line_length + char_width > n_chars then
                    flush_line()
                end
            end
            table.insert(current_line, char)
            current_line_length = current_line_length + char_width
            if char:match('%s') then
                last_space = #current_line
            end
        end
    end
    flush_line()
    return lines
end

function this.str_wrap(str, n_chars, separator)
    separator = separator or '\n'
    return table.concat(this.str_to_lines(str, n_chars), separator)
end

function this.find_mpvacious_dir()
    -- The fallback path will be valid if the project folder is placed
    -- in mpv's scripts directory (e.g. ~/.config/mpv/scripts).
    -- This does not apply to normal installations of mpvacious.
    -- https://github.com/mpv-player/mpv/blob/master/DOCS/man/lua.rst#mputils-functions
    local default_path = mp.get_script_directory()
    -- test if version file is present
    local info = utils.file_info(utils.join_path(default_path, "version.json"))
    if info and info.is_file then
        return default_path
    end
    return utils.join_path(mp.get_script_directory(), "mpvacious")
end

--- Like pathlib.Path.read_text() but doesn't throw.
--- Returns tuple[text, error].
function this.read_text(file_path)
    local handle = io.open(file_path, 'r')
    if this.is_empty(handle) then
        return nil, "Couldn't open: " .. file_path
    end
    local text = handle:read('*all')
    handle:close()
    if this.is_empty(text) then
        return nil, "Empty file: " .. file_path
    end
    return text, nil
end

--- True if needs update, nil if versions are equal, false if installed version is newer.
function this.version_needs_update(latest_version, installed_version)
    -- Convert version strings to lists of numbers and compare them numerically
    local function version_to_list(version)
        -- Remove leading 'v' if present
        version = version:gsub("^v", "")
        local list = {}
        for num in version:gmatch("%d+") do
            table.insert(list, tonumber(num))
        end
        return list
    end

    local latest_ver_list = version_to_list(latest_version)
    local installed_ver_list = version_to_list(installed_version)

    -- Compare each component
    for i = 1, math.max(#latest_ver_list, #installed_ver_list) do
        local latest_part = latest_ver_list[i] or 0
        local installed_part = installed_ver_list[i] or 0

        if latest_part > installed_part then
            return true -- needs update
        elseif installed_part > latest_part then
            return false -- doesn't need update
        end
    end

    return nil  -- versions are equal
end

--- Return a shallow slice of an integer-indexed table.
--- Negative indexes count backward from the end: -1 is the last item.
--- Bounds outside the table are tolerated and simply produce fewer items.
function this.itable_slice(itable, start_pos, end_pos)
    start_pos = start_pos and start_pos or 1
    end_pos = end_pos and end_pos or #itable

    if end_pos < 0 then
        end_pos = #itable + end_pos + 1
    end
    if start_pos < 0 then
        start_pos = #itable + start_pos + 1
    end

    local new_table = {}
    local first_index = math.max(math.ceil(start_pos), 1)
    local last_index = math.min(math.floor(end_pos), #itable)
    for index = first_index, last_index do
        new_table[#new_table + 1] = itable[index]
    end
    return new_table
end

local function test_islice()
    local slice_cases = {
        { input = { 1, 2, 3 }, expected = { 1, 2, 3 } },
        { input = { 1, 2, 3 }, start_pos = 2, expected = { 2, 3 } },
        { input = { 1, 2, 3 }, start_pos = 2, end_pos = 2, expected = { 2 } },
        { input = { 1, 2, 3 }, start_pos = 2, end_pos = 99, expected = { 2, 3 } },
        { input = { 1, 2, 3 }, start_pos = 99, expected = {} },
        { input = { 1, 2, 3 }, start_pos = 1, end_pos = 0, expected = {} },
        { input = { 1, 2, 3 }, start_pos = -2, expected = { 2, 3 } },
        { input = { 1, 2, 3 }, start_pos = -1, expected = { 3 } },
        { input = { 1, 2, 3 }, start_pos = 1, end_pos = -2, expected = { 1, 2 } },
        { input = { 1, 2, 3 }, start_pos = -3, end_pos = -1, expected = { 1, 2, 3 } },
        { input = { 1, 2, 3 }, start_pos = -99, expected = { 1, 2, 3 } },
        { input = { 1, 2, 3 }, start_pos = 1, end_pos = -99, expected = {} },
        { input = { 1, 2, 3 }, start_pos = 1.5, expected = { 2, 3 } },
        { input = { 1, 2, 3 }, start_pos = 1, end_pos = 2.5, expected = { 1, 2 } },
        { input = { 1, 2, 3 }, start_pos = 1.5, end_pos = 2.5, expected = { 2 } },
    }
    for _, case in ipairs(slice_cases) do
        this.assert_equals(this.itable_slice(case.input, case.start_pos, case.end_pos), case.expected)
    end
end

local function test_list_equal()
    local list_equal_cases = {
        { { 1, 2, 3 }, { 1, 2, 3 }, true }, -- identical lists
        { { 1, 2 }, { 1, 2, 3 }, false }, -- different lengths
        { { 1, 2, 3 }, { 1, 2 }, false }, -- different lengths, other direction
        { { 1, 2, 3 }, { 1, 9, 3 }, false }, -- same length, different element
        { {}, {}, true }, -- both empty
        { { "a", "b" }, { "a", "b" }, true }, -- string elements
        { { "a" }, { "A" }, false }, -- exact (case-sensitive) match
        { { 1, 2 }, { 2, 1 }, false }, -- order matters
    }
    for _, case in ipairs(list_equal_cases) do
        local first, second, expected = this.unpack(case)
        this.assert_equals(this.list_equal(first, second), expected)
    end
end

local function test_normalize_newlines()
    local normalize_newline_cases = {
        { "a\r\nb", "a\nb" },
        { "a\rb", "a\nb" },
        { "a\r\nb\rc", "a\nb\nc" },
        { "a\nb", "a\nb" },
    }
    for _, case in ipairs(normalize_newline_cases) do
        local text, expected = this.unpack(case)
        this.assert_equals(this.normalize_newlines(text), expected)
    end
end

local function test_split_lines()
    local split_line_cases = {
        { "a\nb", { "a", "b" } },
        { "a\n", { "a", "" } },
        { "", { "" } },
        { "\n", { "", "" } },
    }
    for _, case in ipairs(split_line_cases) do
        local text, expected = this.unpack(case)
        this.assert_equals(this.split_lines(text), expected)
    end
end

local function test_limit_lines()
    local limit_lines_cases = {
        -- {lines, max_lines, expected}
        { { "a", "b" }, 3, { "a", "b" } }, -- under the limit: unchanged
        { { "a", "b" }, 2, { "a", "b" } }, -- exactly at the limit: unchanged
        { { "a", "b", "c" }, 2, { "a", "b…" } }, -- over the limit: capped, ellipsis on the last kept line
        { { "a", "b", "c" }, 1, { "a…" } }, -- limit of one line
        { {}, 2, {} }, -- empty input
    }
    for _, case in ipairs(limit_lines_cases) do
        local lines, max_lines, expected = this.unpack(case)
        this.assert_equals(this.limit_lines(lines, max_lines), expected)
    end
end

local function test_str_wrap()
    local str_wrap_cases = {
        { text = "short", n_chars = 25, separator = [[\N]], expected = "short" },
        { text = "abcdef", n_chars = 3, separator = [[\N]], expected = [[abc\Ndef]] },
        { text = "one two three", n_chars = 6, separator = [[\N]], expected = [[one\Ntwo\Nthree]] },
        { text = "like them.", n_chars = 9, separator = [[\N]], expected = [[like\Nthem.]] },
        { text = " abc def", n_chars = 4, separator = [[\N]], expected = [[abc\Ndef]] },
        { text = "ab cdefgh", n_chars = 3, separator = [[\N]], expected = [[ab\Ncde\Nfgh]] },
        { text = "一二三四五六", n_chars = 6, separator = [[\N]], expected = [[一二三\N四五六]] },
        { text = "ab一二cd", n_chars = 6, separator = [[\N]], expected = [[ab一二\Ncd]] },
        { text = "一二\n三四", n_chars = 6, separator = [[\N]], expected = [[一二\N三四]] },
        { text = "Привет", n_chars = 3, separator = [[\N]], expected = [[При\Nвет]] },
        { text = "", n_chars = 6, separator = [[\N]], expected = "" },
        { text = "一", n_chars = 1, separator = [[\N]], expected = "一" },
        { text = "a\n\nb", n_chars = 6, separator = [[\N]], expected = [[a\N\Nb]] },
        { text = "a\n", n_chars = 6, separator = [[\N]], expected = [[a\N]] },
        { text = "\na", n_chars = 6, separator = [[\N]], expected = [[\Na]] },
        { text = "abcdef", n_chars = 3, expected = "abc\ndef" },
    }
    for _, case in ipairs(str_wrap_cases) do
        this.assert_equals(this.str_wrap(case.text, case.n_chars, case.separator), case.expected)
    end
end

local function test_trim()
    local trim_cases = {
        { "  hello  ", "hello" },
        { "　hello　", "hello" },
        { " (note) hello ", "hello" },
        { "a \n b", "a b" },
        { "a  b", "a b" },
    }
    for _, case in ipairs(trim_cases) do
        local text, expected = this.unpack(case)
        this.assert_equals(this.trim(text), expected)
    end
end

local function test_normalize_subtitle_text()
    local normalized_subtitle_text_cases = {
        { "<b>現実味</b>", "現実味" },
        { "a　b", "a b" },
        { "a\194\160b", "a b" },
        { "a\226\128\175b", "a b" },
        { "a\226\128\139b", "ab" },
        { "\239\187\191ab", "ab" },
        { "『お』", '"お"' },
        { "「お」", '"お"' },
        { "“お”", '"お"' },
        { "〝お〟", '"お"' },
        { "＂お＂", '"お"' },
        { "  a\t\nb  ", "a b" },
        { "女の子の <b>女性</b>の　『お』から始まる…", "女の子の 女性の \"お\"から始まる…" },
    }
    for _, case in ipairs(normalized_subtitle_text_cases) do
        local text, expected = this.unpack(case)
        this.assert_equals(this.normalize_subtitle_text(text), expected)
    end
end

function this.run_tests()
    -- Test is_substr
    this.assert_equals(this.is_substr("abcd", "bc"), true)
    this.assert_equals(this.is_substr("abcd", "xyz"), false)
    this.assert_equals(this.is_substr("abcd", "^.*d.*$"), false)

    -- Test str_contains
    this.assert_equals(this.str_contains("abcd", "^.*d.*$"), true)
    this.assert_equals(this.str_contains("abcd", "^.*z.*$"), false)

    -- Test collapse_whitespace
    this.assert_equals(this.collapse_whitespace("a  b"), "a b")
    this.assert_equals(this.collapse_whitespace("a\tb"), "a b")
    this.assert_equals(this.collapse_whitespace("a\nb"), "a b")
    this.assert_equals(this.collapse_whitespace("a\r\nb"), "a b")
    this.assert_equals(this.collapse_whitespace("a \t \n b"), "a b")

    -- Test trim
    test_trim()

    -- Test normalize_subtitle_text
    test_normalize_subtitle_text()

    -- Test unescape_special_characters
    this.assert_equals(this.unescape_special_characters("that&apos;s"), "that's")
    this.assert_equals(this.unescape_special_characters("that&#39;s &amp; &quot;ok&quot;"), "that's & \"ok\"")
    this.assert_equals(this.unescape_special_characters("&lt;tag&gt;"), "<tag>")

    -- Test escape_special_characters
    this.assert_equals(this.escape_special_characters("that's"), "that&apos;s")
    this.assert_equals(this.escape_special_characters("that's & \"ok\""), "that&apos;s &amp; &quot;ok&quot;")
    this.assert_equals(this.escape_special_characters("<tag>"), "&lt;tag&gt;")
    this.assert_equals(this.escape_special_characters('&"\'<>'), "&amp;&quot;&apos;&lt;&gt;")
    this.assert_equals(this.escape_special_characters("a<b&c"), "a&lt;b&amp;c")
    this.assert_equals(this.escape_special_characters("&amp;"), "&amp;")
    this.assert_equals(this.escape_special_characters("hello world"), "hello world")
    this.assert_equals(this.escape_special_characters(""), "")
    -- Round-trip: unescape(escape(text)) should return the original text.
    this.assert_equals(this.unescape_special_characters(this.escape_special_characters("that's & \"ok\"")), "that's & \"ok\"")
    -- Idempotency: escaping an already-escaped string should be a no-op.
    this.assert_equals(this.escape_special_characters(this.escape_special_characters("that's & \"ok\"")), "that&apos;s &amp; &quot;ok&quot;")

    -- Test get_episode_number
    -- Use records instead of a filename → expected map because Lua table entries
    -- with nil values do not exist. Keeping `expected = nil` inside a record lets
    -- us test filenames where no episode number should be found.
    local ep_num_cases = {
        { filename = "A Whisker Away.mkv", expected = nil },
        { filename = "[Placeholder] Gekijouban SHIROBAKO [Ma10p_1080p][x265_flac]", expected = nil },
        { filename = "[Placeholder] Sono Bisque Doll wa Koi wo Suru - 06 [54E495D0]", expected = "06" },
        { filename = "(Hi10)_Kobayashi-san_Chi_no_Maid_Dragon_-_02_(BD_1080p)_(Placeholder)_(12C5D2B4)", expected = "02" },
        { filename = "[Placeholder] Koi to Yobu ni wa Kimochi Warui - 01 (1080p) [D517C9F0]", expected = "01" },
        { filename = "[Placeholder] Tsukimonogatari 01 [BD 1080p x264 10-bit FLAC] [5CD88145]", expected = "01" },
        { filename = "[Placeholder] 86 - Eighty Six - 01 (1080p) [1B13598F]", expected = "01" },
        { filename = "[Placeholder] Fate Stay Night - Unlimited Blade Works - 00 (BD 1080p Hi10 FLAC) [95590B7F]", expected = "00" },
        { filename = "House, M.D. S01E01 Pilot - Everybody Lies (1080p x265 Placeholder)", expected = "01" },
        { filename = "A Generic Episode-165", expected = "165" },
    }

    for _, case in ipairs(ep_num_cases) do
        local _, _, episode_num = this.get_episode_number(case.filename)
        this.assert_equals(episode_num, case.expected)
    end

    this.assert_equals(this.join_lists({ 1, 2 }, { 3 }, {}, { 4, 5 }), { 1, 2, 3, 4, 5 })

    -- Test list_equal
    test_list_equal()

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

    -- Test itable_slice
    test_islice()

    -- GNU only:
    if this.is_gnu() then
        this.assert_equals(this.find_mpv_scripts_dir(), utils.join_path(os.getenv("HOME") or "~", '.config/mpv/scripts'))
        this.assert_equals(this.find_mpv_config_directory(), utils.join_path(os.getenv("HOME") or "~", '.config/mpv'))
    end

    -- Test str limit
    this.assert_equals(this.str_limit("abc", 3), "abc")
    this.assert_equals(this.str_limit("abcd", 3), "abc…")
    this.assert_equals(this.str_limit("報連相", 3), "報連相")
    this.assert_equals(this.str_limit("報連相", 2), "報連…")
    this.assert_equals(this.str_limit("報連相", 1), "報…")
    this.assert_equals(this.str_limit("報連相", 33), "報連相")

    -- Test str_limit_width: CJK counts double, narrower chars count once.
    this.assert_equals(this.str_limit_width("abc", 3), "abc")
    this.assert_equals(this.str_limit_width("abcd", 3), "abc…")
    this.assert_equals(this.str_limit_width("報連相", 3), "報…") -- 2 widths each, exceeds 3
    this.assert_equals(this.str_limit_width("報連", 4), "報連")
    this.assert_equals(this.str_limit_width("ab報", 4), "ab報")
    this.assert_equals(this.str_limit_width("ab報c", 4), "ab報…")
    this.assert_equals(this.str_limit_width("", 3), "")
    this.assert_equals(this.str_limit("報連a", 2), "報連…") -- one narrow char remains after the cut
    this.assert_equals(this.str_limit_width("報連相", 6, 3), "報連…") -- wide_char_width=3: two fit, third exceeds
    this.assert_equals(this.str_limit_width("ЯЯЯЯ", 3), "ЯЯЯ…") -- 2-byte chars count as narrow

    -- Test normalize_newlines
    test_normalize_newlines()

    -- Test split_lines
    test_split_lines()

    -- Test limit_lines
    test_limit_lines()

    -- Test str wrap
    test_str_wrap()

    -- Test clamp
    this.assert_equals(this.clamp(5, 1, 10), 5)
    this.assert_equals(this.clamp(0, 1, 10), 1)
    this.assert_equals(this.clamp(-100, 1, 10), 1)
    this.assert_equals(this.clamp(11, 1, 10), 10)
    this.assert_equals(this.clamp(1, 1, 10), 1)
    this.assert_equals(this.clamp(10, 1, 10), 10)

    -- Test version comparison
    this.assert_equals(this.version_needs_update("v1.0.0", "v1.0.0"), nil)
    this.assert_equals(this.version_needs_update("v1.0.0", "v1.0.1"), false)
    this.assert_equals(this.version_needs_update("v1.0.1", "v1.0.0"), true)
    this.assert_equals(this.version_needs_update("v1.10.0", "v1.9.0"), true)
    this.assert_equals(this.version_needs_update("v2.0.0", "v1.99.99"), true)
    this.assert_equals(this.version_needs_update("v1.0", "v1.0.0"), nil)
    this.assert_equals(this.version_needs_update("v1", "v1.0.0"), nil)
    this.assert_equals(this.version_needs_update("v26.1.30.0", "v26.1.30.1"), false)

    -- Test join_two_sorted_lists
    this.assert_equals(this.join_two_sorted_lists({ 1, 3, 5 }, { 2, 4, 6 }), { 1, 2, 3, 4, 5, 6 })
    this.assert_equals(this.join_two_sorted_lists({ 1, 2, 3 }, { 4, 5, 6 }), { 1, 2, 3, 4, 5, 6 })
    this.assert_equals(this.join_two_sorted_lists({ 4, 5, 6 }, { 1, 2, 3 }), { 1, 2, 3, 4, 5, 6 })
    this.assert_equals(this.join_two_sorted_lists({ 1, 3, 5 }, {}), { 1, 3, 5 })
    this.assert_equals(this.join_two_sorted_lists({}, { 2, 4, 6 }), { 2, 4, 6 })
    this.assert_equals(this.join_two_sorted_lists({}, {}), {})
    this.assert_equals(this.join_two_sorted_lists({ 1 }, { 2 }), { 1, 2 })
    this.assert_equals(this.join_two_sorted_lists({ 1, 1, 2 }, { 1, 3, 3 }), { 1, 1, 1, 2, 3, 3 })

    -- Test this.remove_html_tags(str)
    this.assert_equals(this.remove_html_tags("ヤツらの声に<b>現実味</b>が…"), "ヤツらの声に現実味が…")
    this.assert_equals(this.remove_html_tags("ヤツらの声に<span>現実味</span>が…"), "ヤツらの声に現実味が…")
    this.assert_equals(this.remove_html_tags("<b><b><b><b>"), "")
    this.assert_equals(this.remove_html_tags("<a href=\"test\">test</a>"), "test")

    -- Test str_replace
    this.assert_equals(this.str_replace("a.b.a", ".", "-"), "a-b-a")
    this.assert_equals(this.str_replace("ababab", "ab", "x", 2), "xxab")
    this.assert_equals(this.str_replace("%w%w%w", "%w", "_"), "___")
    this.assert_equals(this.str_replace("abcdef", "%w", "_"), "abcdef")
    this.assert_equals(this.str_replace("メイド喫茶", "メイド", "冥土"), "冥土喫茶")
end

return this
