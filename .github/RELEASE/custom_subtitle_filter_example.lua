--- mpvacious Custom Subtitle Filter Example
--- This script filters bilingual (JP/CN) subtitles to extract only the Japanese lines.
--- Based on Kana detection, as both languages share Kanji.
---
--- To enable this feature:
--- 1. Rename this file to 'subs2srs_subtitle_filter.lua'.
--- 2. Place it in '~/.config/mpv/scripts/subs2srs_subtitle_filter/'.
--- 3. Create a dummy 'main.lua' in the same folder (it can be empty).
--- Note: This file is a custom plugin for mpvacious, not a standalone mpv script.
local M = {}

-- Plugin State
local enabled = true
local get_current_mode = function()
    return nil
end

--- Toggle the filter status via OSD.
local function toggle_filter()
    enabled = not enabled
    local status = enabled and "ON" or "OFF"
    mp.osd_message("Bilingual Filter: " .. status)
    mp.msg.info("Custom subtitle filter set to " .. status)
end

-------------------------------------------------------------------------------
-- UTF-8 Decoding Utilities
-------------------------------------------------------------------------------

--- Decodes a UTF-8 character starting at index i and returns its Unicode codepoint 
--- and the number of bytes consumed.
--- This allows us to work with logical Unicode values instead of raw bytes.
--- @param str string: The input string.
--- @param i number: The current byte index.
--- @return number, number: (codepoint, next_index)
local function get_utf8_codepoint(str, i)
    local b1 = string.byte(str, i)
    if not b1 then
        return nil, i + 1
    end

    -- 1-byte (ASCII): 0xxxxxxx
    if b1 < 0x80 then
        return b1, i + 1
    end

    -- Continuation byte (Invalid as start byte)
    if b1 < 0xC0 then
        return nil, i + 1
    end

    -- 2-byte: 110xxxxx
    if b1 < 0xE0 then
        local b2 = string.byte(str, i + 1)
        if not b2 then
            return nil, i + 1
        end
        -- Formula: (b1 & 0x1F) << 6 | (b2 & 0x3F)
        local cp = (b1 - 0xC0) * 0x40 + (b2 - 0x80)
        return cp, i + 2
    end

    -- 3-byte: 1110xxxx
    if b1 < 0xF0 then
        local b2 = string.byte(str, i + 1)
        local b3 = string.byte(str, i + 2)
        if not b2 or not b3 then
            return nil, i + 1
        end
        -- Formula: (b1 & 0x0F) << 12 | (b2 & 0x3F) << 6 | (b3 & 0x3F)
        local cp = (b1 - 0xE0) * 0x1000 + (b2 - 0x80) * 0x40 + (b3 - 0x80)
        return cp, i + 3
    end

    -- 4-byte: 11110xxx
    if b1 < 0xF8 then
        local b2 = string.byte(str, i + 1)
        local b3 = string.byte(str, i + 2)
        local b4 = string.byte(str, i + 3)
        if not b2 or not b3 or not b4 then
            return nil, i + 1
        end
        local cp = (b1 - 0xF0) * 0x40000 + (b2 - 0x80) * 0x1000 + (b3 - 0x80) * 0x40 + (b4 - 0x80)
        return cp, i + 4
    end

    -- Fallback for invalid sequences
    return nil, i + 1
end

--- Helper to get codepoint of a single character string (e.g., "あ")
--- @param char_str string
--- @return number
local function utf8_to_cp(char_str)
    local cp, _ = get_utf8_codepoint(char_str, 1)
    return cp
end

-------------------------------------------------------------------------------
-- Language Detection (Kana)
-------------------------------------------------------------------------------

--- Checks if a Unicode codepoint falls within the Japanese Kana range.
--- Excludes the Middle Dot (U+30FB) commonly used in Chinese text.
--- @param cp number: The Unicode codepoint.
--- @return boolean
local function is_kana_codepoint(cp)
    if not cp then
        return false
    end

    -- Hiragana Range: U+3041 to U+309F
    local is_hiragana = (cp >= 0x3041 and cp <= 0x309F)

    -- Katakana Range: U+30A0 to U+30FF
    -- We explicitly exclude U+30FB (Katana Middle Dot '・')
    local is_katakana = (cp >= 0x30A0 and cp <= 0x30FF) and (cp ~= 0x30FB)

    return is_hiragana or is_katakana
end

--- Scans a string to see if it contains any Japanese Kana.
--- @param str string
--- @return boolean
local function contains_kana(str)
    if not str then
        return false
    end

    local i = 1
    local len = #str
    while i <= len do
        local cp, next_i = get_utf8_codepoint(str, i)

        if is_kana_codepoint(cp) then
            return true
        end

        i = next_i
    end

    return false
end

-------------------------------------------------------------------------------
-- Processing Logic
-------------------------------------------------------------------------------

--- Extracts Japanese lines from the provided text.
--- If the filter is disabled or no Japanese is detected, it returns the original.
--- @param text string: Raw subtitle text
--- @return string: Filtered text
local function extract_japanese_only(text)
    if not enabled or not text or text == "" then
        return text
    end

    if get_current_mode() ~= "japanese" then
        return text
    end

    local lines = {}
    for line in string.gmatch(text, "[^\r\n]+") do
        table.insert(lines, line)
    end

    if #lines <= 1 then
        return text
    end

    local jp_lines = {}
    for _, line in ipairs(lines) do
        if contains_kana(line) then
            table.insert(jp_lines, line)
        end
    end

    -- If we found specific Japanese lines, return them joined.
    -- Otherwise, return the original text (fallback).
    if #jp_lines > 0 then
        return table.concat(jp_lines, "\n")
    end

    return text
end

-------------------------------------------------------------------------------
-- Exported Functions (Plugin Interface)
-------------------------------------------------------------------------------

--- Main preprocessing function called by mpvacious.
M.preprocess = function(text)
    return extract_japanese_only(text)
end

--- Custom trim function.
--- Overrides the internal mpvacious trimmer if uncommented.
--- The internal trimmer is controlled by `clipboard_trim_enabled=yes` 
--- in your `subs2srs.conf`.
-- M.trim = function(text)
--     -- Example: return text:gsub("^%s*(.-)%s*$", "%1")
--     return text
-- end

--- Initialization function called when the extension is loaded.
M.init = function(config)
    if type(config.get_mode) == "function" then
        get_current_mode = config.get_mode
    end

    -- Keybind to toggle the filter manually
    mp.add_key_binding("alt+m", "toggle_custom_subtitle_filter", toggle_filter)
end

return M
