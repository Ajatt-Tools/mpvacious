--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Standalone test setup for mpvacious.
Provides minimal stubs for the mp.* API so tests can run without mpv.
]]

-- Setup package.path to resolve requires from mpvacious/
package.path = "mpvacious/?.lua;" .. package.path

------------------------------------------------------------
-- Minimal pure-Lua JSON encoder
-- Handles: nil, bool, number, string, arrays, dicts.
-- Keys are sorted alphabetically to match mpv's format_json.
------------------------------------------------------------

local function json_escape_string(s)
    local replacements = {
        ['"'] = '\\"',
        ['\\'] = '\\\\',
        ['\n'] = '\\n',
        ['\r'] = '\\r',
        ['\t'] = '\\t',
    }
    return '"' .. s:gsub('["\\\n\r\t]', replacements) .. '"'
end

local function is_array(t)
    local n = #t
    for k, _ in pairs(t) do
        if type(k) ~= "number" or k < 1 or k > n or k ~= math.floor(k) then
            return false
        end
    end
    return true
end

local function sort_key_by_string_value(first, second)
    return tostring(first) < tostring(second)
end

local function format_json(value)
    local t = type(value)
    if value == nil then
        return "null"
    elseif t == "boolean" then
        return value and "true" or "false"
    elseif t == "number" then
        if value ~= value then
            return "null" -- NaN
        end
        if value == math.huge then
            return "null"
        end
        if value == -math.huge then
            return "null"
        end
        -- Format integers without decimal point
        if value == math.floor(value) and math.abs(value) < 1e15 then
            return string.format("%d", value)
        end
        return tostring(value)
    elseif t == "string" then
        return json_escape_string(value)
    elseif t == "table" then
        if next(value) == nil then
            -- mpv's format_json treats empty tables as empty arrays.
            return "[]"
        end
        if is_array(value) then
            local parts = {}
            for i = 1, #value do
                parts[i] = format_json(value[i])
            end
            return "[" .. table.concat(parts, ",") .. "]"
        else
            -- Sort keys alphabetically for deterministic output.
            local keys = {}
            for k in pairs(value) do
                keys[#keys + 1] = k
            end
            table.sort(keys, sort_key_by_string_value)
            local parts = {}
            for _, k in ipairs(keys) do
                parts[#parts + 1] = json_escape_string(tostring(k)) .. ":" .. format_json(value[k])
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end
    else
        error("format_json: unsupported type: " .. t)
    end
end

------------------------------------------------------------
-- mp.* stubs
------------------------------------------------------------

local function noop()
    return
end

local function return_nil()
    return nil
end

local function return_default(_, default)
    return default
end

local function get_script_directory()
    return (os.getenv("HOME") or "~") .. "/.config/mpv/scripts/mpvacious"
end

local function create_osd_overlay()
    return { update = noop, remove = noop }
end

local function command_native()
    return { status = 0, stdout = "", stderr = "" }
end

local function log_msg(level, ...)
    print(string.format("[%s]", level), ...)
end

local function log_warn(...)
    log_msg("warn", ...)
end

local function log_error(...)
    log_msg("error", ...)
end

local function log_fatal(...)
    log_msg("fatal", ...)
end

local function join_path(first, second)
    if first == "" then
        return second
    end
    if first:sub(-1) == "/" then
        return first .. second
    end
    return first .. "/" .. second
end

local function split_path(path)
    local dir, file = path:match("^(.*/)(.*)")
    if dir then
        return dir, file
    end
    return "", path
end

local mp_stub = {
    get_property = return_nil,
    get_property_number = return_default,
    get_property_native = return_nil,
    set_property = noop,
    set_property_bool = noop,
    set_property_native = noop,
    get_script_directory = get_script_directory,
    register_event = noop,
    observe_property = noop,
    unobserve_property = noop,
    add_key_binding = noop,
    add_forced_key_binding = noop,
    remove_key_binding = noop,
    create_osd_overlay = create_osd_overlay,
    osd_message = noop,
    command_native = command_native,
    command_native_async = noop,
    commandv = noop,
}

local mp_msg_stub = {
    info = noop,
    warn = log_warn,
    error = log_error,
    fatal = log_fatal,
    trace = noop,
    debug = noop,
    verbose = noop,
}

local mp_utils_stub = {
    format_json = format_json,
    parse_json = return_nil,
    join_path = join_path,
    split_path = split_path,
    file_info = return_nil,
}

local mp_options_stub = {
    read_options = noop,
}

-- Register stubs before any mpvacious module is required.
package.loaded['mp'] = mp_stub
package.loaded['mp.msg'] = mp_msg_stub
package.loaded['mp.utils'] = mp_utils_stub
package.loaded['mp.options'] = mp_options_stub
