--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Note exporter tests.
]]

local fixtures = require('tests.fixtures')
local h = require('helpers')
local note_exporter = require('anki.note_exporter')
local ankiconnect = require('anki.ankiconnect')
local subtitles_observer = require('subtitles.observer')
local subtitle = require('subtitles.subtitle')
local base64 = require('utils.base64')
local forvo = require('utils.forvo')

--- Create a valid subtitle fixture for update tests.
local function make_valid_update_test_subtitle()
    return {
        text = "new sentence",
        secondary = "",
        --- Mark the subtitle fixture as valid.
        is_valid = function()
            return true
        end,
    }
end

--- Create an invalid subtitle fixture for update tests.
local function make_invalid_update_test_subtitle()
    return {
        --- Mark the subtitle fixture as invalid.
        is_valid = function()
            return false
        end,
    }
end

--- Create the fixed configuration used by exporter tests.
local function make_update_test_config()
    return fixtures.make_update_config {
        model_name = "Test model",
        note_tag = "",
    }
end

--- Return the stored sentence used by exporter tests.
local function make_exporter_test_stored_fields()
    return { SentKanji = 'old sentence' }
end

--- Create an initialized exporter for update tests.
local function make_update_test_exporter(result, jobs, subtitle, options)
    options = options or {}
    return note_exporter.new().init {
        ankiconnect = options.ankiconnect or fixtures.make_update_ankiconnect(result, make_exporter_test_stored_fields),
        quick_creation_opts = fixtures.make_quick_creation_options(result, { record_clear = true }),
        subs_observer = fixtures.make_subtitle_observer(result, subtitle or make_valid_update_test_subtitle()),
        encoder = fixtures.make_update_encoder(jobs, options.media),
        forvo = options.forvo or fixtures.make_forvo(result),
        cfg_mgr = fixtures.make_config_manager(options.config or make_update_test_config()),
        notify = fixtures.make_notifier(result),
        mp = options.mp,
    }
end

--- Deliver a media job's success path or failure to its registered callback.
local function complete_export_test_job(job, error)
    local path = job.filename
    if error then
        path = nil
    end
    job.callback(path, error)
end

--- Complete requested export jobs, leaving synchronously skipped jobs alone.
local function complete_export_test_media(jobs)
    for _, job in ipairs(jobs) do
        if job.filename then
            complete_export_test_job(job, nil)
        end
    end
end

