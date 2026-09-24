--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html
]]

local h = require('helpers')
local make_note_update_context = require('anki.note_update_context')
local fixtures = require('test_fixtures')

--- Create the public Anki note export command adapter.
local function make_exporter()
    local self = {}
    local pub = {}

    --- Return the current config.
    local function config()
        return self.cfg_mgr.config()
    end

    --- Update the specified notes with the current subtitle selection.
    function pub.update_notes(note_ids, overwrite)
        local request = {
            note_ids = note_ids,
            overwrite = overwrite,
            subtitle = self.note_update_context.collect_subtitle(),
        }
        if not request.subtitle:is_valid() then
            return self.notify("Nothing to export. Have you set the timings?", "warn", 2)
        end
        self.note_update_context.perform_update(request)
        return pub
    end

    --- Reload configuration before creating a card when configured.
    function pub.maybe_reload_config()
        if config().reload_config_before_card_creation then
            self.cfg_mgr.reload_from_disk()
        end
        return pub
    end

    --- Create and start media jobs for an ordinary note export.
    local function start_export_media(subtitle)
        self.encoder.set_output_dir(self.ankiconnect.get_media_dir_path())
        local snapshot = self.encoder.snapshot.create_job(subtitle)
        local audio = self.encoder.audio.create_job(subtitle, self.note_update_context.audio_padding())
        snapshot.run_async()
        audio.run_async()
        return snapshot, audio
    end

    --- Build note fields and ensure the first model field is populated.
    local function make_export_note_fields(subtitle, snapshot, audio)
        local first_field = self.ankiconnect.get_first_field(config().model_name)
        local note_fields = self.note_update_context.construct_note_fields {
            primary_text = subtitle['text'],
            secondary_text = subtitle['secondary'],
            snapshot_filename = snapshot.filename,
            audio_filename = audio.filename,
        }
        if not h.is_empty(first_field) and h.is_empty(note_fields[first_field]) then
            note_fields[first_field] = "[empty]"
        end
        return note_fields
    end

    --- Export the current subtitle as a new Anki note.
    function pub.export_to_anki(gui)
        pub.maybe_reload_config()
        local sub = self.subs_observer.collect_from_current()
        if not sub:is_valid() then
            return h.notify("Nothing to export.", "warn", 1)
        end
        if not gui and h.is_empty(sub['text']) then
            sub['text'] = string.format("mpvacious wasn't able to grab subtitles (%s)", os.time())
        end

        local snapshot, audio = start_export_media(sub)
        local note_fields = make_export_note_fields(sub, snapshot, audio)
        self.ankiconnect.add_note(note_fields, self.note_update_context.substitute_fmt(config().note_tag), gui)
        self.subs_observer.clear()
        return pub
    end

    --- Update the most recently created Anki notes.
    function pub.update_last_note(overwrite)
        local accept_notes_made_within_last_minutes = 10
        pub.maybe_reload_config()

        local n_cards = self.quick_creation_opts:get_cards()
        -- this now returns a table
        local last_note_ids = self.ankiconnect.get_last_note_ids(n_cards)
        n_cards = #last_note_ids

        --first element is the earliest
        if h.is_empty(last_note_ids) or last_note_ids[1] < h.minutes_ago(accept_notes_made_within_last_minutes) then
            return h.notify("Couldn't find the target note.", "warn", 2)
        end

        pub.update_notes(last_note_ids, overwrite)
        return pub
    end

    --- Update notes selected in the Anki Browser.
    function pub.update_selected_note(overwrite)
        pub.maybe_reload_config()

        local selected_note_ids = self.ankiconnect.get_selected_note_ids()

        if h.is_empty(selected_note_ids) then
            return h.notify("Couldn't find the target note(s). Did you select the notes you want in Anki?", "warn", 3)
        end

        if #selected_note_ids > config().card_overwrite_safeguard then
            return h.notify(
                    string.format(
                            "More than %i notes selected\nnot recommended, but you can change the limit in your config",
                            config().card_overwrite_safeguard
                    ),
                    "warn",
                    4
            )
        end

        pub.update_notes(selected_note_ids, overwrite)
        return pub
    end

    --- Initialize the exporter with its named dependencies.
    function pub.init(components)
        components.cfg_mgr.fail_if_not_ready()
        self.cfg_mgr = components.cfg_mgr
        self.ankiconnect = components.ankiconnect
        self.quick_creation_opts = components.quick_creation_opts
        self.subs_observer = components.subs_observer
        self.encoder = components.encoder
        self.forvo = components.forvo
        self.notify = components.notify or h.notify
        self.note_update_context = make_note_update_context.new({
            ankiconnect = self.ankiconnect,
            quick_creation_opts = self.quick_creation_opts,
            subs_observer = self.subs_observer,
            encoder = self.encoder,
            forvo = self.forvo,
            cfg_mgr = self.cfg_mgr,
        })
        return pub
    end

    return pub
end

------------------------------------------------------------
--- Tests: executed by both standalone and mpv-backed runners.

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
    return make_exporter().init {
        ankiconnect = fixtures.make_update_ankiconnect(result, make_exporter_test_stored_fields),
        quick_creation_opts = fixtures.make_quick_creation_options(result, { record_clear = true }),
        subs_observer = fixtures.make_subtitle_observer(result, subtitle or make_valid_update_test_subtitle()),
        encoder = fixtures.make_update_encoder(jobs),
        forvo = fixtures.make_forvo(),
        cfg_mgr = fixtures.make_config_manager(make_update_test_config()),
        notify = h.noop,
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

--- Run exporter tests.
local function run_tests()
    test_update_notes_after_media_created()
    test_invalid_subtitle_does_not_start_update()
    test_export_to_anki()
end

return {
    new = make_exporter,
    run_tests = run_tests,
}
