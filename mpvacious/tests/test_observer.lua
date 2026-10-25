--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Subtitle observer tests.
]]

local h = require("helpers")
local subtitle = require("subtitles.subtitle")
local subtitles_observer = require("subtitles.observer")
local Menu = require("menu.menu")
local fixtures = require("tests.fixtures")

--- Construct a secondary subtitle with the real class methods and metatable.
local function make_test_secondary_sub(text, start_time, end_time)
    local sub = subtitle.Subtitle:new {
        text = text,
        ["start"] = start_time,
        ["end"] = end_time,
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
    h.assert_equals(observer.recorded_secondary_subs()[1]["text"], "Secondary")
    h.assert_equals(observer.recorded_secondary_subs()[1]:duration(), 1)
    h.assert_equals(observer.collect_from_current().secondary, "Secondary")
    h.assert_equals(observer.get_timing("start"), 0)
    observer.clear()
    h.assert_equals(observer.has_recorded_dialogs(), false)
    h.assert_equals(#observer.recorded_secondary_subs(), 0)
    h.assert_equals(observer.get_timing("start"), -1)
end

--- Verify cycling one observer's autocopy method does not alter another.
local function test_autoclip_method_state_is_isolated()
    local first = subtitles_observer.new()
    local second = subtitles_observer.new()
    first.next_autoclip_method()
    h.assert_equals(first.autocopy_current_method(), "goldendict")
    h.assert_equals(second.autocopy_current_method(), "clipboard")
end

--- A menu-wrapped autocopy toggle redraws the enabled and disabled status.
local function test_autocopy_toggle_refreshes_open_menu()
    local observer = subtitles_observer.new()
    local redraws = 0
    local menu = Menu:new {
        active = true,
        overlay = {
            --- Count overlay redraws without rendering an mpv overlay.
            update = function() redraws = redraws + 1 end,
        },
    }
    --- Supply the observer's current autocopy status as menu text.
    menu.make_osd = function()
        return { get_text = observer.autocopy_is_enabled_str }
    end
    local toggle = menu:with_update { observer.toggle_autocopy }
    for _, expected in ipairs { "enabled", "disabled" } do
        toggle()
        h.assert_equals(menu.overlay.data, expected)
        h.assert_equals(observer.autocopy_is_enabled_str(), expected)
    end
    h.assert_equals(redraws, 2)
end

--- Supply visible subtitle tracks with independent delays for isolated observer tests.
local function make_observer_api_test_properties()
    return {
        ["sub-text"] = "Primary",
        ["sub-start"] = 10,
        ["sub-end"] = 12,
        ["secondary-sub-text"] = "Secondary",
        ["secondary-sub-start"] = 11,
        ["secondary-sub-end"] = 13,
        ["sub-delay"] = 2,
        ["secondary-sub-delay"] = 1,
        ["audio-delay"] = 0.5,
    }
end

--- Register callbacks only on the supplied API and collect its independently delayed tracks.
local function test_injected_api_observers_and_history()
    local properties = make_observer_api_test_properties()
    local api, observers = fixtures.make_subtitle_observer_test_api(properties)
    local observer = subtitles_observer.new { mp = api }
    observer.init({}, fixtures.make_config_manager { autoclip = false, autoclip_method = "clipboard" })
    for _, name in ipairs { "sub-text", "secondary-sub-text" } do
        h.assert_equals(observers[name].format, "string")
        observers[name].callback()
    end
    properties["sub-text"], properties["secondary-sub-text"] = nil, nil
    local primary, secondary = observer.all_subs_until_now()
    h.assert_equals(#primary, 1)
    h.assert_equals(#secondary, 1)
    h.assert_equals(primary[1].text, "Primary")
    h.assert_equals({ primary[1]["start"], primary[1]["end"], primary[1].is_secondary }, { 11.5, 13.5, false })
    h.assert_equals(secondary[1].text, "Secondary")
    h.assert_equals({ secondary[1]["start"], secondary[1]["end"], secondary[1].is_secondary }, { 11.5, 13.5, true })
end

--- Read current subtitles through each observer's own API for either collection entry point.
local function test_injected_api_current_collection()
    for _, method in ipairs { "collect_from_current", "collect_from_all_dialogues" } do
        local api = fixtures.make_subtitle_observer_test_api(make_observer_api_test_properties())
        local observer = subtitles_observer.new { mp = api }
        local collected = observer[method](1)
        h.assert_equals(collected.text, "Primary")
        h.assert_equals(collected.secondary, "Secondary")
        h.assert_equals({ collected["start"], collected["end"] }, { 11.5, 13.5 })
    end
end

--- Initialize one observer with optional selection recording and observable text reads and redraws.
local function make_append_subtitle_test_context(recording)
    local properties = make_observer_api_test_properties()
    local api, observers, reads = fixtures.make_subtitle_observer_test_api(properties)
    local state = { update_count = 0 }
    local observer = subtitles_observer.new { mp = api }
    observer.init(
        fixtures.make_subtitle_observer_test_menu(state),
        fixtures.make_config_manager { autoclip = false, autoclip_method = "clipboard" }
    )
    if recording then observer.set_to_current_sub() end
    return { observer = observer, properties = properties, observers = observers, reads = reads, state = state }
end

--- Read a callback's subtitle once, storing it in history and only updating an active selection.
local function assert_append_subtitle_test_case(case, recording)
    local ctx = make_append_subtitle_test_context(recording)
    local before = ctx.state.update_count
    ctx.reads[case.property] = 0
    ctx.properties[case.property] = "Next subtitle"
    ctx.properties["sub-start"], ctx.properties["secondary-sub-start"] = 20, 20
    ctx.properties["sub-end"], ctx.properties["secondary-sub-end"] = 22, 22
    ctx.observers[case.property].callback()
    h.assert_equals(ctx.reads[case.property], 1)
    local selected = ctx.observer[case.selection]()
    local histories = { ctx.observer.all_subs_until_now() }
    local expected_history, expected_selected, expected_updates = 1, 0, before
    if recording then
        expected_history, expected_selected, expected_updates = 2, 2, before + 1
    end
    h.assert_equals(#histories[case.history], expected_history)
    h.assert_equals(#selected, expected_selected)
    h.assert_equals(ctx.state.update_count, expected_updates)
    h.assert_equals(histories[case.history][expected_history].text, "Next subtitle")
end

--- Describe the primary and secondary callback boundaries without sharing mutable scenarios.
local function make_append_callback_test_cases()
    return {
        { property = "sub-text", prefix = "sub-", selection = "recorded_subs", history = 1 },
        {
            property = "secondary-sub-text",
            prefix = "secondary-sub-",
            selection = "recorded_secondary_subs",
            history = 2,
        },
    }
end

--- Primary and secondary callbacks use the same early-return policy with or without recording.
local function test_append_subtitle_reads_once()
    for _, recording in ipairs { false, true } do
        for _, case in ipairs(make_append_callback_test_cases()) do
            assert_append_subtitle_test_case(case, recording)
        end
    end
end

--- Capture detached history, selection, and redraw state before delivering an inert callback.
local function snapshot_append_subtitle_test_state(ctx)
    return h.deep_copy {
        histories = { ctx.observer.all_subs_until_now() },
        primary = ctx.observer.recorded_subs(),
        secondary = ctx.observer.recorded_secondary_subs(),
        updates = ctx.state.update_count,
    }
end

--- Duplicate events and disappearing subtitles must not change history, selection, or redraws.
local function assert_inert_append_subtitle_test_case(case, recording, disappeared)
    local ctx = make_append_subtitle_test_context(recording)
    local before = snapshot_append_subtitle_test_state(ctx)
    if disappeared then
        for _, suffix in ipairs { "text", "start", "end" } do
            ctx.properties[case.prefix .. suffix] = nil
        end
    end
    ctx.reads[case.property] = 0
    ctx.observers[case.property].callback()
    h.assert_equals(ctx.reads[case.property], 1)
    h.assert_equals(snapshot_append_subtitle_test_state(ctx), before)
end

--- Exercise both track callbacks with and without an active recording selection.
local function test_append_subtitle_inert_events()
    for _, recording in ipairs { false, true } do
        for _, disappeared in ipairs { false, true } do
            for _, case in ipairs(make_append_callback_test_cases()) do
                assert_inert_append_subtitle_test_case(case, recording, disappeared)
            end
        end
    end
end

--- Exercise real clipboard preparation with the legacy whitespace filter enabled or disabled.
local function assert_clipboard_space_filter_test_case(case)
    local api = fixtures.make_subtitle_observer_test_api({})
    local observer = subtitles_observer.new { mp = api }
    observer.init(
        {},
        fixtures.make_config_manager {
            autoclip = false,
            autoclip_method = "clipboard",
            clipboard_trim_enabled = false,
            nuke_spaces = case.enabled,
        }
    )
    h.assert_equals(observer.clipboard_prepare(case.text), case.expected)
end

--- Enabled whitespace filtering must retain its live helper dependency without crashing.
local function test_clipboard_space_filtering()
    for _, case in ipairs {
        { enabled = true, text = "日 本", expected = "日本" },
        { enabled = false, text = "日 本", expected = "日 本" },
        { enabled = true, text = "Latin words", expected = "Latin words" },
        { enabled = false, text = "Latin words", expected = "Latin words" },
    } do
        assert_clipboard_space_filter_test_case(case)
    end
end

--- Run observer instance, selection, API-injection, and menu-refresh regressions.
local function run_tests()
    test_instances_keep_recorded_subs_isolated()
    test_import_subs_separates_tracks_and_clear_resets_selection()
    test_autoclip_method_state_is_isolated()
    test_autocopy_toggle_refreshes_open_menu()
    test_injected_api_observers_and_history()
    test_injected_api_current_collection()
    test_append_subtitle_reads_once()
    test_append_subtitle_inert_events()
    test_clipboard_space_filtering()
end

return {
    run_tests = run_tests,
}
