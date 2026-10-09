--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Subtitle observer tests.
]]

local h = require('helpers')
local subtitle = require('subtitles.subtitle')
local subtitles_observer = require('subtitles.observer')
local Menu = require('menu.menu')

--- Construct a secondary subtitle with the real class methods and metatable.
local function make_test_secondary_sub(text, start_time, end_time)
    local sub = subtitle.Subtitle:new {
        text = text,
        ['start'] = start_time,
        ['end'] = end_time,
        is_secondary = true,
    }
    return sub
end

--- Verify recorded subtitle selections remain isolated between observer instances.
local function test_instances_keep_recorded_subs_isolated()
    local first = subtitles_observer.new()
    local second = subtitles_observer.new()
    first.import_subs { subtitle.make_subtitle("First", 0, 1) }
    second.import_subs { subtitle.make_subtitle("Second", 1, 2) }
    h.assert_equals(first.get_selected_primary_text(), "First")
    h.assert_equals(second.get_selected_primary_text(), "Second")
end

--- Verify imported tracks retain methods and clearing resets both selections.
local function test_import_subs_separates_tracks_and_clear_resets_selection()
    local observer = subtitles_observer.new()
    observer.import_subs {
        subtitle.make_subtitle("Primary", 0, 1),
        make_test_secondary_sub("Secondary", 0, 1),
    }
    h.assert_equals(observer.get_selected_primary_text(), "Primary")
    h.assert_equals(observer.recorded_secondary_subs()[1]['text'], "Secondary")
    h.assert_equals(observer.recorded_secondary_subs()[1]:duration(), 1)
    h.assert_equals(observer.collect_from_current().secondary, 'Secondary')
    h.assert_equals(observer.get_timing('start'), 0)
    observer.clear()
    h.assert_equals(observer.has_recorded_dialogs(), false)
    h.assert_equals(#observer.recorded_secondary_subs(), 0)
    h.assert_equals(observer.get_timing('start'), -1)
end

--- Verify cycling one observer's autocopy method does not alter another.
local function test_autoclip_method_state_is_isolated()
    local first = subtitles_observer.new()
    local second = subtitles_observer.new()
    first.next_autoclip_method()
    h.assert_equals(first.autocopy_current_method(), 'goldendict')
    h.assert_equals(second.autocopy_current_method(), 'clipboard')
end

--- A menu-wrapped autocopy toggle redraws the enabled and disabled status.
local function test_autocopy_toggle_refreshes_open_menu()
    local observer = subtitles_observer.new()
    local redraws = 0
    local menu = Menu:new { active = true, overlay = {
        --- Count overlay redraws without rendering an mpv overlay.
        update = function() redraws = redraws + 1 end,
    } }
    --- Supply the observer's current autocopy status as menu text.
    menu.make_osd = function()
        return { get_text = observer.autocopy_is_enabled_str }
    end
    local toggle = menu:with_update { observer.toggle_autocopy }
    for _, expected in ipairs { 'enabled', 'disabled' } do
        toggle()
        h.assert_equals(menu.overlay.data, expected)
        h.assert_equals(observer.autocopy_is_enabled_str(), expected)
    end
    h.assert_equals(redraws, 2)
end

--- Run observer instance, selection, and menu-refresh regressions.
local function run_tests()
    test_instances_keep_recorded_subs_isolated()
    test_import_subs_separates_tracks_and_clear_resets_selection()
    test_autoclip_method_state_is_isolated()
    test_autocopy_toggle_refreshes_open_menu()
end

return {
    run_tests = run_tests,
}
