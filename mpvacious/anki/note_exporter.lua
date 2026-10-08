--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html
]]

local h = require('helpers')
local note_update_context = require('anki.note_update_context')

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

    --- Discard subtitle selection and quick options when the source file changes.
    function pub.reset_for_file_change()
        if self.subs_observer == nil then
            return pub
        end
        self.subs_observer.clear()
        self.quick_creation_opts:clear_options()
        return pub
    end

    --- Reload configuration before creating a card when configured.
    function pub.maybe_reload_config()
        if config().reload_config_before_card_creation then
            self.cfg_mgr.reload_from_disk()
        end
        return pub
    end

    --- Preflight and create export media jobs without starting them.
    local function create_export_media(subtitle)
        local first_field, field_error = self.ankiconnect.get_first_field(config().model_name)
        if field_error then
            -- A missing note type must not start encoding or discard the selection.
            return nil, field_error
        end
        local media_dir, error = self.ankiconnect.get_media_dir_path()
        if error then
            return nil, error
        end
        self.encoder.set_output_dir(media_dir)
        local snapshot = self.encoder.snapshot.create_job(subtitle)
        local audio = self.encoder.audio.create_job(subtitle, self.note_update_context.audio_padding())
        return { snapshot = snapshot, audio = audio, first_field = first_field }, nil
    end

    --- Build note fields and ensure the first model field is populated.
    local function make_export_note_fields(subtitle, media)
        local note_fields = self.note_update_context.construct_note_fields {
            primary_text = subtitle['text'],
            secondary_text = subtitle['secondary'],
            snapshot_filename = media.snapshot.filename,
            audio_filename = media.audio.filename,
        }
        if h.is_empty(note_fields[media.first_field]) then
            note_fields[media.first_field] = "[empty]"
        end
        return note_fields
    end

    --- Report media errors after both jobs have completed.
    local function on_media_creation_failure(errors)
        self.notify('Failed to create media: ' .. table.concat(errors, '; '), 'error', 5)
    end

    --- Add the captured note only after every requested media job completes successfully.
    local function start_export_media(media, note_fields, gui)
        local tag = self.note_update_context.substitute_fmt(config().note_tag)
        local completion = note_update_context
                .make_completion_collector()
                .count(2)
                .on_success(h.as_callback(self.ankiconnect.add_note, note_fields, tag, gui))
                .on_failure(on_media_creation_failure)
        -- The shared countdown is ready before any job, including a skipped job, can finish.
        self.subs_observer.clear()
        media.snapshot.on_finish(completion.callback_for('snapshot')).run_async()
        media.audio.on_finish(completion.callback_for('audio')).run_async()
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

        local media, error = create_export_media(sub)
        if error then
            -- Keep the observer's selection for a retry when Anki is unavailable.
            self.notify(error, 'error', 5)
            return pub
        end
        start_export_media(media, make_export_note_fields(sub, media), gui)
        return pub
    end

    --- Update the most recently created Anki notes.
    function pub.update_last_note(overwrite)
        local accept_notes_made_within_last_minutes = 10
        pub.maybe_reload_config()

        local n_cards = self.quick_creation_opts:get_cards()
        -- this now returns a table
        local last_note_ids = self.ankiconnect.get_last_note_ids(n_cards)

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
        self.note_update_context = note_update_context.new({
            ankiconnect = self.ankiconnect,
            quick_creation_opts = self.quick_creation_opts,
            subs_observer = self.subs_observer,
            encoder = self.encoder,
            forvo = self.forvo,
            cfg_mgr = self.cfg_mgr,
            mp = components.mp,
        })
        return pub
    end

    return pub
end

return {
    new = make_exporter,
}
