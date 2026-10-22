--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Fixtures shared by standalone and in-mpv tests.
]]

local h = require("helpers")

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
function this.make_pending_media_job(filename, jobs, on_start)
    local job = { filename = filename }
    --- Record when the simulated job starts.
    function job.run_async()
        job.started = true
        if on_start then on_start() end
        if filename == nil and job.callback then
            job.callback(nil, nil)
        end
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
local function make_media_job_factory(filename, jobs, state)
    --- Create a pending job when the encoder requests one.
    return function(_, argument)
        local job = this.make_pending_media_job(filename, jobs, state.on_start)
        job.cfg_mgr = state.cfg_mgr
        job.output_dir = state.output_dir
        job.argument = argument
        return job
    end
end

--- Return an encoder whose audio and snapshot jobs are recorded in `jobs`.
function this.make_update_encoder(jobs, options, cfg_mgr)
    options = options or {}
    local state = { cfg_mgr = cfg_mgr, on_start = options.on_start }
    local snapshot_filename = "snapshot.avif"
    local audio_filename = "audio.ogg"
    if options.skip_snapshot then
        snapshot_filename = nil
    end
    if options.skip_audio then
        audio_filename = nil
    end
    local encoder = {
        snapshot = { create_job = make_media_job_factory(snapshot_filename, jobs, state) },
        audio = { create_job = make_media_job_factory(audio_filename, jobs, state) },
    }
    --- Set only this fake encoder's output directory.
    function encoder.set_output_dir(dir_path)
        state.output_dir = dir_path
    end
    --- Construct independent fake jobs using the same scenario recording list.
    function encoder.new(request_cfg_mgr)
        request_cfg_mgr.fail_if_not_ready()
        return this.make_update_encoder(jobs, options, request_cfg_mgr)
    end
    return encoder
end

--- Return a request-local Forvo fake recording configuration and stored fields.
function this.make_forvo(state, cfg_mgr)
    state = state or {}
    local output_dir
    local downloader = {
        --- Leave generated fields unchanged.
        append = function(fields, stored_fields)
            state.forvo_stored_data = stored_fields
            if cfg_mgr then
                state.forvo_calls = state.forvo_calls or {}
                table.insert(state.forvo_calls, { cfg_mgr = cfg_mgr, output_dir = output_dir })
            end
            return fields
        end,
    }
    --- Set only this fake downloader's destination.
    function downloader.set_output_dir(dir_path)
        output_dir = dir_path
    end
    --- Construct a fresh pronunciation fake for the supplied provider.
    function downloader.new(request_cfg_mgr)
        request_cfg_mgr.fail_if_not_ready()
        return this.make_forvo(state, request_cfg_mgr)
    end
    return downloader
end

--- Return a config manager that exposes the supplied test configuration.
function this.make_config_manager(config, profiles)
    profiles = profiles or { active = "test", profiles = "test" }
    return {
        fail_if_not_ready = h.noop,
        --- Return the test configuration.
        config = function()
            return config
        end,
        --- Return profile metadata that a transaction snapshot can capture.
        profiles = function()
            return profiles
        end,
    }
end

