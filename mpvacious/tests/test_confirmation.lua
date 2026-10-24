--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Confirmation lifecycle, busy rejection, and stale callback tests.
]]

local mp = require("mp")
local input = require("mp.input")
local h = require("helpers")

local confirmation_module = require("menu.confirmation")

local make_confirmation = confirmation_module.new

------------------------------------------------------------
-- Tests: executed by both standalone and mpv-backed runners.

--- Return the fake mp.input API that records prompt options in `state`.
local function make_confirmation_test_input(state)
    return {
        select = function(options)
            state.options = options
        end,
        terminate = function()
            state.terminated = state.terminated + 1
            state.closing_options = state.options
            if state.close_synchronously then
                state.closing_options.closed()
            end
        end,
    }
end

--- Return the fake mp.msg API that records the warning message in `state`.
local function make_confirmation_test_msg(state)
    return {
        warn = function(message)
            state.warning = message
        end,
    }
end

--- Return the fake timer API that records callbacks in `state`.
local function make_confirmation_test_mp(state)
    return {
        add_timeout = function(seconds, callback)
            local timer = { seconds = seconds, callback = callback, killed = false }
            table.insert(state.timers, timer)
            return {
                kill = function()
                    timer.killed = true
                    state.timer_kills = state.timer_kills + 1
                end,
            }
        end,
    }
end

--- Record nonempty notifications using the same empty-message contract as h.notify.
local function make_confirmation_test_notifier(state)
    state.notifications = {}
    return function(message, level, duration)
        if not h.is_non_empty_str(message) then
            return
        end
        table.insert(state.notifications, { message = message, level = level, duration = duration })
    end
end

--- Return a fake mp API that records confirmation effects in `state`.
local function make_fake_mp_api(state)
    return {
        input = make_confirmation_test_input(state),
        msg = make_confirmation_test_msg(state),
        mp = make_confirmation_test_mp(state),
        notify = make_confirmation_test_notifier(state),
    }
end

--- Deliver the active prompt's delayed close event in confirmation tests.
local function close_confirmation_test_input(state)
    (state.closing_options or state.options).closed()
end

--- Return the confirmation-test timeout callback recorded in `state`.
local function get_confirmation_test_timeout(state)
    return state.timers[1].callback
end

--- Start one confirmation and return its recorded state plus controller.
local function confirmation_fixture(prompt)
    local state = { accepted = 0, terminated = 0, timer_kills = 0, timers = {} }
    local confirmation = make_confirmation(make_fake_mp_api(state))
    confirmation.confirm({
        prompt = prompt or "Warning\nProceed?",
        on_accept = function()
            h.assert_equals({ state.terminated, state.timer_kills }, { 1, 1 })
            h.assert_equals(state.timers[1].killed, true)
            state.accepted = state.accepted + 1
        end,
    })
    return state, confirmation
end

--- Test prompt configuration and logging.
local function test_confirmation_prompt()
    local state, confirmation = confirmation_fixture("Different sentence.\nUpdate anyway?")
    h.assert_equals(state.options.items, { "Yes", "No" })
    h.assert_equals(state.options.default_item, 2)
    h.assert_equals(state.options.prompt, "Different sentence.\nUpdate anyway?")
    h.assert_equals(state.warning, state.options.prompt)
    h.assert_equals(state.timers[1].seconds, confirmation.get_confirmation_timeout())
    h.assert_equals(state.timers[1].seconds > 0 and state.timers[1].seconds < math.huge, true)
end

--- Test that acceptance resolves once despite a later closed callback.
local function test_confirmation_accepts_once()
    local state, confirmation = confirmation_fixture()
    state.options.submit(1)
    state.options.submit(1)
    state.options.submit(2)
    get_confirmation_test_timeout(state)()
    close_confirmation_test_input(state)
    close_confirmation_test_input(state)
    confirmation.cancel("Must not report cancellation after acceptance.")
    h.assert_equals(state.accepted, 1)
    h.assert_equals({ state.terminated, state.timer_kills }, { 1, 1 })
    h.assert_equals(state.notifications, {})
end

--- Callback failures must not prevent timer cleanup or prompt closure.
local function test_acceptance_failure_closes_prompt()
    local state = { terminated = 0, timer_kills = 0, timers = {} }
    local confirmation = make_confirmation(make_fake_mp_api(state))
    confirmation.confirm { prompt = "Failure", on_accept = h.as_callback(error, "acceptance failed") }
    local success, failure = pcall(state.options.submit, 1)
    h.assert_equals(success, false)
    h.assert_equals(h.is_substr(failure, "acceptance failed"), true)
    h.assert_equals({ state.terminated, state.timer_kills }, { 1, 1 })
    state.options.submit(1)
    close_confirmation_test_input(state)
    confirmation.confirm { prompt = "Next", on_accept = h.noop }
    h.assert_equals(state.options.prompt, "Next")
