--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Fixtures shared by standalone and in-mpv tests.
]]

local h = require('helpers')

local this = {}

--- Return an AnkiConnect client that records the requested IDs and supplies a response.
function this.make_note_fields_client(state, make_client, scenario)
    local client = make_client()
    --- Record the notesInfo request without asserting inside the fixture.
    client.execute = function(options)
        state.requested_note_ids = options.request.params.notes
        return options
    end
    --- Return the scenario's simulated AnkiConnect response.
    client.parse_result = function()
        return scenario.result, scenario.error
    end
    return client
end

--- Create a deferred media job and record its completion callback and start.
function this.make_pending_media_job(filename, jobs)
    local job = { filename = filename }
    --- Record when the simulated job starts.
    function job.run_async()
        job.started = true
    end
    --- Save the completion callback for the test to invoke.
    function job.on_finish(callback)
        job.callback = callback
        return job
    end
    table.insert(jobs, job)
    return job
end

--- Return a media-job factory for one output filename.
local function make_media_job_factory(filename, jobs)
    --- Create a pending job when the encoder requests one.
    return function()
        return this.make_pending_media_job(filename, jobs)
    end
end

--- Return an encoder whose audio and snapshot jobs are recorded in `jobs`.
function this.make_update_encoder(jobs)
    return {
        set_output_dir = h.noop,
        snapshot = { create_job = make_media_job_factory('snapshot.avif', jobs) },
        audio = { create_job = make_media_job_factory('audio.ogg', jobs) },
    }
end

--- Return a Forvo fake that preserves fields without producing media.
function this.make_forvo()
    return {
        set_output_dir = h.noop,
        --- Leave generated fields unchanged.
        append = function(fields)
            return fields
        end,
    }
end

--- Return a config manager that exposes the supplied test configuration.
function this.make_config_manager(config)
    return {
        fail_if_not_ready = h.noop,
        --- Return the test configuration.
        config = function()
            return config
        end,
    }
end

--- Return a fresh common update-test configuration with local scenario overrides.
function this.make_update_config(overrides)
    local config = {
        sentence_field = 'SentKanji',
        audio_field = 'SentAudio',
        audio_template = '[sound:%s]',
        image_field = 'Image',
        image_template = '<img alt="snapshot" src="%s">',
        audio_padding = 0,
        miscinfo_enable = false,
    }
    for key, value in pairs(overrides or {}) do
        config[key] = value
    end
    return config
end

--- Build note-field results without sharing field tables between note IDs.
local function make_update_test_fields_by_id(note_ids, fields_for_note)
    local fields_by_id = {}
    for _, note_id in pairs(note_ids) do
        fields_by_id[note_id] = fields_for_note(note_id)
    end
    return fields_by_id
end

--- Return an AnkiConnect fake that records update requests and delegates test-specific fields.
function this.make_update_ankiconnect(state, fields_for_note)
    return {
        --- Return the test media directory.
        get_media_dir_path = function()
            if state.media_dir_error then
                return nil, state.media_dir_error
            end
            return '/tmp', nil
        end,
        --- Record bulk field reads before returning test-specific fields or errors.
        get_notes_fields = function(note_ids)
            state.field_requests = state.field_requests or {}
            table.insert(state.field_requests, h.itable_slice(note_ids))
            if state.read_fields then
                return state.read_fields(note_ids, #state.field_requests)
            end
            return make_update_test_fields_by_id(note_ids, fields_for_note), nil
        end,
        --- Record notification previews before returning test-specific fields or errors.
        get_note_fields = function(note_id)
            state.preview_reads = state.preview_reads or {}
            table.insert(state.preview_reads, note_id)
            if state.read_preview then
                return state.read_preview(note_id, #state.preview_reads)
            end
            return fields_for_note(note_id), nil
        end,
        --- Return the sentence field used in update notifications.
        get_first_field = function()
            if state.first_field_error then
                return nil, state.first_field_error
            end
            return state.first_field or 'SentKanji', nil
        end,
        --- Record a write and optionally defer its completion for asynchronous tests.
        append_media = function(note_id, fields, _, on_finish)
            state.append_count = (state.append_count or 0) + 1
            state.appended_note_ids = state.appended_note_ids or {}
            state.fields_by_note = state.fields_by_note or {}
            table.insert(state.appended_note_ids, note_id)
            state.fields_by_note[note_id] = fields
            state.note_id = note_id
            state.fields = fields
            if state.write_callbacks then
                state.write_callbacks[note_id] = on_finish
            elseif on_finish then
                on_finish(nil, nil)
            end
        end,
        --- Record an ordinary note export.
        add_note = function(fields, tag, gui)
            state.fields = fields
            state.tag = tag
            state.gui = gui
        end,
        --- Record the Anki Browser query.
        gui_browse = function(query)
            state.browse_query = query
        end,
    }
end

--- Return an observer that records subtitle collection and selection clearing.
function this.make_subtitle_observer(state, subtitle, options)
    options = options or {}
    return {
        --- Return the current test subtitle and record the collection.
        collect_from_current = function()
            state.current_collections = (state.current_collections or 0) + 1
            return subtitle
        end,
        --- Record the requested number of dialogue lines.
        collect_from_all_dialogues = function(lines)
            state.collected_lines = lines
            return subtitle
        end,
        --- Preserve text during field preparation.
        clipboard_prepare = function(text)
            return text
        end,
        --- Record clearing the subtitle selection.
        clear = function()
            state.clear_count = (state.clear_count or 0) + 1
        end,
        --- Report whether subtitle timings were manually altered.
        user_altered = function()
            return options.user_altered or false
        end,
    }
end

--- Return quick-creation options with optional clearing observation.
function this.make_quick_creation_options(state, options)
    options = options or {}
    return {
        --- Return the chosen number of lines.
        get_lines = function()
            return options.lines
        end,
        --- Record clearing when requested by the test.
        clear_options = function()
            if options.record_clear then
                state.clear_count = (state.clear_count or 0) + 1
            end
        end,
    }
end

--- Return a notification callback that records the last message and level.
function this.make_notifier(state)
    --- Record one notification for later assertions.
    return function(message, level)
        state.notification = message
        state.notification_level = level
    end
end

--- Return a fake AnkiConnect API for automatic new-note checker tests.
function this.make_new_note_checker_ankiconnect(state, scenario)
    return {
        --- Return an empty search first, then the note to inspect.
        find_notes = function(options)
            state.searches = state.searches + 1
            if state.searches == 1 then
                options.completion_fn({}, nil)
            else
                options.completion_fn({ state.note_id }, nil)
            end
        end,
        --- Record a field read and return the scenario response.
        get_note_fields = function()
            state.fetches = state.fetches + 1
            if scenario.error then
                return nil, scenario.error
            end
            return scenario.fields, nil
        end,
    }
end

--- Return a fake mp API that exposes each scheduled checker tick through `state`.
function this.make_new_note_checker_mp(state)
    return {
        --- Expose the scheduled timer callback to the test.
        add_periodic_timer = function(_, callback)
            state.tick = callback
            return {
                --- Record timer cancellation.
                kill = function()
                    state.timer_kills = state.timer_kills + 1
                end,
            }
        end,
    }
end

--- Return a fake logger that records checker errors and ignores status messages.
function this.make_new_note_checker_logger(state)
    return {
        --- Record checker errors without printing them.
        error = function(message)
            table.insert(state.errors, message)
        end,
        info = h.noop,
    }
end

return this
