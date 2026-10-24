--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Playback-control construction and timing tests.
]]

local h = require("helpers")
local fixtures = require("tests.fixtures")
local play_control = require("utils.play_control")
local pause_timer = require("utils.pause_timer")

--- Create isolated playback controls using the real subtitle reader and pause timer.
local function make_play_control_test_context(overrides)
    local state = { commands = {}, writes = {}, observers = {}, unobserved = {} }
    local properties = {
        ["sub-text"] = "First",
        ["sub-start"] = 10,
        ["sub-end"] = 12,
        ["sub-delay"] = 2,
        ["audio-delay"] = 0.5,
    }
    for name, value in pairs(overrides or {}) do
        properties[name] = value
    end
    local api = fixtures.make_playback_test_api { state = state, properties = properties }
    local control = play_control.new { mp = api, notify = fixtures.make_notifier(state) }
    return { control = control, state = state, properties = properties, mp = api }
end

--- Find one registered callback for explicit delivery by a playback test.
local function find_play_control_test_observer(state, name)
    for callback, registration in pairs(state.observers) do
        if registration.name == name then return callback end
    end
    return nil
end

--- Each construction returns its own command table without invoking playback operations.
local function test_instances_own_command_tables()
    local first, second = play_control.new(), play_control.new()
    h.assert_equals(rawequal(first, second), false)
    for _, name in ipairs { "play_till_sub_end", "play_till_next_sub_end", "sub_seek", "sub_rewind" } do
        h.assert_equals(type(first[name]), "function")
        h.assert_equals(type(second[name]), "function")
    end
    local rewind = second.sub_rewind
    first.sub_rewind = h.noop
    h.assert_equals(rawequal(second.sub_rewind, rewind), true)
    h.assert_equals(rawequal(second.sub_rewind, h.noop), false)
end

--- Return positive, negative, and zero effective-delay scenarios.
local function make_playback_timing_test_cases()
    return {
        { subtitle_delay = 2, audio_delay = 0.5 },
        { subtitle_delay = -2, audio_delay = 0.5 },
        { subtitle_delay = 1, audio_delay = 1 },
    }
end

--- Replay seeks and pauses using the adjusted subtitle boundaries, applying the offset once.
local function assert_playback_replay_test_case(case)
    local ctx =
        make_play_control_test_context { ["sub-delay"] = case.subtitle_delay, ["audio-delay"] = case.audio_delay }
    local offset = case.subtitle_delay - case.audio_delay
    ctx.control.play_till_sub_end()
    h.assert_equals(ctx.state.commands, { { "seek", 10 + offset, "absolute" } })
    local callback = find_play_control_test_observer(ctx.state, "time-pos")
    h.assert_equals(ctx.state.observers[callback].format, "number")
    local boundary = 12 + offset - 0.050
    callback("time-pos", boundary)
    h.assert_equals(ctx.state.writes, { { "pause", "no" } })
    callback("time-pos", boundary + 0.001)
    h.assert_equals(ctx.state.writes, { { "pause", "no" }, { "pause", "yes" } })
    h.assert_equals(ctx.state.observers, {})
end

--- Rewind uses adjusted start timing and cancels an already scheduled stop timer.
local function assert_playback_rewind_test_case(case)
    local ctx =
        make_play_control_test_context { ["sub-delay"] = case.subtitle_delay, ["audio-delay"] = case.audio_delay }
    ctx.control.play_till_sub_end()
    local timer_callback = find_play_control_test_observer(ctx.state, "time-pos")
    ctx.state.commands, ctx.state.writes = {}, {}
    ctx.control.sub_rewind()
    local start_time = 10 + case.subtitle_delay - case.audio_delay + 0.015
    h.assert_equals(ctx.state.commands, { { "seek", start_time, "absolute" } })
    h.assert_equals(ctx.state.writes, {})
    h.assert_equals(ctx.state.observers, {})
    h.assert_equals(ctx.state.unobserved, { timer_callback })