--- Test that note writes wait for both media jobs.
local function test_update_notes_after_media_created()
    local result = { append_count = 0, clear_count = 0 }
    local jobs = {}
    make_update_test_exporter(result, jobs).update_notes({ 1 }, true)
    h.assert_equals(#jobs, 2)
    jobs[1].callback()
    h.assert_equals(result.append_count, 0)
    jobs[2].callback()
    h.assert_equals(result.append_count, 1)
    h.assert_equals(result.field_requests, { { 1 } })
    h.assert_equals(result.preview_reads, { 1 })
    h.assert_equals(result.note_id, 1)
    h.assert_equals(result.fields.SentKanji, "new sentence")
    h.assert_equals(result.fields.SentAudio, "[sound:audio.ogg]")
    h.assert_equals(result.fields.Image, '<img alt="snapshot" src="snapshot.avif">')
end

--- Test that invalid subtitles do not start an update.
local function test_invalid_subtitle_does_not_start_update()
    local result = { append_count = 0, clear_count = 0 }
    local jobs = {}
    make_update_test_exporter(result, jobs, make_invalid_update_test_subtitle()).update_notes({ 1 }, true)
    h.assert_equals(#jobs, 0)
    h.assert_equals(result.append_count, 0)
    h.assert_equals(result.clear_count, 0)
end

--- Test ordinary exports use the context to create and write note fields.
local function test_export_to_anki()
    local result = { append_count = 0, clear_count = 0 }
    local jobs = {}
    make_update_test_exporter(result, jobs).export_to_anki(false)
    h.assert_equals(#jobs, 2)
    h.assert_equals(jobs[1].started, true)
    h.assert_equals(jobs[2].started, true)
    h.assert_equals(result.fields, nil)
    h.assert_equals(result.clear_count, 1)
    jobs[2].callback('audio.ogg', nil)
    h.assert_equals(result.fields, nil)
    jobs[1].callback('snapshot.avif', nil)
    h.assert_equals(result.fields.SentKanji, "new sentence")
    h.assert_equals(result.fields.SentAudio, "[sound:audio.ogg]")
    h.assert_equals(result.fields.Image, '<img alt="snapshot" src="snapshot.avif">')
    h.assert_equals(result.tag, "")
    h.assert_equals(result.gui, false)
    h.assert_equals(result.clear_count, 1)
    h.assert_equals(result.add_count, 1)
end

--- Keep the subtitle and skip note creation until Anki's media directory is available.
local function test_export_without_media_directory()
    local result = { append_count = 0, clear_count = 0, media_dir_error = 'AnkiConnect unavailable' }
    local jobs = {}
    local subtitle = make_valid_update_test_subtitle()
    local exporter = make_update_test_exporter(result, jobs, subtitle)
    exporter.export_to_anki(false)
    h.assert_equals(#jobs, 0)
    h.assert_equals(result.fields, nil)
    h.assert_equals(result.clear_count, 0)
    h.assert_equals(result.notification, 'AnkiConnect unavailable')
    h.assert_equals(result.notification_level, 'error')

    result.media_dir_error = nil
    exporter.export_to_anki(false)
    h.assert_equals(#jobs, 2)
    complete_export_test_media(jobs)
    h.assert_equals(result.fields.SentKanji, 'new sentence')
    h.assert_equals(result.clear_count, 1)
end

--- Failed model lookup aborts before media creation and keeps the selection for a retry.
local function test_export_without_first_field()
    local result = { append_count = 0, clear_count = 0, first_field_error = 'Note type missing' }
    local jobs = {}
    local exporter = make_update_test_exporter(result, jobs)
    exporter.export_to_anki(false)
    h.assert_equals(#jobs, 0)
    h.assert_equals(result.fields, nil)
    h.assert_equals(result.clear_count, 0)
    h.assert_equals(result.notification, 'Note type missing')
    h.assert_equals(result.notification_level, 'error')
    result.first_field_error = nil
    exporter.export_to_anki(false)
    h.assert_equals(#jobs, 2)
    complete_export_test_media(jobs)
    h.assert_equals(result.fields.SentKanji, 'new sentence')
    h.assert_equals(result.clear_count, 1)
end

--- An unset first field still receives the fallback required by Anki.
local function test_export_populates_first_field()
    local result = { append_count = 0, clear_count = 0, first_field = 'Word' }
    local jobs = {}
    make_update_test_exporter(result, jobs).export_to_anki(false)
    complete_export_test_media(jobs)
    h.assert_equals(result.fields.Word, '[empty]')
    h.assert_equals(result.fields.SentKanji, 'new sentence')
end

--- Complete a failed media pair without allowing any note addition.
local function assert_export_media_failure(case)
    local result = { clear_count = 0 }
    local jobs = {}
    make_update_test_exporter(result, jobs).export_to_anki(false)
    complete_export_test_job(jobs[1], case.snapshot_error)
    h.assert_equals(result.fields, nil)
    h.assert_equals(result.notification, nil)
    complete_export_test_job(jobs[2], case.audio_error)
    h.assert_equals(result.fields, nil)
    h.assert_equals(result.add_count, nil)
    h.assert_equals(result.notification, 'Failed to create media: ' .. case.expected)
    h.assert_equals(result.notification_level, 'error')
    h.assert_equals(result.clear_count, 1)
end

--- Each requested media failure prevents adding a note after the entire batch finishes.
local function test_export_media_failures()
    for _, case in ipairs {
        { snapshot_error = 'image failed', expected = 'snapshot: image failed' },
        { audio_error = 'audio failed', expected = 'audio: audio failed' },
        {
            snapshot_error = 'image failed',
            audio_error = 'audio failed',
            expected = 'snapshot: image failed; audio: audio failed',
        },
    } do
        assert_export_media_failure(case)
    end
end

--- Skipped tracks count as completions without adding nonexistent filenames to fields.
local function test_export_skipped_media()
    for _, media in ipairs {
        { skip_snapshot = true },
        { skip_audio = true },
        { skip_snapshot = true, skip_audio = true },
    } do
        local result = { clear_count = 0 }
        local jobs = {}
        make_update_test_exporter(result, jobs, nil, { media = media }).export_to_anki(true)
        complete_export_test_media(jobs)
        h.assert_equals(result.add_count, 1)
        h.assert_equals(result.gui, true)
        h.assert_equals(result.fields.Image ~= nil, not media.skip_snapshot)
        h.assert_equals(result.fields.SentAudio ~= nil, not media.skip_audio)
        h.assert_equals(result.clear_count, 1)
    end
end

--- Completion writes the captured fields and tag without clearing a later subtitle selection.
local function test_export_captures_request()
    local result = { clear_count = 0 }
    local jobs = {}
    local subtitle = make_valid_update_test_subtitle()
    local config = make_update_test_config()
    config.note_tag = '%t'
    local properties = { filename = 'episode.mkv', ['time-pos'] = 65, duration = 200 }
    local exporter = make_update_test_exporter(result, jobs, subtitle, {
        config = config,
        mp = fixtures.make_mp_property_reader(properties),
    })
    exporter.export_to_anki(false)
    subtitle.text = 'later subtitle selection'
    properties['time-pos'] = 125
    complete_export_test_media(jobs)
    h.assert_equals(result.fields.SentKanji, 'new sentence')
    h.assert_equals(result.tag, '01m05s000ms')
    h.assert_equals(subtitle.text, 'later subtitle selection')
    h.assert_equals(result.clear_count, 1)
end

--- Return note and transport settings representing the original export profile.
local function make_export_destination_test_config()
    local config = make_update_test_config()
    config.deck_name = 'Original deck'
    config.allow_duplicates = false
    config.ankiconnect_url = 'http://original-server:8765'
    config.ankiconnect_api_key = 'original-key'
    return config
end

--- Verify the captured request payload and transport use the same original profile.
local function assert_export_destination_test_request(result)
    h.assert_equals(#result.note_requests, 1)
    local note = result.note_requests[1].params.note
    h.assert_equals(note.deckName, 'Original deck')
    h.assert_equals(note.modelName, 'Test model')
    h.assert_equals(note.options.allowDuplicate, false)
    h.assert_equals(note.fields.SentKanji, 'new sentence')
    h.assert_equals(result.transport_calls[1].url, 'http://original-server:8765')
    h.assert_equals(result.note_requests[1].key, 'original-key')
end

--- Pending exports retain their original destination when the live profile changes.
local function test_export_captures_destination()
    local result, jobs = {}, {}
    local config = make_export_destination_test_config()
    local client = fixtures.make_note_add_client(result, ankiconnect.new, config, {
        platform = fixtures.make_recording_anki_platform(result),
    })
    local exporter = make_update_test_exporter(result, jobs, nil, { config = config, ankiconnect = client })
    exporter.export_to_anki(false)
    h.assert_equals(result.note_requests, nil)
    config.deck_name = 'Different deck'
    config.model_name = 'Different model'
    config.allow_duplicates = true
    config.ankiconnect_url = 'http://different-server:8765'
    config.ankiconnect_api_key = 'different-key'
    complete_export_test_media(jobs)
    assert_export_destination_test_request(result)
end

--- Return settings whose field, pronunciation, and transport values change during an update.
local function make_transaction_update_test_config(append_media)
    return h.shallow_copy({
        append_media = append_media,
        disable_gui_browse = false,
        note_tag = 'original-tag',
        card_overwrite_safeguard = 1,
        use_forvo = 'always',
        vocab_field = 'Word',
        vocab_audio_field = 'VocabAudio',
        audio_format = 'opus',
        audio_codec = 'libopus',
        audio_extension = '.ogg',
        audio_bitrate = '32k',
    }, make_export_destination_test_config())
end

--- Build raw stored fields and endpoint-specific media directories for recording clients.
local function make_transaction_update_test_state(note_ids)
    local state = { target_ids = note_ids, stored_fields = {}, media_dirs = {
        ['http://original-server:8765'] = '/original-media',
        ['http://different-server:8765'] = '/different-media',
    } }
    for _, note_id in ipairs(note_ids) do
        state.stored_fields[note_id] = {
            SentKanji = 'stored sentence', SentAudio = '[sound:stored.ogg]',
            Image = '<img src="stored.jpg">', Word = 'word', VocabAudio = '',
        }
    end
    return state
end

--- Construct an exporter using real Anki request serialization with fake responses.
local function make_transaction_update_test_exporter(state, jobs, config, pronunciation)
    local cfg_mgr = fixtures.make_config_manager(config)
    local client = fixtures.make_update_transport_test_client(state, ankiconnect.new, cfg_mgr)
    return make_update_test_exporter(state, jobs, nil, {
        config = config, ankiconnect = client, forvo = pronunciation,
        mp = fixtures.make_mp_property_reader { filename = 'episode.mkv', ['time-pos'] = 65, duration = 200 },
    })
end

--- Change live settings after media starts without modifying captured providers.
local function change_transaction_update_test_profile(config)
    h.shallow_copy({
        sentence_field = 'DifferentSentence', audio_field = 'DifferentAudio', image_field = 'DifferentImage',
        model_name = 'Different model', append_media = not config.append_media,
        ankiconnect_url = 'http://different-server:8765', ankiconnect_api_key = 'different-key',
        disable_gui_browse = true, note_tag = 'different-tag', use_forvo = 'no',
        audio_format = 'mp3', audio_codec = 'libmp3lame', audio_extension = '.mp3', audio_bitrate = '96k',
    }, config)
end

--- Construct real Forvo behavior with recording page, download, encoding, and cleanup boundaries.
local function make_transaction_update_test_pronunciation(config)
    local state = { requests = {}, encodings = {}, removed = {}, warnings = {} }
    local page = string.format("Play('%s','%s');", base64.enc('clip.mp3'), base64.enc('clip.ogg'))
    local dependencies = fixtures.make_forvo_dependencies(state, {
        { status = 0, stdout = page }, { status = 0 },
    })
    return forvo.new(dependencies).init(fixtures.make_config_manager(config)), state
end

--- Assert original fields and pronunciation settings were used after a live profile change.
local function assert_transaction_update_test_write(state, pronunciation, note_id, append_media)
    local request = state.anki_requests[#state.anki_requests].request
    h.assert_equals(request.action, 'updateNoteFields')
    h.assert_equals(request.params.note.id, note_id)
    local fields = request.params.note.fields
    local expected = 'new sentence<br>stored sentence'
    if append_media then expected = 'stored sentence<br>new sentence' end
    h.assert_equals(fields.SentKanji, expected)
    h.assert_equals(fields.DifferentSentence, nil)
    -- Reverse merge keeps stored ancillary fields. Encoding must retain its settings in either order.
    if append_media then
        h.assert_equals(fields.VocabAudio, '[sound:forvo_word.ogg]')
    end
    h.assert_equals(pronunciation.requests[2][1], 'https://audio00.forvo.com/ogg/clip.ogg')
    local args = pronunciation.encodings[1]
    h.assert_equals(args[#args], '-o=/original-media/forvo_word.ogg')
    h.assert_equals(args[#args - 1], '--oacopts-add=b=32k')
    h.assert_equals(args[#args - 3], '--oac=libopus')
    h.assert_equals(pronunciation.warnings, {})
end

--- Assert every serialized read, write, tag, and Browser request uses its own captured provider.
local function assert_transaction_update_test_transport(state)
    for index, options in ipairs(state.anki_transport) do
        local record = state.anki_requests[index]
        local config = record.cfg_mgr.config()
        h.assert_equals(options.url, config.ankiconnect_url)
        h.assert_equals(options.request_json:match('"key"%s*:%s*"([^"]*)"'), config.ankiconnect_api_key)
        if record.request.action == 'findModelsByName' then
            h.assert_equals(record.request.params.modelNames, { config.model_name })
        elseif record.request.action == 'addTags' then
            h.assert_equals(record.request.params.tags, config.note_tag)
        end
    end
end

--- Exercise one entry point across both media and deferred Anki-write profile changes.
local function assert_transaction_update_test_case(case)
    local note_id = h.minutes_ago(0) + 1
    local state, jobs = make_transaction_update_test_state({ note_id }), {}
    local config = make_transaction_update_test_config(case.append_media)
    local pronunciation, pronunciation_state = make_transaction_update_test_pronunciation(config)
    local exporter = make_transaction_update_test_exporter(state, jobs, config, pronunciation)
    if case.command == 'update_notes' then
        exporter.update_notes({ note_id }, false)
    else
        exporter[case.command](false)
    end
    change_transaction_update_test_profile(config)
    complete_export_test_media(jobs)
    assert_transaction_update_test_write(state, pronunciation_state, note_id, case.append_media)
    config.ankiconnect_url, config.ankiconnect_api_key = 'http://third-server:8765', 'third-key'
    state.anki_write_callbacks[note_id](true, {}, nil)
    assert_transaction_update_test_transport(state)
    h.assert_equals(state.notification, 'Updated note: stored sentence.')
    h.assert_equals(state.clear_count, 2) -- Selection and quick options are cleared once each.
end

--- Verify direct, recent, and selected updates retain original settings through completion.
local function test_update_transactions_capture_profile()
    for _, case in ipairs {
        { command = 'update_notes', append_media = true },
        { command = 'update_notes', append_media = false },
        { command = 'update_last_note', append_media = true },
        { command = 'update_selected_note', append_media = true },
    } do
        assert_transaction_update_test_case(case)
    end
end

--- Complete one media pair without completing later requests' pending jobs.
local function complete_transaction_update_test_pair(jobs, first_index)
    complete_export_test_job(jobs[first_index], nil)
    complete_export_test_job(jobs[first_index + 1], nil)
end

--- Assert encoder, Forvo, and Anki providers remain paired within overlapping requests.
local function assert_concurrent_update_test_ownership(state, jobs)
    h.assert_equals(jobs[1].cfg_mgr == jobs[2].cfg_mgr, true)
    h.assert_equals(jobs[3].cfg_mgr == jobs[4].cfg_mgr, true)
    h.assert_equals(jobs[1].cfg_mgr == jobs[3].cfg_mgr, false)
    h.assert_equals(jobs[1].output_dir, '/original-media')
    h.assert_equals(jobs[3].output_dir, '/different-media')
    h.assert_equals(state.forvo_calls[1].cfg_mgr == jobs[1].cfg_mgr, true)
    h.assert_equals(state.forvo_calls[2].cfg_mgr == jobs[3].cfg_mgr, true)
    h.assert_equals(state.forvo_calls[1].output_dir, '/original-media')
    h.assert_equals(state.forvo_calls[2].output_dir, '/different-media')
end

--- Verify overlapping updates own different providers and pronunciation destinations.
local function test_update_transactions_isolate_media_directories()
    local state, jobs = make_transaction_update_test_state({ 11, 12 }), {}
    local config = make_transaction_update_test_config(true)
    local exporter = make_transaction_update_test_exporter(state, jobs, config)
    exporter.update_notes({ 11 }, true)
    config.ankiconnect_url, config.ankiconnect_api_key = 'http://different-server:8765', 'different-key'
    config.note_tag = 'second-tag'
    exporter.update_notes({ 12 }, true)
    complete_transaction_update_test_pair(jobs, 1)
    complete_transaction_update_test_pair(jobs, 3)
    assert_concurrent_update_test_ownership(state, jobs)
    h.assert_equals(state.notification, nil)
    state.anki_write_callbacks[12](true, {}, nil)
    state.anki_write_callbacks[11](true, {}, nil)
    assert_transaction_update_test_transport(state)
end

--- Build a file-transition fixture using the real subtitle selection implementation.
local function make_file_change_test_context()
    local observer = subtitles_observer.new()
    observer.import_subs { subtitle.make_subtitle('Old file selection', 20, 22) }
    local options = fixtures.make_quick_creation_options({}, { lines = 3, cards = 5 })
    local state, jobs = {}, {}
    local exporter = note_exporter.new().init {
        ankiconnect = fixtures.make_update_ankiconnect(state, make_exporter_test_stored_fields),
        quick_creation_opts = options,
        subs_observer = observer,
        encoder = fixtures.make_update_encoder(jobs),
        forvo = fixtures.make_forvo(),
        cfg_mgr = fixtures.make_config_manager(make_update_test_config()),
    }
    return exporter, observer, options, state, jobs
end

--- File changes discard the old selection and quick options without creating notes or media.
local function test_reset_for_file_change()
    local uninitialized = note_exporter.new()
    h.assert_equals(uninitialized.reset_for_file_change(), uninitialized)
    local exporter, observer, options, state, jobs = make_file_change_test_context()
    h.assert_equals(observer.get_timing('start'), 20)
    h.assert_equals(options:get_lines(), 3)
    h.assert_equals(exporter.reset_for_file_change(), exporter)
    h.assert_equals(observer.get_selected_primary_text(), '')
    h.assert_equals(observer.has_recorded_dialogs(), false)
    h.assert_equals(observer.get_timing('start'), -1)
    h.assert_equals(observer.get_timing('end'), -1)
    h.assert_equals(observer.user_altered(), false)
    h.assert_equals(options:get_lines(), nil)
    h.assert_equals(options:get_cards(), 1)
    h.assert_equals(state.add_count, nil)
    h.assert_equals(state.append_count, nil)
    h.assert_equals(#jobs, 0)
end

--- Run exporter tests.
local function run_tests()
    test_update_notes_after_media_created()
    test_invalid_subtitle_does_not_start_update()
    test_export_to_anki()
    test_export_without_media_directory()
    test_export_without_first_field()
    test_export_populates_first_field()
    test_export_media_failures()
    test_export_skipped_media()
    test_export_captures_request()
    test_export_captures_destination()
    test_update_transactions_capture_profile()
    test_update_transactions_isolate_media_directories()
    test_reset_for_file_change()
end

return {
    run_tests = run_tests,
}
