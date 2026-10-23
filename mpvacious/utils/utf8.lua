-- Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
-- License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

local h = require("helpers")
local unicode_ranges = require("utils.unicode_ranges")
local utf8_constants = require("utils.utf8_constants")
local this = {}

--- Reject overlong encodings, UTF-16 surrogates, and values beyond Unicode's maximum.
local function is_valid_decoded_codepoint(codepoint, minimum)
    h.assert_type(codepoint, "number")
    h.assert_type(minimum, "number")
    return codepoint >= minimum
        and codepoint <= utf8_constants.MAX_CODEPOINT
        and not (codepoint >= utf8_constants.SURROGATE_MIN and codepoint <= utf8_constants.SURROGATE_MAX)
end

--- Decode continuation payloads, returning the numeric codepoint or nil for invalid bytes.
local function decode_utf8_payload(character, codepoint)
    h.assert_type(codepoint, "number")
    for index = 2, #character do
        local byte = character:byte(index)
        if byte < utf8_constants.CONTINUATION_MIN or byte > utf8_constants.CONTINUATION_MAX then
            return nil
        end
        codepoint = codepoint * utf8_constants.CONTINUATION_MULTIPLIER + byte - utf8_constants.CONTINUATION_MIN
    end
    return codepoint
end

--- Return the numeric Unicode codepoint, or nil for an invalid UTF-8 character.
local function utf8_character_codepoint(character)
    local byte_count, first_byte = #character, character:byte(1)
    if byte_count == 1 and first_byte < utf8_constants.ASCII_LIMIT then
        return first_byte
    end
    local rule = utf8_constants.MULTIBYTE_CHARACTER_RULES[byte_count]
    if not rule or first_byte < rule.first_byte_offset or first_byte > rule.max_first_byte then
        return nil
    end
    local codepoint = decode_utf8_payload(character, first_byte - rule.first_byte_offset)
    if codepoint and is_valid_decoded_codepoint(codepoint, rule.min_decoded_codepoint) then
        return codepoint
    end
    return nil
end

--- Check a decoded character against the documented script-letter ranges.
local function codepoint_in_ranges(codepoint, ranges)
    if codepoint == nil then
        return false
    end
    for _, range in ipairs(ranges) do
        if range:contains(codepoint) then
            return true
        end
    end
    return false
end

--- Return whether any character is a letter in the supplied script ranges.
local function contains_script_letters(text, ranges)
    h.assert_type(ranges, "table")
    for _, character in h.utf8_iter(text) do
        if codepoint_in_ranges(utf8_character_codepoint(character), ranges) then
            return true
        end
    end
    return false
end

--- Return whether text contains a Unicode Latin-script letter, including accented forms.
function this.contains_latin_letters(text)
    h.assert_type(text, "string")
    return contains_script_letters(text, unicode_ranges.latin)
end

--- Return whether text contains a Han, Hiragana, Katakana, or Hangul letter.
function this.contains_cjk_letters(text)
    h.assert_type(text, "string")
    return contains_script_letters(text, unicode_ranges.cjk)
end

return this
