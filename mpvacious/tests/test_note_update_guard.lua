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

--- Return note field tables for test sentence values. False represents unavailable fields.
local function make_guard_test_note_fields(sentences)
    local fields = {}
    for _, sentence in ipairs(sentences) do
        if sentence == false then
            table.insert(fields, {})
        else
            table.insert(fields, { SentKanji = sentence })
        end
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

--- Compare HTML spacing in either input while retaining mismatch and empty-text safeguards.
local function assert_guard_html_spacing_test_case(test_guard, separator)
    local formatted = "hello" .. separator .. "world"
    local unrelated = "goodbye" .. separator .. "moon"
    local fields = { { SentKanji = formatted } }
    h.assert_equals(test_guard.sentences_are_related("hello world", formatted), true)
    h.assert_equals(test_guard.sentences_are_related(formatted, "hello world"), true)
    h.assert_equals(test_guard.current_subtitle_warning(fields, "hello world", "SentKanji"), nil)
    h.assert_equals(test_guard.current_subtitle_warning({ { SentKanji = "hello world" } }, formatted, "SentKanji"), nil)
    h.assert_equals(test_guard.sentences_are_related("hello world", unrelated), false)
    h.assert_equals(
        test_guard.current_subtitle_warning(fields, unrelated, "SentKanji"),
        "The target note's SentKanji does not match the current subtitle."
    )
    h.assert_equals(test_guard.sentences_are_related(separator, separator), false)
    h.assert_equals(
        test_guard.current_subtitle_warning(fields, separator, "SentKanji"),
        "Couldn't verify the current subtitle against target notes' SentKanji field."
    )
end

--- Treat nonbreaking-space entities and common HTML line breaks as ordinary spacing.
local function test_html_sentence_spacing(test_guard)
    for _, separator in ipairs { "&nbsp;", "<br>", "<br/>", "<br />", "<BR>", "<BR />" } do
        assert_guard_html_spacing_test_case(test_guard, separator)
    end
end

--- Return escaped markup cases whose literal contents must survive HTML removal.
local function make_escaped_markup_test_cases()
    return {
        { first = "It says &lt;hello&gt; here.", second = "It says &lt;goodbye&gt; here.", expected = false },
        { first = "It says &lt;br&gt; here.", second = "It says &lt;hr&gt; here.", expected = false },
        { first = "&lt;hello&gt;", second = "&lt;hello&gt;", expected = true },
        { first = "&lt;br&gt;", second = "&lt;br&gt;", expected = true },
        { first = "<b>&lt;hello&gt;</b>", second = "&lt;hello&gt;", expected = true },
    }
end

--- Return nested entity cases that must be decoded only once per original input.
local function make_nested_entity_test_cases()
    return {
        {
            first = "It says &amp;lt;hello&amp;gt; here.",
            second = "It says &amp;lt;goodbye&amp;gt; here.",
            expected = false,
        },
        {
            first = "It says &amp;lt;hello&amp;gt; here.",
            second = "It says &lt;hello&gt; here.",
            expected = false,
        },
        { first = "It says &amp;nbsp; here.", second = "It says here.", expected = false },
    }
end

--- Check both comparison directions and warning generation from the same original inputs.
local function assert_literal_entity_test_case(test_guard, case)
    for _, pair in ipairs { { case.first, case.second }, { case.second, case.first } } do
        h.assert_equals(test_guard.sentences_are_related(pair[1], pair[2]), case.expected)
        local warning = test_guard.current_subtitle_warning({ { SentKanji = pair[2] } }, pair[1], "SentKanji")
        if case.expected then
            h.assert_equals(warning, nil)
        else
            h.assert_equals(warning, "The target note's SentKanji does not match the current subtitle.")
        end
    end
end

--- Preserve escaped sentence content without interpreting it as tags or repeated entities.
local function test_literal_html_entities(test_guard)
    for _, cases in ipairs { make_escaped_markup_test_cases(), make_nested_entity_test_cases() } do
        for _, case in ipairs(cases) do
            assert_literal_entity_test_case(test_guard, case)
        end
    end
end

--- Return fresh warning scenarios for matching, mismatched, blank, and unavailable fields.
local function make_subtitle_warning_test_cases()
    local partial_match = "Only 1 of 2 target notes have SentKanji matching the current subtitle."
    return {
        { fields = {}, expected = nil },
        { fields = { "<b>" .. TEST_SENTENCE .. "</b>" }, expected = nil },
        { fields = { TEST_SENTENCE, TEST_SENTENCE }, expected = nil },
        {
            fields = { TEST_UNRELATED_SENTENCE },
            expected = "The target note's SentKanji does not match the current subtitle.",
        },
        { fields = { TEST_SENTENCE, TEST_UNRELATED_SENTENCE }, expected = partial_match },
        { fields = { "", TEST_SENTENCE }, expected = partial_match },
        { fields = { false, TEST_SENTENCE }, expected = partial_match },
        {
            fields = { TEST_UNRELATED_SENTENCE, TEST_UNRELATED_SENTENCE },
            expected = "Only 0 of 2 target notes have SentKanji matching the current subtitle.",
        },
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
    test_html_sentence_spacing(test_guard)
    test_literal_html_entities(test_guard)
    test_current_subtitle_warning(test_guard)
end

return {
    run_tests = run_tests,
}
