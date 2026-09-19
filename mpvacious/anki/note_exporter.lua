--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html
]]

local h = require('helpers')
local make_note_update_context = require('anki.note_update_context')

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

        self.encoder.set_output_dir(self.ankiconnect.get_media_dir_path())
        local snapshot = self.encoder.snapshot.create_job(sub)
        local audio = self.encoder.audio.create_job(sub, self.note_update_context.audio_padding())

        snapshot.run_async()
        audio.run_async()

        local first_field = self.ankiconnect.get_first_field(config().model_name)
        local note_fields = self.note_update_context.construct_note_fields {
            primary_text = sub['text'],
            secondary_text = sub['secondary'],
            snapshot_filename = snapshot.filename,
            audio_filename = audio.filename,
        }

        if not h.is_empty(first_field) and h.is_empty(note_fields[first_field]) then
            note_fields[first_field] = "[empty]"
        end

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

--- Create a deferred media job that records its completion callback.
local function make_exporter_test_pending_media_job(filename, jobs)
    local job = { filename = filename }
    --- Record that the media job started.
    function job.run_async()
        job.started = true
    end
    --- Register the media-job completion callback.
    function job.on_finish(callback)
        job.callback = callback
        return job
    end
    table.insert(jobs, job)
    return job
end

--- Create a media-job factory for the supplied filename.
local function make_exporter_test_media_job_factory(filename, jobs)
    --- Create one pending media job.
    return function()
        return make_exporter_test_pending_media_job(filename, jobs)
    end
end

--- Create an encoder test double that records media jobs.
local function make_update_test_encoder(jobs)
    return {
        set_output_dir = h.noop,
        snapshot = { create_job = make_exporter_test_media_job_factory("snapshot.avif", jobs) },
        audio = { create_job = make_exporter_test_media_job_factory("audio.ogg", jobs) },
    }
end

--- Create the fixed configuration used by exporter tests.
local function make_update_test_config()
    return {
        sentence_field = "SentKanji",
        audio_field = "SentAudio",
        audio_template = "[sound:%s]",
        image_field = "Image",
        image_template = '<img alt="snapshot" src="%s">',
        audio_padding = 0,
        miscinfo_enable = false,
        model_name = "Test model",
        note_tag = "",
    }
end

--- Create an AnkiConnect test double that records updated fields.
local function make_update_test_ankiconnect(result)
    return {
        --- Return the test media directory.
        get_media_dir_path = function()
            return "/tmp"
        end,
        --- Return stored fields for an update target.
        get_note_fields = function()
            return { SentKanji = "old sentence" }
        end,
        --- Return the model's first field name.
        get_first_field = function()
            return "SentKanji"
        end,
        --- Record fields written by an update.
        append_media = function(note_id, fields)
            result.append_count = result.append_count + 1
            result.note_id = note_id
            result.fields = fields
        end,
        --- Record fields created by an ordinary export.
        add_note = function(fields, tag, gui)
            result.fields = fields
            result.tag = tag
            result.gui = gui
        end,
    }
end

--- Create a subtitle observer test double.
local function make_update_test_observer(result, subtitle)
    return {
        --- Return the configured subtitle fixture.
        collect_from_current = function()
            return subtitle or make_valid_update_test_subtitle()
        end,
        --- Preserve test subtitle text during field preparation.
        clipboard_prepare = function(text)
            return text
        end,
        --- Record clearing the subtitle selection.
        clear = function()
            result.clear_count = result.clear_count + 1
        end,
    }
end

--- Create quick-creation options for update tests.
local function make_update_test_options(result)
    return {
        get_lines = h.noop,
        --- Record that quick-creation options were cleared.
        clear_options = function()
            result.clear_count = result.clear_count + 1
        end,
    }
end

--- Create a Forvo test double that leaves fields unchanged.
local function make_update_test_forvo()
    return {
        set_output_dir = h.noop,
        --- Preserve generated fields without pronunciation media.
        append = function(new_data)
            return new_data
        end
    }
end

--- Create the configuration manager used by update tests.
local function make_update_test_config_manager()
    return {
        fail_if_not_ready = h.noop,
        --- Return the fixed exporter-test configuration.
        config = function()
            return make_update_test_config()
        end
    }
end

--- Create an initialized exporter for update tests.
local function make_update_test_exporter(result, jobs, subtitle)
    return make_exporter().init {
        ankiconnect = make_update_test_ankiconnect(result),
        quick_creation_opts = make_update_test_options(result),
        subs_observer = make_update_test_observer(result, subtitle),
        encoder = make_update_test_encoder(jobs),
        forvo = make_update_test_forvo(),
        cfg_mgr = make_update_test_config_manager(),
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
