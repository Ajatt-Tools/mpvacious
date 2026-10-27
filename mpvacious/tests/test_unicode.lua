-- Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
-- License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

local h = require("helpers")
local utf8 = require("utils.utf8")
local Range = require("utils.range")
local unicode_ranges = require("utils.unicode_ranges")

local RANGE_GROUP_TEST_CASES = {
    {
        script = "latin",
        count = 36,
        groups = {
            { from = 0x0041, to = 0x007A, count = 2 },
            { from = 0x00AA, to = 0x00F6, count = 4 },
            { from = 0x00F8, to = 0x02E4, count = 2 },
            { from = 0x1D00, to = 0x1DBE, count = 5 },
            { from = 0x1E00, to = 0x1EFF, count = 1 },
            { from = 0x2071, to = 0x2184, count = 7 },
            { from = 0x2C60, to = 0x2C7F, count = 1 },
            { from = 0xA722, to = 0xA7FF, count = 3 },
            { from = 0xAB30, to = 0xAB69, count = 3 },
            { from = 0xFB00, to = 0xFF5A, count = 3 },
            { from = 0x10780, to = 0x1DF2A, count = 5 },
        },
    },
    {
        script = "cjk",
        count = 44,
        groups = {
            { from = 0x1100, to = 0xD7FB, count = 6 },
            { from = 0xFFA0, to = 0xFFDC, count = 5 },
            { from = 0x3041, to = 0x1B152, count = 5 },
            { from = 0x30A1, to = 0xFF9D, count = 5 },
            { from = 0x1AFF0, to = 0x1B167, count = 7 },
            { from = 0x3005, to = 0xFAD9, count = 6 },
            { from = 0x16FE3, to = 0x33479, count = 10 },
        },
    },
}

