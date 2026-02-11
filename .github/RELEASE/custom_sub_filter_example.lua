--- mpvacious Custom Subtitle Filter Example
--- This script filters bilingual (JP/CN) subtitles to extract only the Japanese lines.
--- Based on Kana detection, as both languages share Kanji.
---
--- To enable this feature:
--- 1. Rename this file to 'subs2srs_sub_filter.lua'.
--- 2. Place it in '~/.config/mpv/scripts/subs2srs_sub_filter/'.
--- 3. Create a dummy 'main.lua' in the same folder (it can be empty).
--- Note: This file is a custom plugin for mpvacious, not a standalone mpv script.
local M = {}

-- Plugin State
local enabled = true

--- Toggle the filter status via OSD.
local function toggle_filter()
    enabled = not enabled
    local status = enabled and "ON" or "OFF"
    mp.osd_message("Bilingual Filter: " .. status)
    mp.msg.info("Custom sub filter set to " .. status)
end

-------------------------------------------------------------------------------
-- UTF-8 / Language Utilities
-------------------------------------------------------------------------------

--- Checks if a 3-byte sequence represents a Japanese Kana character.
--- @param b1, b2, b3 number: The three bytes of a UTF-8 character.
--- @return boolean
local function is_kana_bytes(b1, b2, b3)
    -- Hiragana: U+3041(ぁ) - U+309F(ゟ) 
    -- (UTF-8: E3 81 81 to E3 82 9F)
    if b1 == 0xE3 and b2 == 0x81 and (b3 >= 0x81 and b3 <= 0xBF) then
        return true
    end
    if b1 == 0xE3 and b2 == 0x82 and (b3 >= 0x80 and b3 <= 0x9F) then
        return true
    end

    -- Katakana: U+30A0(゠) - U+30FF(ヿ)
    -- (UTF-8: E3 82 A0 to E3 83 BF)
    -- Note: U+30FB (E3 82 BB) is '・', which is also used in Chinese.
    -- We split the 0x82 block to exclude 0xBB.
    if b1 == 0xE3 and b2 == 0x82 then
        if (b3 >= 0xA0 and b3 <= 0xBA) or (b3 >= 0xBC and b3 <= 0xBF) then
            return true
        end
    end
    if b1 == 0xE3 and b2 == 0x83 and (b3 >= 0x80 and b3 <= 0xBF) then
        return true
    end

    return false
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
        local b1 = string.byte(str, i)

        -- UTF-8 Prefix Patterns:
        if b1 < 0x80 then
            -- 1-byte (0xxxxxxx): ASCII
            i = i + 1
        elseif b1 < 0xE0 then
            -- 2-byte (110xxxxx): 0xC2 to 0xDF
            i = i + 2
        elseif b1 < 0xF0 then
            -- 3-byte (1110xxxx): 0xE0 to 0xEF
            -- This is where most CJK characters (including Kana) reside.
            if i + 2 <= len then
                local b2 = string.byte(str, i + 1)
                local b3 = string.byte(str, i + 2)
                if is_kana_bytes(b1, b2, b3) then
                    return true
                end
            end
            i = i + 3
        elseif b1 < 0xF8 then
            -- 4-byte (11110xxx): 0xF0 to 0xF7 (Emoji/Rare chars)
            i = i + 4
        else
            -- Invalid UTF-8 start byte or rare 5/6 byte sequences
            i = i + 1
        end
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
M.init = function()
    -- Keybind to toggle the filter manually
    mp.add_key_binding("alt+m", "toggle_custom_sub_filter", toggle_filter)
end

return M