end

--- Exercise replay and rewind under both nonzero offsets and a zero effective delay.
local function test_adjusted_playback_timings()
    for _, case in ipairs(make_playback_timing_test_cases()) do
        assert_playback_replay_test_case(case)
        assert_playback_rewind_test_case(case)
    end
end

--- Deliver absent and repeated subtitle events without scheduling a stop.
local function deliver_inert_playback_test_events(ctx, callback)
    callback()
    h.assert_equals(find_play_control_test_observer(ctx.state, "time-pos"), nil)
    ctx.properties["sub-text"], ctx.properties["sub-start"], ctx.properties["sub-end"] = nil, nil, nil
    callback()
    h.assert_equals(find_play_control_test_observer(ctx.state, "time-pos"), nil)
    h.assert_equals(ctx.state.unobserved, {})
end

--- Waiting ignores absent or unchanged subtitles and pauses after the next adjusted end.
local function assert_playback_wait_test_case(initially_visible)
    local ctx = make_play_control_test_context()
    if not initially_visible then
        ctx.properties["sub-text"], ctx.properties["sub-start"], ctx.properties["sub-end"] = nil, nil, nil
    end
    ctx.control.play_till_next_sub_end()
    local callback = find_play_control_test_observer(ctx.state, "sub-text")
    h.assert_equals(ctx.state.observers[callback].format, "string")
    deliver_inert_playback_test_events(ctx, callback)
    ctx.properties["sub-text"], ctx.properties["sub-start"], ctx.properties["sub-end"] = "Next", 20, 23
    callback()
    h.assert_equals(ctx.state.observers[callback], nil)
    local timer_callback = find_play_control_test_observer(ctx.state, "time-pos")
    timer_callback("time-pos", 23 + 1.5 - 0.050 + 0.001)
    h.assert_equals(ctx.state.commands, {})
    h.assert_equals(ctx.state.writes, { { "pause", "no" }, { "pause", "yes" } })
    h.assert_equals(ctx.state.observers, {})
end

--- Start waiting both with a visible subtitle and during a subtitle gap.
local function test_waiting_for_next_subtitle()
    for _, initially_visible in ipairs { false, true } do
        assert_playback_wait_test_case(initially_visible)
    end
end

--- Missing subtitles must not seek, start playback, or register a pause timer.
local function test_missing_subtitle_playback_commands()
    for _, case in ipairs {
        { command = "play_till_sub_end", message = "No subtitle is currently playing" },
        { command = "sub_rewind", message = "No subtitle is currently visible" },
    } do
        local ctx = make_play_control_test_context()
        ctx.properties["sub-start"], ctx.properties["sub-end"] = nil, nil
        ctx.control[case.command]()
        h.assert_equals(ctx.state.commands, {})
        h.assert_equals(ctx.state.writes, {})
        h.assert_equals(ctx.state.observers, {})
        h.assert_equals(ctx.state.notification, case.message)
        h.assert_equals(ctx.state.notification_level, "error")
    end
end

--- Subtitle-step seeking preserves direction, optional pause, and stop-timer cancellation.
local function assert_playback_step_test_case(direction, pause)
    local ctx = make_play_control_test_context()
    ctx.control.play_till_sub_end()
    local callback = find_play_control_test_observer(ctx.state, "time-pos")
    ctx.state.commands, ctx.state.writes = {}, {}
    ctx.control.sub_seek(direction, pause)
    local step = "1"
    if direction == "backward" then step = "-1" end
    h.assert_equals(ctx.state.commands, { { "sub_seek", step }, { "seek", "0.015", "relative+exact" } })
    local expected_writes = {}
    if pause then expected_writes = { { "pause", "yes" } } end
    h.assert_equals(ctx.state.writes, expected_writes)
    h.assert_equals(ctx.state.observers, {})
    h.assert_equals(ctx.state.unobserved, { callback })
