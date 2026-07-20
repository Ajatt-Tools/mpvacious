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

local format_json

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

format_json = function(value)
    local t = type(value)
    if value == nil then
        return "null"
    elseif t == "boolean" then
        return value and "true" or "false"
    elseif t == "number" then
        if value ~= value then return "null" end -- NaN
        if value == math.huge then return "null" end
        if value == -math.huge then return "null" end
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
            table.sort(keys, function(a, b)
                return tostring(a) < tostring(b)
            end)
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

local mp_stub = {
    get_property = function() return nil end,
    get_property_number = function(_, def) return def end,
    get_property_native = function() return nil end,
    set_property = function() end,
    set_property_bool = function() end,
    set_property_native = function() end,
    get_script_directory = function()
        return (os.getenv("HOME") or "~") .. "/.config/mpv/scripts/mpvacious"
    end,
    register_event = function() end,
    observe_property = function() end,
    unobserve_property = function() end,
    add_key_binding = function() end,
    add_forced_key_binding = function() end,
    remove_key_binding = function() end,
    create_osd_overlay = function()
        return { update = function() end, remove = function() end }
    end,
    osd_message = function() end,
    command_native = function() return { status = 0, stdout = "", stderr = "" } end,
    command_native_async = function() end,
    commandv = function() end,
}

local mp_msg_stub = {
    info = function() end,
    warn = function(...) print("[warn]", ...) end,
    error = function(...) print("[error]", ...) end,
    fatal = function(...) print("[fatal]", ...) end,
    trace = function() end,
    debug = function() end,
    verbose = function() end,
}

local mp_utils_stub = {
    format_json = format_json,
    parse_json = function() return nil end,
    join_path = function(a, b)
        if a == "" then return b end
        if a:sub(-1) == "/" then return a .. b end
        return a .. "/" .. b
    end,
    split_path = function(path)
        local dir, file = path:match("^(.*/)(.*)")
        if dir then return dir, file end
        return "", path
    end,
    file_info = function() return nil end,
}

local mp_options_stub = {
    read_options = function() end,
}

-- Register stubs before any mpvacious module is required.
package.loaded['mp'] = mp_stub
package.loaded['mp.msg'] = mp_msg_stub
package.loaded['mp.utils'] = mp_utils_stub
package.loaded['mp.options'] = mp_options_stub
