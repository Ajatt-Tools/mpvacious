--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

AnkiConnect tests
]]

local h = require('helpers')
local fixtures = require('tests.fixtures')
local ankiconnect = require('anki.ankiconnect')

--- Return the successful reordered multi-note response scenario.
local function make_successful_notes_fields_test_scenario()
    return {
        note_ids = { 1, 2 },
        result = {
            { noteId = 2, fields = { Sentence = { value = 'second' } } },
            { noteId = 1, fields = { Sentence = { value = 'first' }, Audio = { value = '' } } },
        },
        fields = { [1] = { Sentence = 'first', Audio = '' }, [2] = { Sentence = 'second' } },
    }
end

--- Create fresh scenarios for bulk note-field response handling.
local function make_notes_fields_test_scenarios()
    return {
        make_successful_notes_fields_test_scenario(),
        { note_ids = { 1 }, error = 'connection failed', expected_error = 'connection failed' },
        { note_ids = { 1 }, expected_error = 'AnkiConnect returned no requested notes' },
        { note_ids = { 1 }, result = {}, expected_error = 'AnkiConnect returned no requested notes' },
        { note_ids = { 1 }, result = 'invalid', expected_error = 'AnkiConnect returned no requested notes' },
        { note_ids = { 1 }, result = { {} }, expected_error = 'AnkiConnect returned note fields without a note ID' },
        { note_ids = { 1 }, result = { false }, expected_error = 'AnkiConnect returned note fields without a note ID' },
        { note_ids = { 1, 2 }, result = { { noteId = 1, fields = { Sentence = { value = 'first' } } } },
          expected_error = 'AnkiConnect returned no fields for note 2' },
        { note_ids = { 1 }, result = { { noteId = 1, fields = {} } },
          expected_error = 'AnkiConnect returned no fields for note 1' },
        { note_ids = { 1 }, result = { { noteId = 1, fields = false } },
          expected_error = 'AnkiConnect returned no fields for note 1' },
        { note_ids = { 1 }, result = { { noteId = 1, fields = { Sentence = false } } },
          expected_error = 'AnkiConnect returned invalid fields for note 1' },
        { note_ids = { 1 }, result = { { noteId = 1, fields = { Sentence = {} } } },
          expected_error = 'AnkiConnect returned invalid fields for note 1' },
    }
end

--- Assert one bulk field-fetch scenario without sending a network request.
local function assert_notes_fields_test_case(case)
    local state = {}
    local client = fixtures.make_note_fields_client(state, ankiconnect.new, case)
    local original_result = h.deep_copy(case.result)
    local fields, error = client.get_notes_fields(case.note_ids)
    h.assert_equals(state.requested_note_ids, case.note_ids)
    h.assert_equals(fields, case.fields)
    h.assert_equals(error, case.expected_error)
    h.assert_equals(case.result, original_result)
end

--- Exercise successful, failed, reordered, missing-note, and invalid-field responses.
local function test_get_notes_fields()
    for _, case in ipairs(make_notes_fields_test_scenarios()) do
        assert_notes_fields_test_case(case)
    end
end

local function make_get_media_dir_path_scenarios()
    return {
        { result = '/anki/media', expected_path = '/anki/media' },
        { error = 'AnkiConnect unavailable', expected_error = 'AnkiConnect unavailable' },
        { expected_error = 'AnkiConnect returned no media directory' },
        { result = '', expected_error = 'AnkiConnect returned no media directory' },
        { result = 42, expected_error = 'AnkiConnect returned no media directory' },
    }
end

--- Verify media directory requests distinguish valid paths from AnkiConnect failures.
local function test_get_media_dir_path()
    for _, case in ipairs(make_get_media_dir_path_scenarios()) do
        local client = ankiconnect.new()
        client.execute = function(options)
            h.assert_equals(options.request.action, 'getMediaDirPath')
            return options
        end
        client.parse_result = function()
            return case.result, case.error
        end
        local path, error = client.get_media_dir_path()
        h.assert_equals(path, case.expected_path)
        h.assert_equals(error, case.expected_error)
    end
end

local function make_get_note_fields_scenarios()
    return {
        { result = { { noteId = 123, fields = { Sentence = { value = 'text' }, Audio = { value = '' } } } },
          fields = { Sentence = 'text', Audio = '' } },
        { error = 'connection failed', expected_error = 'connection failed' },
        { expected_error = 'AnkiConnect returned no requested notes' },
        { result = {}, expected_error = 'AnkiConnect returned no requested notes' },
        { result = { {} }, expected_error = 'AnkiConnect returned note fields without a note ID' },
        { result = { { noteId = 123, fields = {} } },
          expected_error = 'AnkiConnect returned no fields for note 123' },
        { result = { { noteId = 123, fields = { Sentence = {} } } },
          expected_error = 'AnkiConnect returned invalid fields for note 123' },
    }
end

--- Verify singleton reads delegate to bulk reads and propagate failures.
local function test_get_note_fields()
    for _, case in ipairs(make_get_note_fields_scenarios()) do
        local state = {}
        local client = fixtures.make_note_fields_client(state, ankiconnect.new, case)
        local fields, error = client.get_note_fields(123)
        h.assert_equals(state.requested_note_ids, { 123 })
        h.assert_equals(fields, case.fields)
        h.assert_equals(error, case.expected_error)
    end
end

--- Forward a failed asynchronous Anki write to the update context.
local function test_append_media_reports_write_error()
    local logged_error
    local client = ankiconnect.new { logger = {
        --- Capture the expected write failure without alarming the test runner.
        error = function(message)
            logged_error = message
        end,
    } }
    local completed_result, completed_error
    --- Avoid a real Anki Browser request during this test.
    client.gui_browse = h.noop
    --- Deliver a failed write through the real response callback.
    client.execute = function(options)
        options.completion_fn(false, nil, 'write denied')
    end
    --- A failed write must never tag the note.
    client.add_tag = function()
        error('unexpected tag on failed write')
    end
    client.append_media(123, { Sentence = 'text' }, '', function(result, error)
        completed_result, completed_error = result, error
    end)
    h.assert_equals(completed_result, nil)
    h.assert_equals(completed_error, 'write denied')
    h.assert_equals(logged_error, 'Failed to update note 123: write denied')
end

--- Forward a successful AnkiConnect result and apply the note tag.
local function test_append_media_reports_write_result()
    local client = ankiconnect.new()
    local completed_result, completed_error, tagged_note_id
    client.gui_browse = h.noop
    client.parse_result = function()
        return 'updated', nil
    end
    client.execute = function(options)
        options.completion_fn(true, {}, nil)
    end
    client.add_tag = function(note_id)
        tagged_note_id = note_id
    end
    client.append_media(123, { Sentence = 'text' }, 'tag', function(result, error)
        completed_result, completed_error = result, error
    end)
    h.assert_equals(completed_result, 'updated')
    h.assert_equals(completed_error, nil)
    h.assert_equals(tagged_note_id, 123)
end

--- Run field-fetch contract tests without contacting Anki.
local function run_tests()
    test_get_notes_fields()
    test_get_media_dir_path()
    test_get_note_fields()
    test_append_media_reports_write_error()
    test_append_media_reports_write_result()
end

return {
    run_tests = run_tests,
}
