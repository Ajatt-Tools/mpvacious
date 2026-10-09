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

--- Build valid, missing, and failed media-directory response scenarios.
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
        --- Verify the media-directory action without contacting Anki.
        client.execute = function(options)
            h.assert_equals(options.request.action, 'getMediaDirPath')
            return options
        end
        --- Return the scenario's media-directory response.
        client.parse_result = function()
            return case.result, case.error
        end
        local path, error = client.get_media_dir_path()
        h.assert_equals(path, case.expected_path)
        h.assert_equals(error, case.expected_error)
    end
end

--- Build singleton field-read scenarios with valid and malformed responses.
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

--- Return model lookup responses covering missing and malformed first fields.
local function make_first_field_test_cases()
    return {
        { result = { { flds = { { ord = 1, name = 'Other' }, { ord = 0, name = 'First' } } } }, field = 'First' },
        { error = 'connection failed', expected_error = 'connection failed' },
        { }, { result = {} }, { result = false }, { result = { false } },
        { result = { {} } }, { result = { { flds = false } } }, { result = { { flds = {} } } },
        { result = { { flds = { false } } } },
        { result = { { flds = { { ord = 1, name = 'Other' } } } } },
        { result = { { flds = { { ord = 0, name = '' } } } } },
        { result = { { flds = { { ord = 0, name = 42 } } } } },
    }
end

--- Return a field/error tuple without crashing on missing note types or malformed responses.
local function test_get_first_field()
    for _, case in ipairs(make_first_field_test_cases()) do
        local client = ankiconnect.new()
        --- Verify the requested model lookup without contacting Anki.
        client.execute = function(options)
            h.assert_equals(options.request.action, 'findModelsByName')
            h.assert_equals(options.request.params.modelNames, { 'Test' })
            return options
        end
        --- Return the scenario's model response and error.
        client.parse_result = function() return case.result, case.error end
        local field, error = client.get_first_field('Test')
        h.assert_equals(field, case.field)
        local expected_error = case.expected_error
        if not case.field and not expected_error then
            expected_error = 'AnkiConnect returned no valid first field for note type Test'
        end
        h.assert_equals(error, expected_error)
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
    --- Supply a successful parsed write result.
    client.parse_result = function()
        return 'updated', nil
    end
    --- Complete the fake write through the real response callback.
    client.execute = function(options)
        options.completion_fn(true, {}, nil)
    end
    --- Record the note receiving the post-write tag.
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

--- Captured job options select the destination for both direct and GUI additions.
local function test_add_note_captured_options()
    local current = { deck_name = 'Current deck', model_name = 'Current model', allow_duplicates = true }
    local captured = { deck_name = 'Captured deck', model_name = 'Captured model', allow_duplicates = false }
    for _, gui in ipairs { false, true } do
        local state = {}
        local client = fixtures.make_note_add_client(state, ankiconnect.new, current)
        local fields = { Sentence = 'captured sentence' }
        client.add_note { note_fields = fields, tag = 'source', gui = gui, opts = captured }
        local request = state.note_requests[1]
        local action = 'addNote'
        if gui then action = 'guiAddCards' end
        h.assert_equals(request.action, action)
        h.assert_equals(request.params.note.deckName, 'Captured deck')
        h.assert_equals(request.params.note.modelName, 'Captured model')
        h.assert_equals(request.params.note.options, { allowDuplicate = false, duplicateScope = 'deck' })
        h.assert_equals(request.params.note.fields, fields)
        h.assert_equals(request.params.note.tags, { 'source' })
    end
end

--- Jobs without explicit options use the client's current configuration.
local function test_add_note_default_options()
    local config = { deck_name = 'Current deck', model_name = 'Current model', allow_duplicates = true }
    local state = {}
    local client = fixtures.make_note_add_client(state, ankiconnect.new, config)
    client.add_note { note_fields = { Sentence = 'sentence' }, tag = '', gui = false }
    local note = state.note_requests[1].params.note
    h.assert_equals(note.deckName, 'Current deck')
    h.assert_equals(note.modelName, 'Current model')
    h.assert_equals(note.options.allowDuplicate, true)
    h.assert_equals(note.tags, {})
end