--- Retain every private group's range count, boundary positions, and original concatenation order.
local function test_range_group_assembly()
    for _, case in ipairs(RANGE_GROUP_TEST_CASES) do
        local ranges = unicode_ranges[case.script]
        h.assert_equals(#ranges, case.count)
        local next_index = 1
        for _, group in ipairs(case.groups) do
            h.assert_equals(ranges[next_index].from, group.from)
            next_index = next_index + group.count
            h.assert_equals(ranges[next_index - 1].to, group.to)
        end
        h.assert_equals(next_index - 1, case.count)
    end
end

local SCRIPT_TEST_CASES = {
    { text = "", latin = false, cjk = false },
    { text = "AZ az", latin = true, cjk = false },
    { text = "@ [ ` {", latin = false, cjk = false },
    { text = "ª º", latin = true, cjk = false },
    { text = "À Ö Ø ö ø ÿ", latin = true, cjk = false },
    { text = "× ÷", latin = false, cjk = false },
    { text = "č č", latin = true, cjk = false },
    { text = "ɐ ʸ", latin = true, cjk = false },
    { text = "ắ ắ", latin = true, cjk = false },
    { text = "é", latin = true, cjk = false },
    { text = "́", latin = false, cjk = false }, -- A combining accent alone is not a letter.
    { text = "ꭥ", latin = false, cjk = false }, -- U+AB65 is Greek.
    { text = "꜠ ꜡", latin = false, cjk = false }, -- U+A720/21 are tone symbols, not Latin letters.
    { text = "ﬀ Ａ ｚ", latin = true, cjk = false },
    { text = "𐞀", latin = true, cjk = false }, -- U+10780, Latin Extended-F.
    { text = "𝼀", latin = true, cjk = false }, -- U+1DF00, Latin Extended-G.
    { text = "日本語", latin = false, cjk = true },
    { text = "ひらがな", latin = false, cjk = true },
    { text = "カタカナ ｶﾅ", latin = false, cjk = true },
    { text = "한국어 ᄀ ㄱ", latin = false, cjk = true },
    { text = "𠀀", latin = false, cjk = true }, -- U+20000, supplementary Han.
    { text = "𛀁", latin = false, cjk = true }, -- U+1B001, supplementary Hiragana.
    { text = "é 日本", latin = true, cjk = true },
    { text = "日本 z", latin = true, cjk = true },
    { text = "привет мир", latin = false, cjk = false },
    { text = "γειά σου", latin = false, cjk = false },
    { text = "مرحبا بالعالم", latin = false, cjk = false },
    { text = "123 — 。 、 😊", latin = false, cjk = false },
    { text = string.char(0), latin = false, cjk = false },
}

--- Detect letters by script rather than byte width, block name, or locale.
local function test_script_detection()
    for _, case in ipairs(SCRIPT_TEST_CASES) do
        h.assert_equals({ utf8.contains_latin_letters(case.text) }, { case.latin })
        h.assert_equals({ utf8.contains_cjk_letters(case.text) }, { case.cjk })
    end
end

-- Every character in a group has the same expected script classification.
local SCRIPT_CHARACTER_TEST_CASES = {
    { text = "AZazªºÀÖØöøÿčɐʸắﬀＡｚ𐞀𝼀", latin = true, cjk = false },
    { text = "日本語ひらがなカタカナｶﾅ한국어ᄀㄱ𠀀𛀁", latin = false, cjk = true },
    { text = "@[`{×÷́ꭥ꜠꜡приветγειάمرحبا123—。、😊", latin = false, cjk = false },
}

--- Check every grouped character independently so a matching neighbor cannot hide a failure.
local function test_individual_script_characters()
    for _, case in ipairs(SCRIPT_CHARACTER_TEST_CASES) do
        for _, character in h.utf8_iter(case.text) do
            h.assert_equals({ character, utf8.contains_latin_letters(character) }, { character, case.latin })
            h.assert_equals({ character, utf8.contains_cjk_letters(character) }, { character, case.cjk })
        end
    end
end

local SCRIPT_BOUNDARY_TEST_CASES = {
    -- Latin-1 letters on either side of the multiplication and division signs.
    { bytes = { 0xC3, 0x96 }, latin = true, cjk = false }, -- U+00D6.
    { bytes = { 0xC3, 0x97 }, latin = false, cjk = false }, -- U+00D7.
    { bytes = { 0xC3, 0x98 }, latin = true, cjk = false }, -- U+00D8.
    { bytes = { 0xC3, 0xB6 }, latin = true, cjk = false }, -- U+00F6.
    { bytes = { 0xC3, 0xB7 }, latin = false, cjk = false }, -- U+00F7.
    { bytes = { 0xC3, 0xB8 }, latin = true, cjk = false }, -- U+00F8.
    -- Greek U+AB65 must not bridge the two adjacent Latin Extended-E ranges.
    { bytes = { 0xEA, 0xAD, 0xA4 }, latin = true, cjk = false }, -- U+AB64.
    { bytes = { 0xEA, 0xAD, 0xA5 }, latin = false, cjk = false }, -- U+AB65.
    { bytes = { 0xEA, 0xAD, 0xA6 }, latin = true, cjk = false }, -- U+AB66.
    -- Supplementary Latin Extended-F contains intentional unassigned gaps.
    { bytes = { 0xF0, 0x90, 0x9E, 0x80 }, latin = true, cjk = false }, -- U+10780.
    { bytes = { 0xF0, 0x90, 0x9E, 0x85 }, latin = true, cjk = false }, -- U+10785.
    { bytes = { 0xF0, 0x90, 0x9E, 0x86 }, latin = false, cjk = false }, -- U+10786.
    { bytes = { 0xF0, 0x90, 0x9E, 0x87 }, latin = true, cjk = false }, -- U+10787.
    -- Hiragana endpoints are letters, while neighboring block positions are not.
    { bytes = { 0xE3, 0x81, 0x80 }, latin = false, cjk = false }, -- U+3040.
    { bytes = { 0xE3, 0x81, 0x81 }, latin = false, cjk = true }, -- U+3041.
    { bytes = { 0xE3, 0x82, 0x96 }, latin = false, cjk = true }, -- U+3096.
    { bytes = { 0xE3, 0x82, 0x97 }, latin = false, cjk = false }, -- U+3097.
    -- Precomposed Hangul syllables include both ends but not neighboring positions.
    { bytes = { 0xEA, 0xAF, 0xBF }, latin = false, cjk = false }, -- U+ABFF.
    { bytes = { 0xEA, 0xB0, 0x80 }, latin = false, cjk = true }, -- U+AC00.
    { bytes = { 0xED, 0x9E, 0xA3 }, latin = false, cjk = true }, -- U+D7A3.
    { bytes = { 0xED, 0x9E, 0xA4 }, latin = false, cjk = false }, -- U+D7A4.
    -- Supplementary Han Extension-B starts and ends at its assigned letters.
    { bytes = { 0xF0, 0x9F, 0xBF, 0xBF }, latin = false, cjk = false }, -- U+1FFFF.
    { bytes = { 0xF0, 0xA0, 0x80, 0x80 }, latin = false, cjk = true }, -- U+20000.
    { bytes = { 0xF0, 0xAA, 0x9B, 0x9F }, latin = false, cjk = true }, -- U+2A6DF.
    { bytes = { 0xF0, 0xAA, 0x9B, 0xA0 }, latin = false, cjk = false }, -- U+2A6E0.
}

--- Check representative inclusive range endpoints and excluded gaps using explicit UTF-8 bytes.
local function test_script_range_boundaries()
    for _, case in ipairs(SCRIPT_BOUNDARY_TEST_CASES) do
        local character = string.char(h.unpack(case.bytes))
        h.assert_equals({ case.bytes, utf8.contains_latin_letters(character) }, { case.bytes, case.latin })
        h.assert_equals({ case.bytes, utf8.contains_cjk_letters(character) }, { case.bytes, case.cjk })
    end
end

--- Supply malformed, overlong, surrogate, and out-of-range UTF-8 encodings.
local function make_invalid_utf8_test_cases()
    return {
        { 0x80 },
        { 0xFF },
        { 0xC3 },
        { 0xE3, 0x81 },
        { 0xF0, 0x90, 0x9E },
        { 0xC1, 0x81 }, -- Overlong ASCII A.
        { 0xE0, 0x81, 0x81 }, -- Overlong ASCII A with three bytes.
        { 0xF0, 0x80, 0x81, 0x81 }, -- Overlong ASCII A with four bytes.
        { 0xE3, 0x20, 0x81 }, -- Invalid continuation byte.
        { 0xED, 0xA0, 0x80 }, -- UTF-16 surrogate U+D800.
        { 0xF4, 0x90, 0x80, 0x80 }, -- Beyond U+10FFFF.
        { 0xF5, 0x80, 0x80, 0x80 }, -- Invalid leading byte.
        { 0xE0, 0x9F, 0xBF }, -- U+07FF is below the three-byte minimum.
        { 0xF0, 0x8F, 0xBF, 0xBF }, -- U+FFFF is below the four-byte minimum.
        { 0xED, 0xBF, 0xBF }, -- UTF-16 surrogate U+DFFF.
    }
end

--- Ignore malformed UTF-8 instead of mistaking its payload for a script letter.
local function test_invalid_utf8()
    for _, bytes in ipairs(make_invalid_utf8_test_cases()) do
        local text = string.char(h.unpack(bytes))
        h.assert_equals(utf8.contains_latin_letters(text), false)
        h.assert_equals(utf8.contains_cjk_letters(text), false)
        h.assert_equals(utf8.contains_latin_letters(text .. " é"), true)
        h.assert_equals(utf8.contains_cjk_letters(text .. " 語"), true)
    end
end

--- Validate public predicate arguments before decoding text.
local function test_script_detection_rejects_invalid_arguments()
    for _, predicate in ipairs { utf8.contains_latin_letters, utf8.contains_cjk_letters } do
        for _, value in ipairs { false, 0, {} } do
            h.assert_equals(pcall(predicate, value), false)
        end
        h.assert_equals(pcall(predicate), false)
    end
end

--- Include both boundaries and use the supplied table as the instance without dropping fields.
local function test_range_boundaries_and_ownership()
    for _, options in ipairs { { from = 0, to = 2 }, { from = -2, to = -1 }, { from = 3, to = 3 } } do
        options.label = "retained"
        local original = h.shallow_copy(options)
        local range = Range:new(options)
        h.assert_equals(options, original)
        h.assert_equals(rawequal(range, options), true)
        h.assert_equals(rawequal(getmetatable(options), Range), true)
        for _, case in ipairs {
            { value = options.from - 1, expected = false },
            { value = options.from, expected = true },
            { value = options.to, expected = true },
            { value = options.to + 1, expected = false },
        } do
            h.assert_equals(range:contains(case.value), case.expected)
        end
        options.from = options.from - 10
        h.assert_equals(range.from, original.from - 10)
    end
end

--- Retain method lookup when an existing range is used as the next range's prototype.
local function test_range_prototype_construction()
    local prototype = Range:new { from = 1, to = 5 }
    for _, options in ipairs { { from = 10, to = 20 }, { from = 30, to = 40 } } do
        local original = { prototype.from, prototype.to }
        local range = prototype:new(options)
        h.assert_equals(rawequal(getmetatable(range), prototype), true)
        h.assert_equals(rawequal(rawget(prototype, "__index"), prototype), true)
        h.assert_equals(rawequal(range, options), true)
        h.assert_equals({ prototype.from, prototype.to }, original)
        h.assert_equals(range:contains(options.from), true)
        h.assert_equals(range:contains(options.to), true)
        h.assert_equals(range:contains(options.from - 1), false)
        h.assert_equals(range:contains(options.to + 1), false)
        prototype = range
    end
end

--- Reject invalid constructor input without modifying the supplied boundaries.
local function test_range_constructor_validation()
    for _, options in ipairs {
        false,
        1,
        "range",
        {},
        { from = "0", to = 1 },
        { from = 0, to = false },
        { from = 2, to = 1 },
    } do
        local original = h.deep_copy(options)
        local original_metatable = getmetatable(options)
        h.assert_equals(pcall(function() Range:new(options) end), false)
        h.assert_equals(options, original)
        h.assert_equals(rawequal(getmetatable(options), original_metatable), true)
    end
    h.assert_equals(pcall(function() Range:new() end), false)
end

--- Reject inherited boundaries before replacing the input metatable or changing prototype lookup.
local function test_range_rejects_inherited_boundaries()
    local prototype = Range:new { from = 1, to = 3 }
    for _, constructor in ipairs { Range, prototype } do
        for _, fields in ipairs { {}, { from = 1 }, { to = 3 } } do
            local metatable = { __index = { from = 1, to = 3 } }
            local options = setmetatable(h.shallow_copy(fields), metatable)
            local original_index = rawget(constructor, "__index")
            local success, message = pcall(constructor.new, constructor, options)
            h.assert_equals(success, false)
            h.assert_equals(h.is_substr(message, "Expected type number, got nil"), true)
            h.assert_equals(h.shallow_copy(options), fields)
            h.assert_equals(rawequal(getmetatable(options), metatable), true)
            h.assert_equals(rawequal(rawget(constructor, "__index"), original_index), true)
        end
    end
end

--- Reject nonnumeric membership arguments without changing the range.
local function test_range_membership_validation()
    local range = Range:new { from = 0, to = 1 }
    for _, value in ipairs { "0", false, {} } do
        h.assert_equals(pcall(function() range:contains(value) end), false)
        h.assert_equals({ range.from, range.to }, { 0, 1 })
    end
    h.assert_equals(pcall(function() range:contains() end), false)
end

--- Run Unicode classification and inclusive-range regressions in both test environments.
local function run_tests()
    test_range_group_assembly()
    test_script_detection()
    test_individual_script_characters()
    test_script_range_boundaries()
    test_invalid_utf8()
    test_script_detection_rejects_invalid_arguments()
    test_range_boundaries_and_ownership()
    test_range_prototype_construction()
    test_range_constructor_validation()
    test_range_rejects_inherited_boundaries()
    test_range_membership_validation()
end

return { run_tests = run_tests }
