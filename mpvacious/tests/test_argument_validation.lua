--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Closed-set argument validation and rejection-before-side-effects tests.
]]

local h = require("helpers")
local fixtures = require("tests.fixtures")
local timings = require("utils.timings")
local subtitle = require("subtitles.subtitle")
local sub_list = require("subtitles.sub_list")
local observer = require("subtitles.observer")
local play_control = require("utils.play_control")
local OSD = require("menu.osd_styler")
local switch = require("utils.switch")

--- Require rejection by membership validation rather than an incidental runtime failure.
local function assert_argument_test_rejected(callback, value)
    local success, message = pcall(callback, value)
    h.assert_equals(success, false)
    h.assert_equals(h.is_substr(message, "Expected one of "), true)
end

--- Create independent populated timing stores without starting playback or rendering menus.
local function make_boundary_validation_test_context()
    local manual, subs = timings.new(), sub_list.new()
    manual.set("start", 10)
    manual.set("end", 20)
    local sub = subtitle.make_subtitle("Line", 10, 20)
    subs.insert(sub)
    local selected = observer.new()
    selected.import_subs { sub }
    return { manual = manual, subs = subs, observer = selected }
end

--- Capture supported boundary values to detect mutation after rejected arguments.
local function snapshot_boundary_validation_test_state(ctx)
    return {
        ctx.manual.get("start"),
        ctx.manual.get("end"),
        ctx.subs.get_time("start"),
        ctx.subs.get_time("end"),
        ctx.observer.get_timing("start"),
        ctx.observer.get_timing("end"),
        ctx.observer.is_appending(),
    }
end

--- Reject unsupported boundary names at both storage and observer entry points.
local function test_invalid_timing_boundaries()
    local ctx = make_boundary_validation_test_context()
    local original = snapshot_boundary_validation_test_state(ctx)
    for _, case in ipairs { { value = "middle" }, { value = "" }, { value = false }, { value = 1 }, {} } do
        for _, callback in ipairs {
            ctx.manual.get,
            ctx.manual.is_set,
            ctx.subs.get_time,
            ctx.observer.get_timing,
            ctx.observer.set_manual_timing,
            ctx.observer.set_manual_timing_to_sub,
            function(value) ctx.manual.set(value, 99) end,
        } do
            assert_argument_test_rejected(callback, case.value)
        end
        h.assert_equals(snapshot_boundary_validation_test_state(ctx), original)
    end
end

--- Valid start/end reads and writes retain their previous timing semantics.
local function test_valid_timing_boundaries()
    local ctx = make_boundary_validation_test_context()
    for _, case in ipairs { { position = "start", time = 10 }, { position = "end", time = 20 } } do
        h.assert_equals(ctx.manual.is_set(case.position), true)
        h.assert_equals(ctx.manual.get(case.position), case.time)
        h.assert_equals(ctx.subs.get_time(case.position), case.time)
        h.assert_equals(ctx.observer.get_timing(case.position), case.time)
        ctx.manual.set(case.position, -1)
        h.assert_equals(ctx.manual.is_set(case.position), false)
        ctx.manual.set(case.position, 0)
        h.assert_equals(ctx.manual.is_set(case.position), true)
        h.assert_equals(ctx.manual.get(case.position), 0)
    end
end

--- Reject unknown playback directions before seeking, pausing, or touching timer observers.
local function test_invalid_playback_directions()
    local state = { commands = {}, writes = {}, observers = {}, unobserved = {} }
    local api = fixtures.make_playback_test_api { state = state, properties = {} }
    local control = play_control.new { mp = api, notify = h.as_callback(error, "unexpected notification") }
    for _, case in ipairs { { value = "next" }, { value = "" }, { value = false }, {} } do
        assert_argument_test_rejected(control.sub_seek, case.value)
        h.assert_equals(state, { commands = {}, writes = {}, observers = {}, unobserved = {} })
    end
end

--- Invalid track types must fail before fetching metadata from real or injected mpv APIs.
local function test_invalid_track_types()
    local api = { get_property_native = h.as_callback(error, "unexpected track read") }
    for _, case in ipairs { { value = "subtitle" }, { value = "" }, { value = false }, {} } do
        assert_argument_test_rejected(h.get_loaded_tracks, case.value)
        assert_argument_test_rejected(function(value) h.get_active_track(value, api) end, case.value)
    end
end

--- Invalid log levels fail before logging or OSD calls, while empty messages remain silent.
local function test_invalid_notification_levels()
    for _, case in ipairs { { value = "warning" }, { value = "" }, { value = 1 }, { value = {} } } do
        assert_argument_test_rejected(function(level) h.notify("Message", level) end, case.value)
    end
    h.assert_equals(h.notify(nil, "invalid"), nil)
    h.assert_equals(h.notify("", "invalid"), nil)
end

--- Every supported ASS alignment renders unchanged and preserves chaining.
local function test_valid_osd_alignments()
    for alignment = 1, 9 do
        local osd = OSD:new()
        h.assert_equals(rawequal(osd:align(alignment), osd), true)
        h.assert_equals(osd:get_text(), string.format("{\\an%d}", alignment))
    end
end

--- Invalid ASS alignment values leave the builder unchanged.
local function test_invalid_osd_alignments()
    for _, case in ipairs { { value = 0 }, { value = 10 }, { value = 1.5 }, { value = "4" }, {} } do
        local osd = OSD:new()
        assert_argument_test_rejected(function(value) osd:align(value) end, case.value)
        h.assert_equals(osd:get_text(), "")
    end
end

--- One-step cycling still wraps in both directions and invalid steps do not move it.
local function test_switch_steps()
    local selector = switch.new { "first", "second" }
    for _, case in ipairs { { step = -1, expected = "second" }, { step = 1, expected = "first" } } do
        h.assert_equals(selector.change_menu_item(case.step), case.expected)
    end
    for _, case in ipairs { { value = 0 }, { value = 2 }, { value = -2 }, { value = "1" }, {} } do
        assert_argument_test_rejected(selector.change_menu_item, case.value)
        h.assert_equals(selector.get_index(), 1)
        h.assert_equals(selector.get(), "first")
    end
end

--- Run closed-set validation regressions in both standalone and real-mpv test paths.
local function run_tests()
    test_invalid_timing_boundaries()
    test_valid_timing_boundaries()
    test_invalid_playback_directions()
    test_invalid_track_types()
    test_invalid_notification_levels()
    test_valid_osd_alignments()
    test_invalid_osd_alignments()
    test_switch_steps()
end

return { run_tests = run_tests }
