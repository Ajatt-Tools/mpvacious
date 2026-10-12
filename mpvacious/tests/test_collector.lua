--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Collect subtitle lines into a joined speech.
]]

local h = require("helpers")
local subtitle = require("subtitles.subtitle")
local speech_collector = require("subtitles.collector")

--- Verify exact boundary overlap counts for empty, partial, and complete matches.
local function test_count_overlapping_lines()
    local cases = {
        -- {recorded_lines, lines_to_append, expected}
        { { "Yes", "No" }, { "No", "Maybe" }, 1 }, -- one shared boundary line
        { { "A", "B", "C" }, { "B", "C", "D" }, 2 }, -- multi-line boundary overlap
        { { "A", "B" }, { "A", "B" }, 2 }, -- full overlap
        { { "A", "B", "C", "D" }, { "C", "D" }, 2 }, -- bounded by the shorter list
        { { "X", "A", "B" }, { "A", "B", "C" }, 2 }, -- larger candidate fails, smaller matches
        { { "A", "B" }, { "C", "D" }, 0 }, -- no overlap
        { {}, { "A" }, 0 }, -- empty recorded_lines
        { { "A" }, {}, 0 }, -- empty lines_to_append
        { {}, {}, 0 }, -- both empty
        { { "A", "B", "C" }, { "A", "D" }, 0 }, -- "A" is in recorded_lines but not at the boundary
        { { "B" }, { "A", "B" }, 0 }, -- "B" ends recorded_lines but doesn't start lines_to_append
        { { "a" }, { "A" }, 0 }, -- exact (case-sensitive) match
    }
    for _, case in ipairs(cases) do
        local recorded_lines, lines_to_append, expected = h.unpack(case)
        h.assert_equals(speech_collector.count_overlapping_lines(recorded_lines, lines_to_append), expected)
    end
end

--- Verify adjacent subtitles do not duplicate shared boundary lines.
local function test_speech_collector_removes_boundary_overlap()
    local collector = speech_collector.new()
    collector.append_sub(subtitle.make_subtitle("First line", 0, 1))
    collector.append_sub(subtitle.make_subtitle("First line\nSecond line", 1, 2))
    h.assert_equals(collector.get_all_as_string(), "First line\nSecond line")
end

--- Verify repetitions separated by a timing gap remain in the speech.
local function test_speech_collector_keeps_repeated_text_after_gap()
    local collector = speech_collector.new()
    collector.append_sub(subtitle.make_subtitle("Same line", 0, 1))
    collector.append_sub(subtitle.make_subtitle("Same line", 2, 3))
    h.assert_equals(collector.get_all_as_string(), "Same line\nSame line")
end

--- Verify collected speech normalizes mixed newline conventions.
local function test_speech_collector_normalizes_newlines()
    local collector = speech_collector.new()
    collector.append_sub(subtitle.make_subtitle("First line\r\nSecond line\rThird line", 0, 1))
    h.assert_equals(collector.get_all_as_string(), "First line\nSecond line\nThird line")
end

--- Verify interior empty lines survive subtitle collection.
local function test_speech_collector_preserves_empty_lines()
    local collector = speech_collector.new()
    collector.append_sub(subtitle.make_subtitle("First line\n\nSecond line", 0, 1))
    h.assert_equals(collector.get_all_as_string(), "First line\n\nSecond line")
end

--- Verify collected speech omits a trailing newline.
local function test_speech_collector_drops_trailing_newline()
    local collector = speech_collector.new()
    collector.append_sub(subtitle.make_subtitle("First line\nSecond line\n", 0, 1))
    h.assert_equals(collector.get_all_as_string(), "First line\nSecond line")
end

--- Run subtitle speech-collection regressions.
local function run_tests()
    test_count_overlapping_lines()
    test_speech_collector_removes_boundary_overlap()
    test_speech_collector_keeps_repeated_text_after_gap()
    test_speech_collector_normalizes_newlines()
    test_speech_collector_preserves_empty_lines()
    test_speech_collector_drops_trailing_newline()
end

return {
    run_tests = run_tests,
}
