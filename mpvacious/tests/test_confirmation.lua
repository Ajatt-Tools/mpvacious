--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Confirmation lifecycle and reentrant cancellation tests.
]]

local mp = require("mp")
local input = require("mp.input")
local h = require("helpers")

local CONFIRMATION_TIMEOUT_SECONDS = 10
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

--- Return a fake mp API that records confirmation effects in `state`.
local function make_fake_mp_api(state)
    return {
        input = make_confirmation_test_input(state),
        msg = make_confirmation_test_msg(state),
        mp = make_confirmation_test_mp(state),
    }
end

--- Deliver the active prompt's delayed close event in confirmation tests.
local function close_confirmation_test_input(state)
    (state.closing_options or state.options).closed()
end

--- Run one scheduled confirmation-test task after the old handler closes.
local function run_confirmation_test_scheduled_open(state)
    state.timers[#state.timers].callback()
end

--- Run one confirmation-test timer by creation order.
local function run_confirmation_test_timer(state, index)
    state.timers[index].callback()
end

--- Return the confirmation-test timeout callback recorded in `state`.
local function get_confirmation_test_timeout(state)
    return state.timers[1].callback
end

--- Start one confirmation and return its recorded state plus controller.
local function confirmation_fixture(prompt)
    local state = { accepted = 0, cancelled = 0, terminated = 0, timer_kills = 0, timers = {} }
    local confirmation = make_confirmation(make_fake_mp_api(state))
    confirmation.confirm({
        prompt = prompt or "Warning\nProceed?",
        on_accept = function()
            state.accepted = state.accepted + 1
        end,
        on_cancel = function()
            state.cancelled = state.cancelled + 1
        end,
    })
    return state, confirmation
end

--- Test prompt configuration and logging.
local function test_confirmation_prompt()
    local state = confirmation_fixture("Different sentence.\nUpdate anyway?")
    h.assert_equals(state.options.items, { "Yes", "No" })
    h.assert_equals(state.options.default_item, 2)
    h.assert_equals(state.options.prompt, "Different sentence.\nUpdate anyway?")
    h.assert_equals(state.warning, state.options.prompt)
    h.assert_equals(state.timers[1].seconds, CONFIRMATION_TIMEOUT_SECONDS)
end

--- Test that acceptance resolves once despite a later closed callback.
local function test_confirmation_accepts_once()
    local state = confirmation_fixture()
    state.options.submit(1)
    close_confirmation_test_input(state)
    h.assert_equals({ state.accepted, state.cancelled }, { 1, 0 })
    h.assert_equals({ state.terminated, state.timer_kills }, { 1, 1 })
end

--- Test explicit No and timeout cancellation paths.
local function assert_confirmation_canceled(state, expected_terminations)
    h.assert_equals({ state.accepted, state.cancelled }, { 0, 1 })
    h.assert_equals({ state.terminated, state.timer_kills }, { expected_terminations, 1 })
    h.assert_equals(state.cancelled, 1)
end

--- Run one confirmation-test cancellation scenario.
local function run_confirmation_test_cancellation_scenario(scenario)
    local state, confirmation = confirmation_fixture()
    scenario.resolve(state, confirmation)
    assert_confirmation_canceled(state, scenario.terminate)
    confirmation.cancel()
end

--- Return cancellation scenarios for No, timeout, input closure, and explicit cancellation.
local function make_confirmation_cancellation_test_cases()
    return {
        { terminate = 1, resolve = function(state) state.options.submit(2) end },
        { terminate = 1, resolve = function(state) get_confirmation_test_timeout(state)() end },
        { terminate = 0, resolve = close_confirmation_test_input },
        { terminate = 1, resolve = function(_, confirmation) confirmation.cancel() end },
    }
end

--- Test explicit No and timeout cancellation paths.
local function test_confirmation_cancellation_paths()
    for _, scenario in ipairs(make_confirmation_cancellation_test_cases()) do
        run_confirmation_test_cancellation_scenario(scenario)
    end
end

--- Confirm a replacement request and return its state alongside stale first callbacks.
local function replacement_fixture()
    local first, confirmation = confirmation_fixture("First")
    local first_options = first.options
    local first_timeout = get_confirmation_test_timeout(first)
    local second_state = { accepted = 0, cancelled = 0 }
    confirmation.confirm({
        prompt = "Second",
        on_accept = function()
            second_state.accepted = second_state.accepted + 1
        end,
        on_cancel = function()
            second_state.cancelled = second_state.cancelled + 1
        end,
    })
    return first, confirmation, first_options, first_timeout, second_state
end

--- Test that replacing a request cancels it and opens the replacement after closed.
local function test_confirmation_supersedes_and_cancels()
    local first, confirmation, first_options, first_timeout, second_state = replacement_fixture()
    h.assert_equals(first.cancelled, 1)
    close_confirmation_test_input(first)
    run_confirmation_test_scheduled_open(first)
    h.assert_equals(first.options.prompt, "Second")
    first_options.submit(1)
    first_options.submit(2)
    first_options.closed()
    first_timeout()
    h.assert_equals({ first.accepted, second_state.accepted, second_state.cancelled }, { 0, 0, 0 })
    confirmation.cancel()
    h.assert_equals(second_state.cancelled, 1)
end

--- Test that a stale delayed opener cannot replace an active mpv 0.41 input handler.
local function test_stale_delayed_open_is_inert()
    local first, confirmation = confirmation_fixture("First")
    confirmation.confirm({ prompt = "Second", on_accept = h.noop, on_cancel = h.noop })
    close_confirmation_test_input(first)
    confirmation.confirm({ prompt = "Third", on_accept = h.noop, on_cancel = h.noop })
    confirmation.confirm({ prompt = "Fourth", on_accept = h.noop, on_cancel = h.noop })
    run_confirmation_test_timer(first, 2)
    h.assert_equals(first.options.prompt, "Third")
    close_confirmation_test_input(first)
    run_confirmation_test_scheduled_open(first)
    h.assert_equals(first.options.prompt, "Fourth")
end

--- Queue a test request whose cancellation submits a counted replacement.
local function queue_reentrant_confirmation_test_request(confirmation, counts, scenario)
    confirmation.confirm({
        prompt = scenario.prompt,
        on_accept = h.noop,
        on_cancel = function()
            counts[scenario.cancel_key] = counts[scenario.cancel_key] + 1
            confirmation.confirm({
                prompt = scenario.replacement_prompt,
                on_accept = function()
                    counts[scenario.accept_key] = counts[scenario.accept_key] + 1
                end,
                on_cancel = h.noop,
            })
        end,
    })
end

--- Keep a new request queued from an active request's cancellation callback.
local function test_reentrant_active_cancellation()
    local state = { terminated = 0, timer_kills = 0, timers = {}, cancelled = 0, accepted = 0 }
    local confirmation = make_confirmation(make_fake_mp_api(state))
    queue_reentrant_confirmation_test_request(confirmation, state, {
        prompt = "First",
        cancel_key = "cancelled",
        replacement_prompt = "New",
        accept_key = "accepted",
    })
    local stale_options = state.options
    confirmation.cancel()
    h.assert_equals(state.cancelled, 1)
    close_confirmation_test_input(state)
    run_confirmation_test_scheduled_open(state)
    h.assert_equals(state.options.prompt, "New")
    stale_options.submit(1)
    state.options.submit(1)
    h.assert_equals({ state.cancelled, state.accepted }, { 1, 1 })
end

--- Replacing a pending request must not discard a newer reentrant request.
local function test_reentrant_pending_replacement()
    local state, confirmation = confirmation_fixture("First")
    local counts = { second = 0, third = 0, fourth = 0 }
    queue_reentrant_confirmation_test_request(confirmation, counts, {
        prompt = "Second",
        cancel_key = "second",
        replacement_prompt = "Fourth",
        accept_key = "fourth",
    })
    confirmation.confirm({
        prompt = "Third",
        on_accept = h.noop,
        on_cancel = function() counts.third = counts.third + 1 end,
    })
    close_confirmation_test_input(state)
    run_confirmation_test_scheduled_open(state)
    h.assert_equals(state.options.prompt, "Fourth")
    state.options.submit(1)
    h.assert_equals({ counts.second, counts.third, counts.fourth }, { 1, 1, 1 })
end

--- Public cancellation preserves a request queued by the pending callback.
local function test_reentrant_pending_cancellation()
    local state, confirmation = confirmation_fixture("First")
    local counts = { old = 0, new = 0 }
    queue_reentrant_confirmation_test_request(confirmation, counts, {
        prompt = "Old",
        cancel_key = "old",
        replacement_prompt = "New",
        accept_key = "new",
    })
    confirmation.cancel()
    close_confirmation_test_input(state)
    run_confirmation_test_scheduled_open(state)
    h.assert_equals(state.options.prompt, "New")
    state.options.submit(1)
    h.assert_equals({ counts.old, counts.new }, { 1, 1 })
end

--- Smoke-test real mp and mp.input APIs without producing a test-run warning.
local function test_real_mp_api()
    local confirmation = make_confirmation({ input = input, msg = { warn = h.noop }, mp = mp })
    confirmation.confirm({ prompt = "Test confirmation", on_accept = h.noop, on_cancel = h.noop })
    confirmation.cancel()
end

--- Run confirmation module tests.
local function run_tests()
    test_confirmation_prompt()
    test_confirmation_accepts_once()
    test_confirmation_cancellation_paths()
    test_confirmation_supersedes_and_cancels()
    test_stale_delayed_open_is_inert()
    test_reentrant_active_cancellation()
    test_reentrant_pending_replacement()
    test_reentrant_pending_cancellation()
    test_real_mp_api()
end

return {
    run_tests = run_tests,
}