end

--- Check cancellation messages without hard-coding their tunable display durations.
local function assert_confirmation_test_notifications(state, messages)
    h.assert_equals(h.map(state.notifications, function(notification) return notification.message end), messages)
    for _, notification in ipairs(state.notifications) do
        h.assert_equals(notification.level, "info")
        h.assert_equals(type(notification.duration), "number")
        h.assert_equals(notification.duration > 0 and notification.duration < math.huge, true)
    end
end

--- Test explicit No and timeout cancellation paths.
local function assert_confirmation_canceled(state, expected_terminations)
    h.assert_equals(state.accepted, 0)
    h.assert_equals({ state.terminated, state.timer_kills }, { expected_terminations, 1 })
end

--- Run one confirmation-test cancellation scenario.
local function run_confirmation_test_cancellation_scenario(scenario)
    local state, confirmation = confirmation_fixture()
    scenario.resolve(state, confirmation)
    assert_confirmation_canceled(state, scenario.terminate)
    state.options.submit(1)
    close_confirmation_test_input(state)
    get_confirmation_test_timeout(state)()
    state.options.submit(2)
    confirmation.cancel("Must not report cancellation twice.")
    assert_confirmation_canceled(state, scenario.terminate)
    local messages = {}
    if scenario.message then messages = { scenario.message } end
    assert_confirmation_test_notifications(state, messages)
end

--- Return cancellation scenarios for No, timeout, input closure, and explicit cancellation.
local function make_confirmation_cancellation_test_cases()
    return {
        { terminate = 1, resolve = function(state) state.options.submit(2) end, message = "Cancelled by the user." },
        { terminate = 1, resolve = function(state) get_confirmation_test_timeout(state)() end },
        { terminate = 0, resolve = close_confirmation_test_input },
        { terminate = 1, resolve = function(_, confirmation) confirmation.cancel() end },
        {
            terminate = 1,
            resolve = function(_, confirmation) confirmation.cancel("Video changed.") end,
            message = "Video changed.",
        },
    }
end

--- Idle cancellation and empty reasons must not produce messages.
local function test_confirmation_silent_cancellation()
    local state = { timers = {} }
    local confirmation = make_confirmation(make_fake_mp_api(state))
    confirmation.cancel("Nothing is pending.")
    h.assert_equals(state.notifications, {})
    local active_state, active_confirmation = confirmation_fixture()
    active_confirmation.cancel("")
    h.assert_equals(active_state.accepted, 0)
    h.assert_equals({ active_state.terminated, active_state.timer_kills }, { 1, 1 })
    h.assert_equals(active_state.notifications, {})
end

--- Test explicit No and timeout cancellation paths.
local function test_confirmation_cancellation_paths()
    for _, scenario in ipairs(make_confirmation_cancellation_test_cases()) do
        run_confirmation_test_cancellation_scenario(scenario)
    end
end

