--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Sentence-matching policy tests for guarded note updates.
]]

local h = require("helpers")
local guard_module = require("anki.note_update_guard")

local make_note_update_guard = guard_module.new

------------------------------------------------------------
-- Tests: executed by both standalone and mpv-backed runners.

--- Return note field tables for test sentence values; false represents unavailable fields.
local function make_guard_test_note_fields(sentences)
    local fields = {}
    for _, sentence in ipairs(sentences) do
        table.insert(fields, sentence == false and {} or { SentKanji = sentence })
    end
    return fields
end

local TEST_SENTENCE = "それは うまくすれば 鉛から黄金を生み出すことも 可能になる"
local TEST_UNRELATED_SENTENCE =
    "まあ 無理やり手伝った というのが正しいけれど それで稼いだお金よ"

--- Test equivalent, contained, unrelated, and empty sentence fields.
local function test_sentence_relationship(test_guard)
    local cases = {
        {
            second = "<b>それは　うまくすれば</b> 鉛から黄金を生み出すことも 可能になる",
            expected = true,
        },
        { second = "鉛から黄金を生み出すことも", expected = true },
        { first = "鉛から黄金を生み出すことも", second = TEST_SENTENCE, expected = true },
        { second = TEST_UNRELATED_SENTENCE, expected = false },
        { first = "", second = TEST_SENTENCE, expected = false },
    }
    for _, case in ipairs(cases) do
        h.assert_equals(test_guard.sentences_are_related(case.first or TEST_SENTENCE, case.second), case.expected)
    end
end

--- Return fresh warning scenarios for matching, mismatched, blank, and unavailable fields.
local function make_subtitle_warning_test_cases()
    local partial_match = "Only 1 of 2 target notes have SentKanji matching the current subtitle."
    return {
        { fields = { "<b>" .. TEST_SENTENCE .. "</b>" }, expected = nil },
        {
            fields = { TEST_UNRELATED_SENTENCE },
            expected = "The target note's SentKanji does not match the current subtitle.",
        },
        { fields = { TEST_SENTENCE, TEST_UNRELATED_SENTENCE }, expected = partial_match },
        { fields = { "", TEST_SENTENCE }, expected = partial_match },
        { fields = { false, TEST_SENTENCE }, expected = partial_match },
    }
end

--- Test warnings for matching, mismatched, blank, unavailable, and multi-note targets.
local function test_current_subtitle_warning(test_guard)
    for _, case in ipairs(make_subtitle_warning_test_cases()) do
        h.assert_equals(
            test_guard.current_subtitle_warning(make_guard_test_note_fields(case.fields), TEST_SENTENCE, "SentKanji"),
            case.expected
        )
    end
    h.assert_equals(
        test_guard.current_subtitle_warning(make_guard_test_note_fields({ TEST_SENTENCE }), "", "SentKanji"),
        "Couldn't verify the current subtitle against target notes' SentKanji field."
    )
end

--- Run guard tests in both standalone and mpv-backed runners.
local function run_tests(test_guard)
    test_guard = test_guard or make_note_update_guard()
    test_sentence_relationship(test_guard)
    test_current_subtitle_warning(test_guard)
end

return {
    run_tests = run_tests,
}
