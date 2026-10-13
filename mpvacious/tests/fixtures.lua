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
    --- Supply preflight model metadata for exporter integration tests.
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
function this.make_loudnorm_test_context(make_backend, cfg_mgr)
    local state = { analysis = {}, encoding = {}, warnings = {} }
    local components = {
        mp = this.make_mp_property_reader { aid = "2", volume = 100 },
        --- Supply a known internal audio track without changing shared mp functions.
        get_active_track = function() return { ["ff-index"] = 1, external = false } end,
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
        1,
        2,
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

return this