end

--- Both subtitle seek directions work with or without explicit pausing.
local function test_subtitle_step_commands()
    for _, direction in ipairs { "backward", "forward" } do
        for _, pause in ipairs { false, true } do
            assert_playback_step_test_case(direction, pause)
        end
    end
end

--- A timer stops at its own boundary without unregistering another timer on the same API.
local function test_pause_timer_instances_are_independent()
    local ctx = make_play_control_test_context()
    local first, second = pause_timer.new { mp = ctx.mp }, pause_timer.new { mp = ctx.mp }
    first.set_stop_time(10)
    second.set_stop_time(20)
    h.assert_equals(ctx.state.observers[first.check_stop], { name = "time-pos", format = "number" })
    first.check_stop("time-pos", 11)
    h.assert_equals(ctx.state.observers[first.check_stop], nil)
    h.assert_equals(ctx.state.observers[second.check_stop], { name = "time-pos", format = "number" })
    ctx.state.writes = {}
    second.check_stop("time-pos", 20)
    h.assert_equals(ctx.state.writes, {})
    second.check_stop("time-pos", 21)
    h.assert_equals(ctx.state.writes, { { "pause", "yes" } })
    h.assert_equals(ctx.state.observers, {})
end

--- Explicit stopping removes only the owner's registration and permits a fresh boundary.
local function test_pause_timer_stop_and_restart()
    local ctx = make_play_control_test_context()
    local first, second = pause_timer.new { mp = ctx.mp }, pause_timer.new { mp = ctx.mp }
    first.set_stop_time(10)
    second.set_stop_time(20)
    first.stop()
    h.assert_equals(ctx.state.unobserved, { first.check_stop })
    h.assert_equals(ctx.state.observers[first.check_stop], nil)
    h.assert_equals(ctx.state.observers[second.check_stop].name, "time-pos")
    first.set_stop_time(30)
    first.check_stop("time-pos", 25)
    h.assert_equals(ctx.state.writes, {})
    first.check_stop("time-pos", 31)
    h.assert_equals(ctx.state.writes, { { "pause", "yes" } })
    h.assert_equals(ctx.state.observers[second.check_stop].name, "time-pos")
    second.stop()
    h.assert_equals(ctx.state.observers, {})
end

--- Controls sharing one mpv API still retain separate waiting subtitles and pause timers.
local function test_playback_instances_keep_waiting_state()
    local ctx = make_play_control_test_context()
    ctx.control.play_till_next_sub_end()
    local first_callback = find_play_control_test_observer(ctx.state, "sub-text")
    ctx.properties["sub-text"], ctx.properties["sub-start"], ctx.properties["sub-end"] = "Next", 20, 23
    local second = play_control.new { mp = ctx.mp, notify = fixtures.make_notifier(ctx.state) }
    second.play_till_next_sub_end()
    first_callback()
    h.assert_equals(ctx.state.observers[first_callback], nil)
    local second_callback = find_play_control_test_observer(ctx.state, "sub-text")
    second_callback()
    h.assert_equals(ctx.state.observers[second_callback].name, "sub-text")
    local timer_callback = find_play_control_test_observer(ctx.state, "time-pos")
    second.sub_rewind()
    h.assert_equals(ctx.state.observers[timer_callback].name, "time-pos")
    ctx.control.sub_rewind()
    h.assert_equals(ctx.state.observers[timer_callback], nil)
end

--- Run playback-control and pause-timer regressions in both test environments.
local function run_tests()
    test_instances_own_command_tables()
    test_adjusted_playback_timings()
    test_waiting_for_next_subtitle()
    test_missing_subtitle_playback_commands()
    test_subtitle_step_commands()
    test_pause_timer_instances_are_independent()
    test_pause_timer_stop_and_restart()
    test_playback_instances_keep_waiting_state()
end

return { run_tests = run_tests }
