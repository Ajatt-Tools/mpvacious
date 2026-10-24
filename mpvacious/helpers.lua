--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Various helper functions.
]]

local mp = require("mp")
local msg = require("mp.msg")
local utils = require("mp.utils")
local this = {}

this.unpack = unpack or table.unpack

local CharWidth = {
    normal = 1,
    wide = 2,
}

function this.noop()
    return nil
end

function this.remove_all_spaces(str)
    return str:gsub("%s*", "")
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
        return default or "nil"
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
    return os.getenv("WAYLAND_DISPLAY") ~= nil
end

function this.is_win()
    return mp.get_property("options/vo-mmcss-profile") ~= nil
end

function this.is_mac()
    return mp.get_property("options/macos-force-dedicated-gpu") ~= nil
end

function this.is_gnu()
    return not this.is_win() and not this.is_mac()
end

--- Return transformed values at their original keys without changing the input table.
--- Nil results omit their corresponding keys rather than compacting the table.
function this.map(tab, func)
    local t = {}
    for k, v in pairs(tab) do
        t[k] = func(v)
    end
    return t
end

--- Fold an array in index order by calling reducer(accumulator, value) for each entry.
--- Default initial to zero when omitted or nil. Like ipairs, stop at the first missing index.
function this.reduce(values, reducer, initial)
    if initial == nil then initial = 0 end
    local accumulator = initial
    for _, value in ipairs(values) do
        accumulator = reducer(accumulator, value)
    end
    return accumulator
end

local function args_as_str(args)
    local function single_quote(str)
        return string.format("'%s'", str)
    end
    return table.concat(this.map(args, single_quote), " ")
end

