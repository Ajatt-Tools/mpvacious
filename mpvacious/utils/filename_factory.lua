--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Creates image and audio filenames compatible with Anki.
]]

local mp = require("mp")
local h = require("helpers")

local filename

--- Limit a media basename to Anki's byte budget, reserving the supplied or default suffix.
local anki_compatible_length = (function()
    -- Anki forcibly mutilates all filenames longer than 119 bytes when you run `Tools->Check Media...`.
    local allowed_bytes = 119
    local timestamp_bytes = #"_99h99m99s999ms-99h99m99s999ms.webp"

    return function(str, timestamp)
        -- The generated suffix includes timestamps and the extension and must fit on its own.
        local limit_bytes = allowed_bytes - timestamp_bytes
        if timestamp then
            limit_bytes = allowed_bytes - #timestamp
        end

        if #str <= limit_bytes then
            return str
        end

        return h.str_limit_bytes(str, limit_bytes)
    end
end)()

local make_media_filename = function()
    filename = mp.get_property("filename") -- filename without path
    filename = h.remove_extension(filename)

    local operations = {
        h.remove_filename_text_in_parentheses,
        h.remove_text_in_brackets,
        h.remove_special_characters,
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
        "_%s_%s%s",
        h.human_readable_time(start_timestamp),
        h.human_readable_time(end_timestamp),
        extension
    )
end

local function timestamp_static(timestamp, extension)
    -- Generates a filename suffix of the form: _00h00m00s000ms.extension
    -- Extension must already contain the dot.
    return string.format("_%s%s", h.human_readable_time(timestamp), extension)
end

local make_filename = function(...)
    local args = { ... }
    local timestamp = #args < 3 and timestamp_static(...) or timestamp_range(...)
    return string.lower(anki_compatible_length(filename, timestamp) .. timestamp)
end

mp.register_event("file-loaded", make_media_filename)

return {
    make_filename = make_filename,
    anki_compatible_length = anki_compatible_length,
}