--- Captured transport settings override both the live URL and key, including a blank key.
local function test_execute_captured_transport()
    for _, case in ipairs { { key = 'original-key', expected_key = 'original-key' }, { key = '' } } do
        local state = {}
        local client = ankiconnect.new { platform = fixtures.make_recording_anki_platform(state) }
        client.init(fixtures.make_config_manager {
            ankiconnect_url = 'http://different-server:8765',
            ankiconnect_api_key = 'different-key',
        })
        local request = { action = 'version', version = 6 }
        client.execute {
            request = request,
            opts = { ankiconnect_url = 'http://original-server:8765', ankiconnect_api_key = case.key },
        }
        h.assert_equals(state.transport_calls[1].url, 'http://original-server:8765')
        h.assert_equals(request.key, case.expected_key)
        h.assert_equals(state.transport_calls[1].request_json:match('"key"%s*:%s*"([^"]*)"'), case.expected_key)
    end
end

--- Requests without captured transport settings follow the current configuration.
local function test_execute_default_transport()
    local config = { ankiconnect_url = 'http://original-server:8765', ankiconnect_api_key = 'original-key' }
    local state = {}
    local client = ankiconnect.new { platform = fixtures.make_recording_anki_platform(state) }
    client.init(fixtures.make_config_manager(config))
    config.ankiconnect_url = 'http://different-server:8765'
    config.ankiconnect_api_key = 'different-key'
    local request = { action = 'version', version = 6 }
    client.execute { request = request }
    h.assert_equals(state.transport_calls[1].url, 'http://different-server:8765')
    h.assert_equals(request.key, 'different-key')
end

--- Successful additions browse the original server and honor its Browser preference.
local function test_add_note_browses_captured_destination()
    for _, case in ipairs {
        { captured_disabled = false, current_disabled = false, expected_calls = 2 },
        { captured_disabled = false, current_disabled = true, expected_calls = 2 },
        { captured_disabled = true, current_disabled = false, expected_calls = 1 },
    } do
        local config = {
            deck_name = 'Original deck', model_name = 'Original model', allow_duplicates = false,
            ankiconnect_url = 'http://original-server:8765', ankiconnect_api_key = 'original-key',
            disable_gui_browse = case.captured_disabled,
        }
        local state = {}
        local client = fixtures.make_note_add_client(state, ankiconnect.new, config, {
            platform = fixtures.make_recording_anki_platform(state),
        })
        client.add_note {
            note_fields = { Sentence = 'text' }, tag = '', gui = false, opts = h.deep_copy(config),
        }
        config.ankiconnect_url = 'http://different-server:8765'
        config.ankiconnect_api_key = 'different-key'
        config.disable_gui_browse = case.current_disabled
        client.parse_result = function() return 123, nil end
        state.transport_calls[1].completion_fn(true, {}, nil)
        h.assert_equals(#state.transport_calls, case.expected_calls)
        h.assert_equals(#state.note_requests, case.expected_calls)
        if not case.captured_disabled then
            local request = state.note_requests[2]
            h.assert_equals(request.action, 'guiBrowse')
            h.assert_equals(request.params.query, 'nid:123')
            h.assert_equals(request.key, 'original-key')
            h.assert_equals(state.transport_calls[2].url, 'http://original-server:8765')
            h.assert_equals(state.transport_calls[2].request_json:match('"key"%s*:%s*"([^"]*)"'), 'original-key')
        end
    end
end

--- Ordinary Browser requests still use the current profile when no settings are supplied.
local function test_gui_browse_default_options()
    local config = { ankiconnect_url = 'http://current-server:8765', ankiconnect_api_key = 'current-key' }
    local state = {}
    local client = fixtures.make_note_add_client(state, ankiconnect.new, config, {
        platform = fixtures.make_recording_anki_platform(state),
    })
    client.gui_browse('nid:456')
    h.assert_equals(state.transport_calls[1].url, config.ankiconnect_url)
    h.assert_equals(state.note_requests[1].key, config.ankiconnect_api_key)
    h.assert_equals(state.note_requests[1].params.query, 'nid:456')
    config.disable_gui_browse = true
    client.gui_browse('nid:789')
    h.assert_equals(#state.transport_calls, 1)
end

--- Run field-fetch, note-add, and transport contract tests without contacting Anki.
local function run_tests()
    test_get_notes_fields()
    test_get_media_dir_path()
    test_get_note_fields()
    test_get_first_field()
    test_append_media_reports_write_error()
    test_append_media_reports_write_result()
    test_add_note_captured_options()
    test_add_note_default_options()
    test_execute_captured_transport()
    test_execute_default_transport()
    test_add_note_browses_captured_destination()
    test_gui_browse_default_options()
end

return {
    run_tests = run_tests,
}
