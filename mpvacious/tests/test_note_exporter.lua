--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Note exporter tests.
]]

local fixtures = require('tests.fixtures')
local h = require('helpers')
local note_exporter = require('anki.note_exporter')

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
local function make_update_test_exporter(result, jobs, subtitle)
    return note_exporter.new().init {
        ankiconnect = fixtures.make_update_ankiconnect(result, make_exporter_test_stored_fields),
        quick_creation_opts = fixtures.make_quick_creation_options(result, { record_clear = true }),
        subs_observer = fixtures.make_subtitle_observer(result, subtitle or make_valid_update_test_subtitle()),
        encoder = fixtures.make_update_encoder(jobs),
        forvo = fixtures.make_forvo(),
        cfg_mgr = fixtures.make_config_manager(make_update_test_config()),
        notify = fixtures.make_notifier(result),
    }
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
    h.assert_equals(result.fields.SentKanji, "new sentence")
    h.assert_equals(result.fields.SentAudio, "[sound:audio.ogg]")
    h.assert_equals(result.fields.Image, '<img alt="snapshot" src="snapshot.avif">')
    h.assert_equals(result.tag, "")
    h.assert_equals(result.gui, false)
    h.assert_equals(result.clear_count, 1)
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
    h.assert_equals(result.fields.SentKanji, 'new sentence')
    h.assert_equals(result.clear_count, 1)
end

--- Run exporter tests.
local function run_tests()
    test_update_notes_after_media_created()
    test_invalid_subtitle_does_not_start_update()
    test_export_to_anki()
    test_export_without_media_directory()
end

return {
    run_tests = run_tests,
}
