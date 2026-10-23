-- Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
-- License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

-- UTF-8 byte layouts and Unicode scalar limits from RFC 3629, Section 3.
-- https://www.rfc-editor.org/rfc/rfc3629.html#section-3

-- UTF-8 stores a codepoint as a number in one to four bytes.
-- Within each byte some bits mark its role and the remaining bits carry pieces of the codepoint.
-- In the layouts below, x marks a bit carrying part of the codepoint:
--   One byte:    0xxxxxxx
--   Two bytes:   110xxxxx 10xxxxxx
--   Three bytes: 1110xxxx 10xxxxxx 10xxxxxx
--   Four bytes:  11110xxx 10xxxxxx 10xxxxxx 10xxxxxx
return {
    -- Numbers below 0x80 (128) fit in one byte, including English letters and basic punctuation.
    -- For these ASCII characters, the stored byte is already the Unicode codepoint.
    ASCII_LIMIT = 0x80,

    -- In a multibyte character, every byte after the first is a continuation byte.
    -- A continuation byte must have a value from 0x80 to 0xBF (128 to 191).
    -- Subtract 0x80 to extract the character-data portion, a number from 0 to 63.
    --   A (ASCII) is just 0x41, with no continuation bytes.
    --   é is 0xC3 0xA9, with one continuation byte: 0xA9.
    --   あ is 0xE3 0x81 0x82, with two continuation bytes: 0x81 and 0x82.
    CONTINUATION_MIN = 0x80,
    CONTINUATION_MAX = 0xBF,

    -- Each continuation byte starts with two marker bits, leaving six bits for character data.
    -- Those six bits hold a value from 0 to 63, extracted as next_payload = byte - 0x80.
    -- Multiply the result so far by 64 to make room for those six bits, then add their value:
    -- codepoint = codepoint * 64 + next_payload.
    CONTINUATION_MULTIPLIER = 0x40, -- 64 in hexadecimal.

    -- Exclusive upper bound when utf8_char_bytes() estimates a four-byte character from its first byte.
    -- It recognizes 0xF0 through 0xF7, preserving existing behavior.
    -- Only 0xF0 through 0xF4 can be the first byte of a valid four-byte UTF-8 character.
    -- The decoder rejects the invalid values.
    FOUR_BYTE_FIRST_BYTE_LIMIT = 0xF8,

    MULTIBYTE_CHARACTER_RULES = {
        -- Keys are the total number of bytes encoding one character.
        -- `first_byte_offset` is subtracted from the original first byte to extract its codepoint bits.
        -- `max_first_byte` limits the original first-byte value, before subtracting the offset.
        -- `min_decoded_codepoint` limits the final codepoint after combining ALL the character's bytes.
        -- Reject a decoded number below this minimum because it should have used fewer bytes.
        -- Two-byte sequences require at least 128, three-byte sequences 2048,
        -- and four-byte sequences 65536.
        -- For example, A has codepoint 65 and is stored as the single byte 0x41.
        -- The bytes 0xC1 0x81 would also decode to 65: (0xC1 - 0xC0) * 64 + (0x81 - 0x80).
        -- However, 65 is below the two-byte minimum of 128,
        -- so this unnecessarily long encoding is rejected.

        -- Two bytes start with 110xxxxx. 0xC0 is the offset to subtract, not the lowest valid first byte.
        -- 0xC0/0xC1 produce overlong encodings and are rejected by the minimum-codepoint check.
        [2] = {
            first_byte_offset = 0xC0,
            max_first_byte = 0xDF,
            min_decoded_codepoint = 0x80,
        },

        -- Three bytes start with 1110xxxx and represent codepoints of at least 0x800 (2048).
        [3] = {
            first_byte_offset = 0xE0,
            max_first_byte = 0xEF,
            min_decoded_codepoint = 0x800,
        },

        -- Four bytes start with 11110xxx and represent codepoints of at least 0x10000 (65536).
        -- First bytes above 0xF4 cannot produce a codepoint within Unicode's permitted range.
        [4] = {
            first_byte_offset = 0xF0,
            max_first_byte = 0xF4,
            min_decoded_codepoint = 0x10000,
        },
    },

    -- UTF-16 reserves these numbers for surrogate pairs, which encode larger codepoints.
    -- Surrogates themselves are not standalone characters and must never occur in valid UTF-8.
    SURROGATE_MIN = 0xD800,
    SURROGATE_MAX = 0xDFFF,

    -- Unicode permits no codepoints above this number. Values below it can still be unassigned.
    MAX_CODEPOINT = 0x10FFFF,
}

-- Example: é is stored as the two bytes 0xC3 0xA9.
-- Remove the markers: 0xC3 - 0xC0 = 3, and 0xA9 - 0x80 = 41.
-- Combine the payloads: 3 * 64 + 41 = 233 = 0xE9, the Unicode codepoint U+00E9 for é.
-- Check the original first byte 0xC3 against max_first_byte = 0xDF before subtraction.
-- Check the final codepoint 233 against min_decoded_codepoint = 0x80 (128), not the first portion 3.
