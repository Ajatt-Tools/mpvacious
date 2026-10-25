--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Creates image and audio filenames compatible with Anki.
]]

local mp = require("mp")
local h = require("helpers")

--- Build a still-image suffix from a timestamp and a dotted extension.
local function timestamp_static(timestamp, extension)
    -- Generates a filename suffix of the form: _00h00m00s000ms.extension
    -- Extension must already contain the dot.
    return string.format("_%s%s", h.human_readable_time(timestamp), extension)
end

--- Build a media-range suffix from two timestamps and a dotted extension.
local function timestamp_range(start_timestamp, end_timestamp, extension)
    -- Generates a filename suffix of the form: _00h00m00s000ms_99h99m99s999ms.extension
    -- Extension must already contain the dot.
    return string.format(
        "_%s_%s%s",
        h.human_readable_time(start_timestamp),
        h.human_readable_time(end_timestamp),
        extension
    )
end

--- Create a filename factory with independent cached state. mp_api defaults to mp.
local function make_filename_factory(mp_api)
    mp_api = mp_api or mp
    local self = {}
    local pub = {}

    ------------------------------------------------------------
    --- Private

    -- Cached filename, updated (generated) on file load.
    self.filename = nil
    -- Anki forcibly mutilates all filenames longer than 119 bytes when you run `Tools->Check Media...`.
    self.allowed_bytes = 119
    self.timestamp_bytes = #"_99h99m99s999ms-99h99m99s999ms.webp"

    --- Cache the current basename, keeping the previous value when a cleanup would erase it.
    local function make_media_filename()
        self.filename = mp_api.get_property("filename") -- filename without path
        self.filename = h.remove_extension(self.filename)

        local operations = {
            h.remove_filename_text_in_parentheses,
            h.remove_text_in_brackets,
            h.remove_special_characters,
        }
        for _, f in ipairs(operations) do
            local temp_filename = f(self.filename)
            if temp_filename ~= "" then
                self.filename = temp_filename
            end
        end
    end

    --- Register this instance's file-load callback and return its public methods.
    local function constructor()
        mp_api.register_event("file-loaded", make_media_filename)
        return pub
    end

    ------------------------------------------------------------
    --- Public

    --- Limit a media basename to Anki's byte budget, reserving the supplied or default suffix.
    --- A nil/false suffix uses the default. Raise for invalid types or a suffix exceeding 119 bytes.
    function pub.anki_compatible_length(str, timestamp)
        h.assert_type(str, "string")
        -- The generated suffix includes timestamps and the extension and must fit on its own.
        local limit_bytes = self.allowed_bytes - self.timestamp_bytes
        if timestamp then
            h.assert_type(timestamp, "string")
            limit_bytes = self.allowed_bytes - #timestamp
        end
        if limit_bytes < 0 then
            error(string.format("filename suffix exceeds Anki's %d-byte limit", self.allowed_bytes), 2)
        end

        if #str <= limit_bytes then
            return str
        end

        return h.str_limit_bytes(str, limit_bytes)
    end

    --- Build a lowercase static or range filename using this instance's cached basename.
    --- Requires a file-loaded event first. Raise if the generated suffix exceeds Anki's byte budget.
    function pub.make_filename(...)
        local args = { ... }
        local timestamp
        if #args < 3 then
            timestamp = timestamp_static(...)
        else
            timestamp = timestamp_range(...)
        end
        return string.lower(pub.anki_compatible_length(self.filename, timestamp) .. timestamp)
    end

    return constructor()
end

return {
    new = make_filename_factory,
}