--- Return a fresh common update-test configuration with local scenario overrides.
function this.make_update_config(overrides)
    local config = {
        sentence_field = "SentKanji",
        audio_field = "SentAudio",
        audio_template = "[sound:%s]",
        image_field = "Image",
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
function this.make_update_ankiconnect(state, fields_for_note, cfg_mgr)
    return {
        --- Return the test media directory.
        get_media_dir_path = function()
            state.media_dir_requests = (state.media_dir_requests or 0) + 1
            if state.media_dir_error then
                return nil, state.media_dir_error
            end
            return state.media_dir_path or "/tmp", nil
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
            return state.first_field or "SentKanji", nil
        end,
        --- Record a write and optionally defer its completion for asynchronous tests.
        append_media = function(note_id, fields, tag, on_finish)
            state.write_cfg_mgrs = state.write_cfg_mgrs or {}
            table.insert(state.write_cfg_mgrs, cfg_mgr)
            state.tags_by_note = state.tags_by_note or {}
            state.tags_by_note[note_id] = tag
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
        add_note = function(job)
            state.add_count = (state.add_count or 0) + 1
            state.fields = job.note_fields
            state.tag = job.tag
            state.gui = job.gui
            if cfg_mgr then
                state.note_config = h.deep_copy(cfg_mgr.config())
            end
        end,
        --- Record the Anki Browser query.
        gui_browse = function(query)
            state.browse_query = query
        end,
        --- Create a fresh note-add fake retaining only the scenario's recording state.
        new = function(request_cfg_mgr)
            state.client_cfg_mgrs = state.client_cfg_mgrs or {}
            table.insert(state.client_cfg_mgrs, request_cfg_mgr)
            return this.make_update_ankiconnect(state, fields_for_note, request_cfg_mgr)
        end,
        --- Return scenario recent-note IDs while recording the requested count.
        get_last_note_ids = function(n_cards)
            state.requested_cards = n_cards
            return state.last_note_ids or {}
        end,
        --- Return scenario Browser selection without accessing Anki.
        get_selected_note_ids = function()
            return state.selected_note_ids or {}
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
        --- Record a menu refresh after the subtitle selection is cleared.
        refresh_menu = function()
            state.menu_updates = (state.menu_updates or 0) + 1
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
    local lines = options.lines
    local cards = options.cards or 1
    return {
        --- Return the chosen number of lines.
        get_lines = function()
            return lines
        end,
        --- Return the chosen number of target cards.
        get_cards = function()
            return cards
        end,
        --- Set later interactive options from reentrancy tests without changing production APIs.
        set_options_for_test = function(new_lines, new_cards)
            lines, cards = new_lines, new_cards
        end,
        --- Record clearing when requested by the test.
        clear_options = function()
            lines = nil
            cards = 1
            if options.record_clear then
                state.clear_count = (state.clear_count or 0) + 1
            end
        end,
    }
end

--- Return a notification callback that records the last message, level, and duration.
function this.make_notifier(state)
    --- Record one notification for later assertions.
    return function(message, level, duration)
        state.notification = message
        state.notification_level = level
        state.notification_duration = duration
    end
end

--- Supply a deterministic timeout for confirmation fakes without copying the production default.
function this.get_confirmation_timeout_for_test()
    return 7
end

--- Return a confirmation fake that immediately accepts each prompt without opening UI.
function this.make_accepting_confirmation()
    return {
        get_confirmation_timeout = this.get_confirmation_timeout_for_test,
        cancel = h.noop,
        --- Complete accepted prompts synchronously for dispatch and transport scenarios.
        confirm = function(options) options.on_accept() end,
    }
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

--- Record Forvo I/O without accessing the network, filesystem, or real encoder.
function this.make_forvo_dependencies(state, responses)
    return {
        platform = {
            windows = false,
            --- Return a fake temporary directory without creating it.
            tmp_dir = function() return "/forvo-test-tmp" end,
            --- Record a request and return its supplied response.
            curl_request = function(options)
                table.insert(state.requests, options.args)
                return responses[#state.requests]
            end,
        },
        --- Record encoding arguments and simulate successful completion.
        subprocess = function(options)
            table.insert(state.encodings, options.args)
            if state.encoding_response then
                return state.encoding_response()
            end
            return { status = 0 }
        end,
        --- Record temporary-file cleanup without removing a real file.
        remove_file = function(path)
            table.insert(state.removed, path)
        end,
        logger = {
            --- Capture expected warnings without printing misleading test errors.
            warn = function(message)
                table.insert(state.warnings, message)
            end,
        },
    }
end

--- Return isolated mp property readers backed by supplied test values.
function this.make_mp_property_reader(properties)
    --- Read the current value, allowing a test to advance its own playback clock.
    local function get_property(name)
        return properties[name]
    end
    return {
        get_property = get_property,
        get_property_number = get_property,
        get_property_native = get_property,
    }
end

--- Record requests and optionally serialize them through the injected fake transport.
local function record_note_add_test_requests(client, state, components)
    local execute = client.execute
    --- Record the request without contacting Anki.
    client.execute = function(options)
        state.note_requests = state.note_requests or {}
        table.insert(state.note_requests, options.request)
        if components and components.platform then
            return execute(options)
        end
    end
end

--- Construct a recording client and preserve its fake dependencies across new instances.
local function make_note_add_test_client(state, make_client, cfg_mgr, components)
    local client = make_client(components).init(cfg_mgr)
    --- Supply model metadata for exporter integration tests' first-field checks.
    client.get_first_field = function()
        return cfg_mgr.config().sentence_field, nil
    end
    --- Supply a fake destination for deferred encoder jobs.
    client.get_media_dir_path = function()
        return "/anki-test-media", nil
    end
    record_note_add_test_requests(client, state, components)
    --- Construct a recording transaction client rather than losing fake transport hooks.
    client.new = function(request_cfg_mgr)
        return make_note_add_test_client(state, make_client, request_cfg_mgr, components)
    end
    return client
end

--- Use the real note-request builder while recording transport calls without network access.
function this.make_note_add_client(state, make_client, config, components)
    return make_note_add_test_client(state, make_client, this.make_config_manager(config), components)
end

--- Record real-client JSON transport calls without sending network requests.
function this.make_recording_anki_platform(state)
    return {
        --- Capture transport arguments without triggering a completion callback.
        json_curl_request = function(options)
            state.transport_calls = state.transport_calls or {}
            table.insert(state.transport_calls, options)
            return {}
        end,
    }
end

--- Create a backend with deterministic codec support and replaceable configuration.
function this.make_backend_codec_test_context(make_backend, config, supported)
    local state = { config = config }
    local support = {
        avif_encoders = { "libsvtav1", "libaom-av1" },
        ffmpeg_support = { snapshot = supported },
        mpv_support = { snapshot = supported },
    }
    local cfg_mgr = {
        fail_if_not_ready = h.noop,
        --- Return the scenario's current configuration after simulated reloads.
        config = function() return state.config end,
    }
    return make_backend(cfg_mgr, support), state
end

--- Extract the snapshot codec from either backend's generated command.
function this.backend_test_command_codec(args)
    for index, arg in ipairs(args) do
        if arg == "-c:v" then
            return args[index + 1]
        end
        if arg:match("^%-%-ovc=") then
            return arg:sub(7)
        end
    end
    error("backend test command contains no snapshot codec")
end

--- Return only the method names exposed by a backend instance.
function this.backend_test_public_keys(backend)
    local keys = {}
    for key in pairs(backend) do
        table.insert(keys, key)
    end
    table.sort(keys)
    return keys
end

--- Record encoder commands without executing them or completing filesystem-dependent callbacks.
function this.make_recording_encoder_components(state)
    return {
        mp = this.make_mp_property_reader { path = "encoder-test.mkv", ["time-pos"] = 0 },
        --- Keep generic command tests independent of the host mpv's selected tracks.
        get_active_track = function() return nil end,
        --- Record a media command for output-directory assertions.
        subprocess = function(options)
            table.insert(state.commands, options.args)
        end,
        --- Supply a video track without changing the shared mp API.
        has_video_track = function() return true end,
        filename_factory = {
            --- Avoid the file-loaded filename cache during standalone tests.
            make_filename = function() return "encoder-test.jpg" end,
        },
    }
end

--- Extract a still-snapshot timestamp from either backend's command.
function this.encoder_test_snapshot_timestamp(args)
    for index, arg in ipairs(args) do
        if arg == "-ss" then return args[index + 1] end
        local timestamp = arg:match("^%-%-start=(.+)$")
        if timestamp then return timestamp end
    end
    error("encoder test command contains no snapshot timestamp")
end

--- Extract the output path from a generated mpv or FFmpeg test command.
function this.encoder_test_output_path(args)
    for _, arg in pairs(args) do
        if arg:match("^%-o=") then
            return arg:sub(4)
        end
    end
    return args[#args]
end

--- Build raw notesInfo responses for the scenario's requested target IDs.
local function make_update_transport_test_fields(state, note_ids)
    local notes = {}
    for _, note_id in ipairs(note_ids) do
        local fields = {}
        for name, value in pairs(state.stored_fields[note_id]) do
            fields[name] = { value = value }
        end
        table.insert(notes, { noteId = note_id, fields = fields })
    end
    return notes
end

--- Return synchronous fake responses while deferring real-client write completions.
local function update_transport_test_response(state, options)
    local request = state.anki_requests[#state.anki_requests].request
    if request.action == "getMediaDirPath" then
        return { test_result = state.media_dirs[options.url] }
    elseif request.action == "notesInfo" then
        return { test_result = make_update_transport_test_fields(state, request.params.notes) }
    elseif request.action == "findModelsByName" then
        return { test_result = { { flds = { { ord = 0, name = "SentKanji" } } } } }
    elseif request.action == "findNotes" or request.action == "guiSelectedNotes" then
        return { test_result = state.target_ids }
    elseif request.action == "updateNoteFields" then
        state.anki_write_callbacks = state.anki_write_callbacks or {}
        state.anki_write_callbacks[request.params.note.id] = options.completion_fn
    end
    return {}
end

--- Capture serialized transport calls without network I/O.
local function make_update_transport_test_platform(state)
    return {
        --- Record the destination and return the scenario's response.
        json_curl_request = function(options)
            state.anki_transport = state.anki_transport or {}
            table.insert(state.anki_transport, options)
            return update_transport_test_response(state, options)
        end,
    }
end

--- Record real request construction and provide parsing independent of the JSON stub.
local function attach_update_transport_test_hooks(client, state, cfg_mgr)
    local execute = client.execute
    --- Record each request and its instance provider before real serialization.
    client.execute = function(options)
        state.anki_requests = state.anki_requests or {}
        table.insert(state.anki_requests, { request = options.request, cfg_mgr = cfg_mgr })
        return execute(options)
    end
    --- Supply already-decoded fake results in standalone and mpv tests.
    client.parse_result = function(result)
        return result.test_result, nil
    end
end

--- Create recording update clients and retain fake hooks in transaction-local instances.
function this.make_update_transport_test_client(state, make_client, cfg_mgr)
    local client = make_client { platform = make_update_transport_test_platform(state) }.init(cfg_mgr)
    attach_update_transport_test_hooks(client, state, cfg_mgr)
    --- Construct a fresh client without losing recording and response hooks.
    client.new = function(request_cfg_mgr)
        return this.make_update_transport_test_client(state, make_client, request_cfg_mgr)
    end
    return client
end

--- Return complete measured statistics in the backend's expected JSON shape.
local function loudnorm_test_json()
    return '{"input_i":"-20","input_lra":"3","input_tp":"-2","input_thresh":"-30","target_offset":"1"}'
end

--- Supply deterministic loudness statistics without depending on the standalone JSON stub.
local function parse_loudnorm_test_json(state, json)
    h.assert_equals(json, loudnorm_test_json())
    state.parsed_json_count = (state.parsed_json_count or 0) + 1
    return {
        input_i = "-20",
        input_lra = "3",
        input_tp = "-2",
        input_thresh = "-30",
        target_offset = "1",
    }
end

--- Create a backend with deferred analysis and isolated track, property, logging, and JSON boundaries.
function this.make_loudnorm_test_context(make_backend, cfg_mgr, audio_track)
    audio_track = audio_track or { ["ff-index"] = 1, external = false }
    local state = { analysis = {}, encoding = {}, warnings = {} }
    local components = {
        mp = this.make_mp_property_reader { aid = "2", volume = 100 },
        --- Supply controlled internal or external audio without changing shared mp functions.
        get_active_track = function() return audio_track end,
        --- Save analysis callbacks without launching an encoder process.
        subprocess = function(options) table.insert(state.analysis, options) end,
        --- Decode the controlled successful analysis result.
        parse_json = function(json) return parse_loudnorm_test_json(state, json) end,
        logger = {
            info = h.noop,
            --- Capture expected normalization fallbacks without printing test errors.
            warn = function(message) table.insert(state.warnings, message) end,
        },
    }
    local backend = make_backend(cfg_mgr, nil, components)
    backend.init()
    backend.make_audio_args(
        "source.mkv",
        "output" .. cfg_mgr.config().audio_extension,
        { ["start"] = 1, ["end"] = 2 },
        this.make_loudnorm_test_consumer(state)
    )
    return backend, state
end

--- Record the command delivered after deferred loudness analysis completes.
function this.make_loudnorm_test_consumer(state)
    return function(args) table.insert(state.encoding, args) end
end

--- Complete analysis with controlled successful output or an explicit process failure.
function this.complete_loudnorm_test_analysis(state, success)
    local result = { status = 1, stdout = "", stderr = "" }
    if success then
        result = {
            status = 0,
            stdout = "[ffmpeg] " .. loudnorm_test_json(),
            stderr = "[Parsed_loudnorm_0 @ test] " .. loudnorm_test_json(),
        }
    end
    state.analysis[1].completion_fn(success, result, nil)
end

--- Read a generated FFmpeg option or an equals-delimited mpv option.
function this.encoder_test_option_value(args, option)
    for index, arg in ipairs(args) do
        if arg == option then
            return args[index + 1]
        elseif arg:sub(1, #option + 1) == option .. "=" then
            return arg:sub(#option + 2)
        end
    end
    return nil
end

--- Model a selected subtitle that can be replaced by a synchronous completion callback.
function this.make_reentrant_update_test_observer(state)
    return {
        refresh_menu = h.noop,
        --- Return the scenario's current selected subtitle.
        collect_from_current = function() return state.selection end,
        --- Leave text preparation unchanged for the lifecycle test.
        clipboard_prepare = function(text) return text end,
        user_altered = function() return false end,
        --- Clear only the selection present when the request begins.
        clear = function()
            state.selection = nil
            state.clear_count = (state.clear_count or 0) + 1
        end,
    }
end

--- Record interactive state at each media-job start.
function this.make_update_start_test_recorder(state, quick_options)
    return function()
        table.insert(state.job_starts, {
            selection = state.selection,
            lines = quick_options:get_lines(),
            cards = quick_options:get_cards(),
        })
    end
end

--- Install a later selection and options when a successful request completes reentrantly.
function this.make_reentrant_update_test_notifier(state, quick_options)
    return function(message, level)
        state.notification, state.notification_level = message, level
        if level ~= "error" then
            state.selection_at_finish = state.selection
            state.selection = state.later_selection
            quick_options.set_options_for_test(7, 9)
        end
    end
end

--- Initialize a backend with deterministic codecs and selected-video metadata.
function this.make_cover_backend_test_context(make_backend, config, video_track)
    local support = {
        avif_encoders = {},
        ffmpeg_support = { snapshot = {} },
        mpv_support = { snapshot = {} },
    }
    local backend = make_backend(this.make_config_manager(config), support, {
        --- Supply only the scenario's selected video track.
        get_active_track = function(kind)
            if kind == "video" then return video_track end
            return nil
        end,
    })
    backend.init()
    return backend
end

--- Record cover-job commands, native screenshots, and requested filename arguments.
function this.make_cover_encoder_test_components(state, video_track)
    local components = this.make_recording_encoder_components(state)
    state.video_track = video_track
    components.mp = this.make_mp_property_reader { path = "source.m4b", ["time-pos"] = 65 }
    --- Record native screenshots without requiring a rendered video output.
    components.mp.command_native_async = function(args) table.insert(state.screenshots, args) end
    --- Preserve the selected-track boundary when constructing transaction encoders.
    components.get_active_track = function(kind)
        if kind == "video" then return state.video_track end
        return nil
    end
    --- Expose the selected static or animated filename extension and timing arguments.
    components.filename_factory.make_filename = function(...)
        local args = { ... }
        table.insert(state.filename_args, args)
        return "snapshot" .. args[#args]
    end
    return components
end

--- Record media completion paths and errors, including intentional nil results.
function this.make_media_result_test_recorder(state, on_finish)
    return function(path, error)
        state.completion_count = (state.completion_count or 0) + 1
        state.completed_path, state.completed_error = path, error
        if on_finish then on_finish(path, error) end
    end
end

--- Record audio and snapshot jobs against isolated track, duration, and filename dependencies.
function this.make_recording_audio_encoder_components(state)
    local components = this.make_recording_encoder_components(state)
    components.mp = this.make_mp_property_reader {
        path = "encoder-test.mkv",
        ["time-pos"] = 65,
        duration = 100,
        aid = "1",
        volume = 100,
    }
    --- Make audio-job eligibility independent of the media used by the real-mpv test runner.
    components.has_audio_track = function() return true end
    --- Record the original unpadded timing window used to name each media file.
    components.filename_factory.make_filename = function(...)
        local args = { ... }
        state.filename_args = state.filename_args or {}
        table.insert(state.filename_args, args)
        return "encoder-test" .. args[#args]
    end
    return components
end

--- Supply deterministic eligibility and informational logging for skipped encoder jobs.
function this.make_noop_encoder_test_components(state, has_track)
    local components = this.make_recording_audio_encoder_components(state)
    --- Make either media type absent without modifying the shared mp API.
    components.has_video_track = function() return has_track end
    components.has_audio_track = components.has_video_track
    components.logger = {
        --- Expose the standard informational logger method, not a non-existent warning method.
        info = function(message) table.insert(state.messages, message) end,
    }
    return components
end

--- Record one completion and whether the real batch collector accepts it as successful.
function this.make_recording_completion_test_callback(state, make_collector, label)
    local collector = make_collector()
        .count(1)
        .on_success(function()
            state.success_count = (state.success_count or 0) + 1
        end)
        .on_failure(function(errors)
            state.failed_errors = errors
        end)
    return this.make_media_result_test_recorder(state, collector.callback_for(label))
end

--- Deliver one recorded native or subprocess media result without touching the filesystem.
function this.complete_job_lifecycle_test_operation(state, index, success, error)
    local operation = state.operations[index]
    local result
    if not operation.native then
        local status = 0
        if not success then status = 1 end
        result = { status = status }
    end
    operation.callback(success, result, error)
end

--- Record a media operation and optionally finish it synchronously to exercise reentrancy.
local function record_job_lifecycle_test_operation(state, args, callback, native)
    table.insert(state.operations, { args = args, callback = callback, native = native })
    if state.finish_immediately then
        this.complete_job_lifecycle_test_operation(state, #state.operations, true, nil)
    end
end

--- Return independent recording state for one real-job lifecycle scenario.
function this.make_job_lifecycle_test_state(options)
    return {
        operations = {},
        checked_paths = {},
        messages = {},
        previews = {},
        file_exists = options.file_exists,
        finish_immediately = options.finish_immediately,
    }
end

--- Supply isolated execution, file checks, logging, and audio previews for real job lifecycle tests.
function this.make_job_lifecycle_test_components(state)
    local components = this.make_recording_audio_encoder_components(state)
    --- Record subprocess execution without starting a real encoder.
    components.subprocess = function(options)
        record_job_lifecycle_test_operation(state, options.args, options.completion_fn, false)
    end
    --- Record native screenshot callbacks independently of a rendered video output.
    components.mp.command_native_async = function(args, callback)
        record_job_lifecycle_test_operation(state, args, callback, true)
    end
    --- Return controlled file validation results without filesystem access.
    components.file_exists = function(path)
        table.insert(state.checked_paths, path)
        return state.file_exists
    end
    --- Record playback and whether completion already reached the caller.
    components.play_audio = function(path)
        table.insert(state.previews, { path = path, completion_count = state.completion_count })
    end
    components.logger = {
        --- Record successful creation messages without printing during tests.
        info = function(message) table.insert(state.messages, { level = "info", message = message }) end,
        --- Record expected failures without alarming the real-mpv test runner.
        error = function(message) table.insert(state.messages, { level = "error", message = message }) end,
    }
    return components
end

--- Record completion and attempt a guarded reentrant start when requested by the scenario.
function this.make_job_lifecycle_test_callback(state, job, reentrant)
    return this.make_media_result_test_recorder(state, function()
        if reentrant then
            state.reentrant_success, state.reentrant_error = pcall(job.run_async)
        end
    end)
end

--- Supply isolated subtitle properties and record observer registrations without changing mp.
function this.make_subtitle_observer_test_api(properties)
    local api = this.make_mp_property_reader(properties)
    local observers = {}
    --- Retain the registered callback so tests can deliver property changes explicitly.
    api.observe_property = function(name, format, callback)
        observers[name] = { format = format, callback = callback }
    end
    return api, observers
end

return this
