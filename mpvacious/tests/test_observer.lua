--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Subtitle observer tests.
]]

local h = require('helpers')
local subtitle = require('subtitles.subtitle')
local subtitles_observer = require('subtitles.observer')

local function make_test_secondary_sub(text, start_time, end_time)
    local sub = subtitle.Subtitle.new{
        text = text,
        ['start'] = start_time,
        ['end'] = end_time,
        is_secondary = true,
    }
    return sub
end

local function test_instances_keep_recorded_subs_isolated()
    local first = subtitles_observer.new()
    local second = subtitles_observer.new()
    first.import_subs { subtitle.make_subtitle("First", 0, 1) }
    second.import_subs { subtitle.make_subtitle("Second", 1, 2) }
    h.assert_equals(first.get_selected_primary_text(), "First")
    h.assert_equals(second.get_selected_primary_text(), "Second")
end

local function test_import_subs_separates_tracks_and_clear_resets_selection()
    local observer = subtitles_observer.new()
    observer.import_subs {
        subtitle.make_subtitle("Primary", 0, 1),
        make_test_secondary_sub("Secondary", 0, 1),
    }
    h.assert_equals(observer.get_selected_primary_text(), "Primary")
    h.assert_equals(observer.recorded_secondary_subs()[1]['text'], "Secondary")
    h.assert_equals(observer.get_timing('start'), 0)
    observer.clear()
    h.assert_equals(observer.has_recorded_dialogs(), false)
    h.assert_equals(#observer.recorded_secondary_subs(), 0)
    h.assert_equals(observer.get_timing('start'), -1)
end

local function test_autoclip_method_state_is_isolated()
    local first = subtitles_observer.new()
    local second = subtitles_observer.new()
    first.next_autoclip_method()
    h.assert_equals(first.autocopy_current_method(), 'goldendict')
    h.assert_equals(second.autocopy_current_method(), 'clipboard')
end

local function run_tests()
    test_instances_keep_recorded_subs_isolated()
    test_import_subs_separates_tracks_and_clear_resets_selection()
    test_autoclip_method_state_is_isolated()
end

return {
    run_tests = run_tests,
}