--- Reject malformed incoming requests before allocating a timer or occupying the controller.
local function assert_invalid_confirmation_options_test_case(case)
    local state = { terminated = 0, timer_kills = 0, timers = {} }
    local confirmation = make_confirmation(make_fake_mp_api(state))
    local success, message = pcall(confirmation.confirm, case.options)
    h.assert_equals(success, false)
    h.assert_equals(h.is_substr(message, "Expected type " .. case.expected .. ", got "), true)
    h.assert_equals(state.timers, {})
    h.assert_equals(state.options, nil)
    h.assert_equals(state.warning, nil)
    h.assert_equals(state.notifications, {})
    confirmation.confirm { prompt = "Valid", on_accept = h.noop }
    h.assert_equals(state.options.prompt, "Valid")
    h.assert_equals(#state.timers, 1)
end

--- A new prompt requires a table, string prompt, and acceptance function.
local function test_confirmation_argument_types()
    for _, case in ipairs {
        { expected = "table" },
        { options = false, expected = "table" },
        { options = "Prompt", expected = "table" },
        { options = {}, expected = "string" },
        { options = { prompt = false, on_accept = h.noop }, expected = "string" },
        { options = { prompt = "Prompt" }, expected = "function" },
        { options = { prompt = "Prompt", on_accept = {} }, expected = "function" },
    } do
        assert_invalid_confirmation_options_test_case(case)
    end
end

--- Ignore repeated prompt requests without closing, resolving, or queueing the first.
local function test_confirmation_ignores_requests_while_active()
    local state, confirmation = confirmation_fixture("First")
    local first_options = state.options
    for _ = 1, 3 do
        confirmation.confirm { prompt = "Ignored", on_accept = h.as_callback(error, "ignored prompt was accepted") }
    end
    h.assert_equals(pcall(confirmation.confirm, nil), true)
    h.assert_equals(rawequal(state.options, first_options), true)
    h.assert_equals({ #state.timers, state.terminated, state.timer_kills }, { 1, 0, 0 })
    state.options.submit(1)
    close_confirmation_test_input(state)
    h.assert_equals(state.accepted, 1)
    h.assert_equals(#state.timers, 1)
    h.assert_equals(state.options.prompt, "First")
    h.assert_equals(state.notifications, {})
end

--- Old input and timeout callbacks must not resolve or close a newly opened prompt.
local function assert_stale_confirmation_test_callbacks(state, old_options, old_timeout)
    local counts = { state.accepted, state.terminated, state.timer_kills }
    local notifications = h.deep_copy(state.notifications)
    old_options.submit(1)
    old_options.submit(2)
    old_options.closed()
    old_timeout()
    h.assert_equals({ state.accepted, state.terminated, state.timer_kills }, counts)
    h.assert_equals(state.notifications, notifications)
end

--- Synchronous input closure releases the controller without affecting a later request.
local function test_synchronous_closure_releases_request()
    local state = { accepted = 0, terminated = 0, timer_kills = 0, timers = {}, close_synchronously = true }
    local confirmation = make_confirmation(make_fake_mp_api(state))
    confirmation.confirm {
        prompt = "First",
        on_accept = function() state.accepted = state.accepted + 1 end,
    }
    local old_options, old_timeout = state.options, get_confirmation_test_timeout(state)
    state.options.submit(1)
    h.assert_equals({ state.accepted, state.terminated, state.timer_kills }, { 1, 1, 1 })
    confirmation.confirm { prompt = "Next", on_accept = h.noop }
    assert_stale_confirmation_test_callbacks(state, old_options, old_timeout)
    confirmation.confirm { prompt = "Ignored", on_accept = h.noop }
    h.assert_equals(state.options.prompt, "Next")
    confirmation.cancel()
    h.assert_equals({ state.terminated, state.timer_kills }, { 2, 2 })
end

--- Reject requests while closing and accept a fresh invocation only after closed.
local function run_confirmation_test_closing_scenario(resolve_request)
    local state, confirmation = confirmation_fixture("First")
    local old_options, old_timeout = state.options, get_confirmation_test_timeout(state)
    resolve_request(state, confirmation)
    local accepted = state.accepted
    h.assert_equals(pcall(confirmation.confirm, nil), true)
    confirmation.confirm { prompt = "Ignored", on_accept = h.as_callback(error, "closing prompt was replaced") }
    h.assert_equals(rawequal(state.options, old_options), true)
    h.assert_equals(#state.timers, 1)
    close_confirmation_test_input(state)
    confirmation.confirm {
        prompt = "Next",
        on_accept = function() state.accepted = state.accepted + 1 end,
    }
    h.assert_equals(state.options.prompt, "Next")
    h.assert_equals(#state.timers, 2)
    assert_stale_confirmation_test_callbacks(state, old_options, old_timeout)
    state.options.submit(1)
    h.assert_equals(state.accepted, accepted + 1)
end

--- Cover closing after Yes, No, timeout, and explicit cancellation.
local function test_confirmation_ignores_requests_while_closing()
    for _, resolve_request in ipairs {
        function(state) state.options.submit(1) end,
        function(state) state.options.submit(2) end,
        function(state) get_confirmation_test_timeout(state)() end,
        function(_, confirmation) confirmation.cancel("Video changed.") end,
    } do
        run_confirmation_test_closing_scenario(resolve_request)
    end
end

--- Smoke-test real mp and mp.input APIs without producing a test-run warning.
local function test_real_mp_api()
    local confirmation = make_confirmation({ input = input, msg = { warn = h.noop }, mp = mp })
    confirmation.confirm({ prompt = "Test confirmation", on_accept = h.noop })
    confirmation.cancel()
end

--- Run confirmation module tests.
local function run_tests()
    test_confirmation_prompt()
    test_confirmation_accepts_once()
    test_acceptance_failure_closes_prompt()
    test_confirmation_cancellation_paths()
    test_confirmation_silent_cancellation()
    test_confirmation_argument_types()
    test_confirmation_ignores_requests_while_active()
    test_confirmation_ignores_requests_while_closing()
    test_synchronous_closure_releases_request()
    test_real_mp_api()
end

return {
    run_tests = run_tests,
}
