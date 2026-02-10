--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Creates image and audio filenames compatible with Anki.
]]

local mp = require('mp')
local h = require('helpers')

local filename

local anki_compatible_length = (function()
    -- Anki forcibly mutilates all filenames longer than 119 bytes when you run `Tools->Check Media...`.
    local allowed_bytes = 119
    local timestamp_bytes = #'_99h99m99s999ms-99h99m99s999ms.webp'

    return function(str, timestamp)
        -- if timestamp provided, recalculate limit_bytes
        local limit_bytes = allowed_bytes - (timestamp and #timestamp or timestamp_bytes)

        if #str <= limit_bytes then
            return str
        end

        local bytes_per_char = h.contains_non_latin_letters(str) and #'車' or #'z'
        local limit_chars = math.floor(limit_bytes / bytes_per_char)

        if limit_chars == limit_bytes then
            return str:sub(1, limit_bytes)
        end

        return h.str_limit(str, limit_chars)
    end
end)()

local make_media_filename = function()
    filename = mp.get_property("filename") -- filename without path
    filename = h.remove_extension(filename)

    local operations = {
        h.remove_filename_text_in_parentheses,
        h.remove_text_in_brackets,
        h.remove_special_characters
    }
    for _, f in ipairs(operations) do
        local temp_filename = f(filename)
        if temp_filename ~= "" then
            filename = temp_filename
        end
    end
end

local function timestamp_range(start_timestamp, end_timestamp, extension)
    -- Generates a filename suffix of the form: _00h00m00s000ms-99h99m99s999ms.extension
    -- Extension must already contain the dot.
    return string.format(
            '_%s_%s%s',
            h.human_readable_time(start_timestamp),
            h.human_readable_time(end_timestamp),
            extension
    )
end

local function timestamp_static(timestamp, extension)
    -- Generates a filename suffix of the form: _00h00m00s000ms.extension
    -- Extension must already contain the dot.
    return string.format(
            '_%s%s',
            h.human_readable_time(timestamp),
            extension
    )
end

local make_filename = function(...)
    local args = {...}
    local timestamp = #args < 3 and timestamp_static(...) or timestamp_range(...)
    return string.lower(anki_compatible_length(filename, timestamp) .. timestamp)
end

mp.register_event("file-loaded", make_media_filename)

return {
    make_filename = make_filename,
}