--- Parameters: args, completion_fn, override_settings, suppress_log
--- if `completion_fn` is passed, the command is ran asynchronously,
--- and upon completion, `completion_fn` is called to process the results.
--- https://github.com/mpv-player/mpv/blob/master/DOCS/man/lua.rst#mp-functions
function this.subprocess(o)
    if not o.suppress_log then
        msg.info("Executing: " .. args_as_str(o.args))
    end
    local command_native = type(o.completion_fn) == "function" and mp.command_native_async or mp.command_native
    local command_table = {
        name = "subprocess",
        playback_only = false,
        capture_stdout = true,
        capture_stderr = true,
        args = o.args,
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
    return var == nil or var == "" or (type(var) == "table" and next(var) == nil)
end

--- Return whether a value is a string containing at least one character.
function this.is_non_empty_str(value)
    return type(value) == "string" and value ~= ""
end

function this.contains_non_latin_letters(str)
    return str:match("[^%c%p%s%w—]")
end

function this.capitalize_first_letter(string)
    return string:gsub("^%l", string.upper)
end

function this.remove_leading_trailing_spaces(str)
    return str:gsub("^%s*(.-)%s*$", "%1")
end

function this.remove_leading_trailing_dashes(str)
    return str:gsub("^[%-_]*(.-)[%-_]*$", "%1")
end

function this.remove_text_in_parentheses(str)
    -- Remove text like （泣き声） or （ドアの開く音）
    -- No deletion is performed if there's no text after the parentheses.
    -- Note: the modifier `-´ matches zero or more occurrences.
    -- However, instead of matching the longest sequence, it matches the shortest one.
    return str:gsub("(%b())(.)", "%2"):gsub("(（.-）)(.)", "%2")
end

function this.remove_newlines(str, repl_char)
    repl_char = repl_char or " "
    return str:gsub("[\n\r]+", repl_char)
end

--- Normalize CRLF and CR line endings to LF.
function this.normalize_newlines(str)
    return str:gsub("\r\n", "\n"):gsub("\r", "\n")
end

--- Split text into lines on LF. Input must be LF-normalized (see normalize_newlines).
--- Trailing empty lines are kept: "a\n" splits into {"a", ""}.
function this.split_lines(str)
    local lines = {}
    for line in (str .. "\n"):gmatch("(.-)\n") do
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
    return str:gsub("　+", " "):gsub("  +", " ")
end

function this.collapse_whitespace(str)
    -- Replace sequences of any whitespace with a single ASCII space.
    return str:gsub("%s+", " ")
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
    ["　"] = " ", -- ideographic space
    ["\194\160"] = " ", -- non-breaking space
    ["\226\128\175"] = " ", -- narrow non-breaking space
    -- Invisible characters that should not affect comparison.
    ["\226\128\139"] = "", -- zero-width space
    ["\239\187\191"] = "", -- byte-order mark
    -- Quote-like punctuation normalized to a plain double quote.
    ["『"] = '"',
    ["』"] = '"',
    ["「"] = '"',
    ["」"] = '"',
    ["“"] = '"',
    ["”"] = '"',
    ["〝"] = '"',
    ["〟"] = '"',
    ["＂"] = '"',
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

--- Lowercase HTML text and normalize spacing while preserving escaped literal content.
function this.normalize_html_text(text)
    text = (text or ""):lower()
    text = this.str_replace(text, "&nbsp;", " ")
    -- Removing line-break tags directly would join otherwise separate words.
    text = text:gsub("<br%s*/?>", " ")
    -- Strip actual markup before decoding entities so escaped tags remain literal text.
    text = this.normalize_subtitle_text(text)
    return this.unescape_special_characters(text)
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
        ["&"] = "&amp;",
        ['"'] = "&quot;",
        ["'"] = "&apos;",
        ["<"] = "&lt;",
        [">"] = "&gt;",
    }
    return function(text)
        -- Unescape first to ensure idempotency. Calling escape on already-escaped text should be a no-op.
        text = this.unescape_special_characters(text)
        -- Use gsub here to avoid double-replacing, resulting in: Expected 'that&apos;s', got 'that&amp;apos;s'
        -- Assign before returning to discard gsub's replacement count and return only the string.
        text = text:gsub("[&\"'<>]", entities)
        return text
    end
end)()

this.unescape_special_characters = (function()
    local entities = {
        ["&apos;"] = "'",
        ["&#39;"] = "'",
        ["&quot;"] = '"',
        ["&lt;"] = "<",
        ["&gt;"] = ">",
        ["&amp;"] = "&",
    }
    return function(text)
        -- Assign before returning to discard gsub's replacement count and return only the string.
        text = text:gsub("&[#%w]+;", entities)
        return text
    end
end)()

function this.remove_extension(filename)
    return filename:gsub("%.%w+$", "")
end

function this.remove_special_characters(str)
    return str:gsub("[%c%p%s]", ""):gsub("　", "")
end

function this.remove_text_in_brackets(str)
    return str:gsub("%b[]", ""):gsub("【.-】", "")
end

function this.remove_filename_text_in_parentheses(str)
    return str:gsub("%b()", ""):gsub("（.-）", "")
end

function this.remove_html_tags(str)
    return str:gsub("<[^<>]+>", "")
end

function this.remove_common_resolutions(str)
    -- Also removes empty leftover parentheses and brackets.
    return str:gsub("2160p", "")
        :gsub("1080p", "")
        :gsub("720p", "")
        :gsub("576p", "")
        :gsub("480p", "")
        :gsub("%(%)", "")
        :gsub("%[%]", "")
end

function this.human_readable_time(seconds)
    if type(seconds) ~= "number" or seconds < 0 then
        return "empty"
    end

    local parts = {
        h = math.floor(seconds / 3600),
        m = math.floor(seconds / 60) % 60,
        s = math.floor(seconds % 60),
        ms = math.floor((seconds * 1000) % 1000),
    }

    local ret = string.format("%02dm%02ds%03dms", parts.m, parts.s, parts.ms)

    if parts.h > 0 then
        ret = string.format("%dh%s", parts.h, ret)
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

--- Log and display a nonempty string, ignoring missing or non-string messages.
function this.notify(message, level, duration)
    if not this.is_non_empty_str(message) then
        return
    end
    level = level or "info"
    this.assert_in(level, { "fatal", "error", "warn", "info", "v", "debug", "trace" })
    duration = duration or 1
    msg[level](message)
    mp.osd_message(message, duration)
end

--- Return the selected audio, subtitle, or video track, if track metadata is available.
function this.get_active_track(track_type, mp_api)
    this.assert_in(track_type, { "audio", "sub", "video" })
    -- Allow isolated metadata reads without modifying the shared mp API.
    mp_api = mp_api or mp
    for _, track in pairs(mp_api.get_property_native("track-list") or {}) do
        if track.type == track_type and track.selected == true then
            return track
        end
    end
    return nil
end

function this.has_video_track()
    return mp.get_property_native("vid") ~= false
end

function this.has_audio_track()
    return mp.get_property_native("aid") ~= false
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
    if type(value) == "table" then
        return utils.format_json(value)
    else
        return value
    end
end

--- Compare test values structurally, independent of JSON object-key order.
local function are_two_values_equal(first, last, seen)
    if type(first) ~= type(last) then
        return false
    end
    if type(first) ~= "table" then
        return first == last
    end
    seen = seen or {}
    seen[first] = seen[first] or {}
    if seen[first][last] then
        return true
    end
    seen[first][last] = true
    for key, value in pairs(first) do
        if last[key] == nil or not are_two_values_equal(value, last[key], seen) then
            return false
        end
    end
    for key in pairs(last) do
        if first[key] == nil then
            return false
        end
    end
    return true
end

--- Test whether two scalar or table values are equal.
function this.equal(first, last)
    return are_two_values_equal(first, last)
end

function this.get_loaded_tracks(track_type)
    this.assert_in(track_type, { "audio", "sub", "video" })
    --- Return all sub tracks, audio tracks, etc.
    local function tracks_equal(track)
        return track.type == track_type
    end
    return this.filter(mp.get_property_native("track-list"), tracks_equal)
end

function this.assert_equals(actual, expected)
    if this.equal(actual, expected) == false then
        error(string.format("TEST FAILED: Expected '%s', got '%s'", this.repr(expected), this.repr(actual)))
    end
end

--- Raise an error at the caller when value is not among the allowed values.
function this.assert_in(value, allowed_values)
    if not this.contains(allowed_values, value) then
        error(string.format("Expected one of %s, got %s", this.repr(allowed_values), this.repr(value)), 2)
    end
end

function this.deep_copy(obj, seen)
    -- Handle non-tables and previously-seen tables.
    if type(obj) ~= "table" then
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
    if type(from) ~= "table" then
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
            table.insert(lines, table.concat(current_line, "", 1, last_space - 1))
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
        if char == "\n" then
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
            if char:match("%s") then
                last_space = #current_line
            end
        end
    end
    flush_line()
    return lines
end

function this.str_wrap(str, n_chars, separator)
    separator = separator or "\n"
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
    local handle = io.open(file_path, "r")
    if this.is_empty(handle) then
        return nil, "Couldn't open: " .. file_path
    end
    local text = handle:read("*all")
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

    return nil -- versions are equal
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

return this
