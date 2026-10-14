--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Guarded note-update workflow tests.
]]

local h = require("helpers")
local fixtures = require("tests.fixtures")
local workflow_module = require("anki.note_update_workflow")

local make_note_update_workflow = workflow_module.new

------------------------------------------------------------
-- Tests: executed by both standalone and mpv-backed runners.

--- Build a valid or invalid subtitle for workflow tests.
local function test_subtitle(is_valid)
    return {
        text = "current sentence",
        is_valid = function()
            return is_valid
        end,
    }
end

--- Record confirmation requests and cancellations in workflow tests.
local function make_test_confirmation(state)
    return {
        cancel = function()
            state.cancelled = state.cancelled + 1
        end,
        confirm = function(options)
            state.confirmation = options
        end,
    }
end

--- Return the execution request supplied by the context fake, separate from checking options.
local function make_prepared_update_test_request(request, target_notes)
    return {
        target_notes = target_notes,
        overwrite = request.overwrite,
        subtitle = request.subtitle,
    }
end

--- Record subtitle collection, request preparation, and writes in workflow tests.
local function make_test_context(state, subtitle, warning)
    return {
        collect_subtitle = function()
            return subtitle
        end,
        prepare_update_request = function(request)
            state.preparation_request = request
            state.warning_subtitle_text = request.subtitle.text
            if state.warning_error then
                return { error = state.warning_error }
            end
            state.prepared_request = make_prepared_update_test_request(request, state.target_notes)
            if request.options.check_recent_notes then
                return { warning = warning, request = state.prepared_request }
            end
            return { request = state.prepared_request }
        end,
        perform_update = function(request)
            state.performed = state.performed + 1
            state.performed_request = request
            return {} -- the context has a different API from the exporter
        end,
    }
end

--- Build context components that record workflow effects in `state`.
local function test_components(state, subtitle, warning)
    return {
        confirmation = make_test_confirmation(state),
        context = make_test_context(state, subtitle, warning),
        notify = fixtures.make_notifier(state),
        exporter = state.exporter,
    }
end

--- Build a fresh request, state, and workflow for one test scenario.
local function workflow_fixture(is_valid, warning)
    local state = {
        cancelled = 0,
        performed = 0,
        exporter = {},
        target_notes = { { note_id = 1, fields = {} } },
    }
    local request = { note_ids = { 1 }, overwrite = true, options = { check_recent_notes = not h.is_empty(warning) } }
    local workflow = make_note_update_workflow(test_components(state, test_subtitle(is_valid), warning))
    return state, request, workflow
end

--- Test that a replacement cancels the prior prompt before collecting a subtitle.
local function test_update_cancels_before_collecting()
    local events = {}
    local state = { cancelled = 0, performed = 0, exporter = {} }
    local components = test_components(state, test_subtitle(true), nil)
    components.confirmation.cancel = function()
        table.insert(events, "cancel")
    end
    components.context.collect_subtitle = function()
        h.assert_equals(events, { "cancel" })
        return test_subtitle(true)
    end
    local workflow = make_note_update_workflow(components)
    local request = { note_ids = { 1 }, overwrite = true, options = {} }
    h.assert_equals(workflow.update_notes(request), state.exporter)
    h.assert_equals(request.subtitle, nil)
    h.assert_equals(request.target_notes, nil)
end

--- Pass collected input to context preparation and reuse its execution request on acceptance.
local function test_update_passes_request_to_context()
    local state, request, workflow = workflow_fixture(true, "Different sentence.")
    local original = h.deep_copy(request)
    workflow.update_notes(request)
    h.assert_equals(rawequal(state.preparation_request, request), false)
    h.assert_equals(state.preparation_request.note_ids, request.note_ids)
    h.assert_equals(rawequal(state.preparation_request.note_ids, request.note_ids), false)
    h.assert_equals(state.preparation_request.overwrite, request.overwrite)
    h.assert_equals(state.preparation_request.options, request.options)
    h.assert_equals(state.preparation_request.subtitle.text, "current sentence")
    h.assert_equals(state.prepared_request.target_notes, state.target_notes)
    h.assert_equals(state.prepared_request.note_ids, nil)
    h.assert_equals(request, original)
    state.confirmation.on_accept()
    h.assert_equals(rawequal(state.performed_request, state.prepared_request), true)
end

--- Verify tunable notifications supply a finite, positive display duration.
local function assert_workflow_test_notification_duration(state)
    h.assert_equals(type(state.notification_duration), "number")
    h.assert_equals(state.notification_duration > 0 and state.notification_duration < math.huge, true)
end

--- Test invalid subtitles skip confirmation and updates.
local function test_invalid_subtitle_notifies_without_confirming()
    local state, request, workflow = workflow_fixture(false, nil)
    h.assert_equals(rawequal(workflow.update_notes(request), state.exporter), true)
    h.assert_equals(state.performed, 0)
    h.assert_equals(state.confirmation, nil)
    h.assert_equals(state.notification, "Nothing to export. Have you set the timings?")
    h.assert_equals(state.notification_level, "warn")
    assert_workflow_test_notification_duration(state)
end

--- Immediate updates return the exporter, not the update context's result.
local function test_immediate_update_returns_exporter()
    local state, request, workflow = workflow_fixture(true, nil)
    h.assert_equals(workflow.update_notes(request), state.exporter)
    h.assert_equals(state.performed, 1)
    h.assert_equals(state.performed_request.target_notes, state.target_notes)
end

--- Test warnings defer the update until explicit acceptance and preserve request data.
local function test_update_confirms_before_performing()
    local state, request, workflow = workflow_fixture(true, "Different sentence.")
    h.assert_equals(workflow.update_notes(request), state.exporter)
    h.assert_equals(state.performed, 0)
    h.assert_equals(state.confirmation.prompt, "Different sentence.\nUpdate this note anyway?")
    state.confirmation.on_cancel()
    h.assert_equals(state.performed, 0)
    state.confirmation.on_accept()
    h.assert_equals(state.performed, 1)
    h.assert_equals(state.performed_request.note_ids, nil)
    h.assert_equals(state.performed_request.subtitle:is_valid(), true)
    h.assert_equals(state.performed_request.target_notes, state.target_notes)
    h.assert_equals(state.warning_subtitle_text, "current sentence")
    h.assert_equals(request.subtitle, nil)
    h.assert_equals(request.target_notes, nil)
end

--- A failed target-field read aborts before confirmation or media creation.
local function test_update_fails_closed_on_read_error()
    local state, request, workflow = workflow_fixture(true, "Different sentence.")
    state.warning_error = "Could not read note 1"
    h.assert_equals(workflow.update_notes(request), state.exporter)
    h.assert_equals(state.confirmation, nil)
    h.assert_equals(state.performed, 0)
    h.assert_equals(state.notification, "Could not read note 1")
    h.assert_equals(state.notification_level, "error")
    assert_workflow_test_notification_duration(state)
end

--- A pending confirmation uses captured target IDs even if the caller changes its input list.
local function test_update_retains_captured_targets()
    local state, request, workflow = workflow_fixture(true, "Different sentence.")
    request.note_ids = { 1, 2 }
    state.target_notes = { { note_id = 1, fields = {} }, { note_id = 2, fields = {} } }
    h.assert_equals(workflow.update_notes(request), state.exporter)
    h.assert_equals(state.confirmation.prompt, "Different sentence.\nUpdate all 2 notes anyway?")
    request.note_ids[1] = 99
    table.insert(request.note_ids, 3)
    state.confirmation.on_accept()
    h.assert_equals(state.performed_request.note_ids, nil)
    h.assert_equals(state.performed_request.target_notes[1].note_id, 1)
    h.assert_equals(state.performed_request.target_notes[2].note_id, 2)
    h.assert_equals(state.performed_request.target_notes, state.target_notes)
end

--- Run workflow tests in both standalone and mpv-backed runners.
local function run_tests()
    test_update_cancels_before_collecting()
    test_update_passes_request_to_context()
    test_invalid_subtitle_notifies_without_confirming()
    test_immediate_update_returns_exporter()
    test_update_confirms_before_performing()
    test_update_fails_closed_on_read_error()
    test_update_retains_captured_targets()
end

return {
    run_tests = run_tests,
}
