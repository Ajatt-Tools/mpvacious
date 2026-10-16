--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Encoder creates audio clips and snapshots, both animated and static.
]]

local mp = require("mp")
local utils = require("mp.utils")
local h = require("helpers")
local filename_factory = require("utils.filename_factory")
local msg = require("mp.msg")
local exec = require("encoder.executables")
local mpv_encoder = require("encoder.mpv")
local ffmpeg_encoder = require("encoder.ffmpeg")

------------------------------------------------------------
--- utility functions

--- Extend an audio window and clamp it to zero and the duration supplied by the job.
local function pad_timings(padding, start_time, end_time, video_duration)
    start_time = start_time - padding
    end_time = end_time + padding

    if start_time < 0 then
        start_time = 0
    end

    if end_time > video_duration then
        end_time = video_duration
    end

    return start_time, end_time
end

--- Play a generated audio clip in a separate mpv process.
local function background_play(file_path, on_finish)
    return h.subprocess {
        args = { exec.mpv, "--audio-display=no", "--force-window=no", "--keep-open=no", "--really-quiet", file_path },
        completion_fn = on_finish,
    }
end

--- Report a created media path or a descriptive failure to the job callback.
local function report_creation_result(kwargs)
    -- The table contains file_path plus optional file_exists, play_audio, and logger dependencies.
    kwargs = kwargs or {}
    kwargs.file_exists = kwargs.file_exists or h.file_exists
    kwargs.play_audio = kwargs.play_audio or background_play
    kwargs.logger = kwargs.logger or msg

    local private = { preview_audio = false }
    local public = {}

    --- Register the callback that receives (file_path, error).
    function public.on_finish(on_finish_fn)
        private.on_finish_fn = on_finish_fn
        return public
    end

    --- Enable playback of an audio file only after successful creation.
    function public.preview_audio(preview_audio)
        private.preview_audio = not not preview_audio
        return public
    end

    --- Notify completion before optionally playing successfully created audio.
    local function report_success()
        kwargs.logger.info(string.format("Created file: %s", kwargs.file_path))
        if type(private.on_finish_fn) == "function" then
            private.on_finish_fn(kwargs.file_path, nil)
        end
        if private.preview_audio then
            kwargs.play_audio(
                kwargs.file_path,
                function()
                    print("Played file: " .. kwargs.file_path)
                end
            )
        end
    end

    --- Log creation failure and forward its reason to an optional completion callback.
    local function report_failure(error)
        local reason = error or string.format("Couldn't create file: %s", kwargs.file_path)
        kwargs.logger.error(reason)
        if type(private.on_finish_fn) == "function" then
            private.on_finish_fn(nil, reason)
        end
    end

    --- Handle completion of an mpv or subprocess media command.
    --- https://github.com/mpv-player/mpv/blob/master/DOCS/man/lua.rst#mp-functions
    function public.run(success, result, error)
        -- result is nil on success for screenshot-to-file.
        if success and (result == nil or result.status == 0) and kwargs.file_exists(kwargs.file_path) then
            report_success()
        else
            report_failure(error)
        end
    end

    return public
end

--- Reject another attempt to start a single-use media job.
local function refuse_to_run_again()
    -- Adding `2` points to the caller: the line that called job.run_async().
    -- Using 2 makes this API-misuse error easier to trace.
    error("job has already been started", 2)
end

--- Report an unavailable media destination and fail an optional completion callback.
local function handle_missing_output_directory(logger, on_finish_fn, media_type)
    local reason = string.format("Output directory wasn't provided. %s file will not be created.", media_type)
    logger.error(reason)
    -- Report failure so a media batch cannot wait forever or treat this as a successful skip.
    if type(on_finish_fn) == "function" then
        on_finish_fn(nil, reason)
    end
end

--- Create a deferred snapshot job with its own dependencies and captured destination.
local function make_snapshot_job(opts)
    -- Dependencies (API)
    local mp_api = opts.mp_api or mp
    local get_active_track = opts.get_active_track or h.get_active_track
    local filenames = opts.filename_factory or filename_factory
    local subprocess = opts.subprocess or h.subprocess
    local logger = opts.logger or msg

    -- Private fields
    local self = {
        -- Args passed to constructor.
        sub = h.shallow_copy(opts.sub),
        cfg_mgr = opts.cfg_mgr,
        output_dir_path = opts.output_dir_path,
        backend = opts.backend, -- ffmpeg or mpv
        -- Initialized here.
        on_finish_fn = nil,
        current_timestamp = (opts.snapshot_timestamp or mp_api.get_property_number("time-pos", 0)),
        track = get_active_track("video"),
    }
    -- Public interface
    local job = {}

    ------------------------------------------------------------
    --- Private

    --- Return the active configuration for this encoder instance.
    local function config()
        return self.cfg_mgr.config()
    end

    --- Determine whether this job's selected track supports the configured animation mode.
    local function is_animated()
        return (config().animated_snapshot_enabled and not (self.track and self.track.albumart == true))
    end

    --- Name the snapshot using its configured format and timing mode.
    local function make_filename()
        -- Generate a filename for the snapshot, taking care of its extension and whether it's animated or static
        if is_animated() then
            return filenames.make_filename(self.sub["start"], self.sub["end"], config().animated_snapshot_extension)
        else
            return filenames.make_filename(self.current_timestamp, config().snapshot_extension)
        end
    end

    --- Encode an animated snapshot and forward command completion.
    local function create_animated_snapshot(source_path, output_path, on_finish_fn)
        -- Creates the animated snapshot and then calls on_finish_fn
        local args =
            self.backend.make_animated_snapshot_args(source_path, output_path, self.sub["start"], self.sub["end"])
        return subprocess { args = args, completion_fn = on_finish_fn }
    end

    --- Create a still image using encoding or mpv's screenshot command.
    local function create_static_snapshot(source_path, output_path, on_finish_fn)
        -- Creates a static snapshot, in other words an image, and then calls on_finish_fn
        if not config().screenshot then
            local args =
                self.backend.make_static_snapshot_args(source_path, output_path, self.current_timestamp, self.track)
            subprocess { args = args, completion_fn = on_finish_fn }
        else
            local args = { "screenshot-to-file", output_path, "video" }
            mp_api.command_native_async(args, on_finish_fn)
        end
    end

    --- Start the appropriate snapshot operation through the job's completion reporter.
    local function start_snapshot()
        local source_path = mp_api.get_property("path")
        local output_path = utils.join_path(self.output_dir_path, job.filename)
        local on_finish_wrap = report_creation_result {
            file_exists = opts.file_exists,
            logger = logger,
            file_path = output_path,
        }.on_finish(self.on_finish_fn)
        -- Calls the proper function depending on whether or not the snapshot should be animated
        if is_animated() then
            create_animated_snapshot(source_path, output_path, on_finish_wrap.run)
        else
            create_static_snapshot(source_path, output_path, on_finish_wrap.run)
        end
    end

    ------------------------------------------------------------
    --- Public

    job.filename = make_filename()

    --- Start this single-use snapshot job using its captured timings.
    job.run_async = function()
        job.run_async = refuse_to_run_again

        if h.is_empty(self.output_dir_path) then
            return handle_missing_output_directory(logger, self.on_finish_fn, "Image")
        end

        if not h.is_empty(config().image_field) then
            start_snapshot()
        else
            print("Snapshot will not be created.")
        end
    end

    --- Register the callback receiving the completed media path and error.
    job.on_finish = function(fn)
        self.on_finish_fn = fn
        return job
    end

    return job
end

--- Create a deferred audio job owning its timing fields and output destination.
local function make_audioclip_job(opts)
    -- Dependencies (API)
    local mp_api = opts.mp_api or mp
    local filenames = opts.filename_factory or filename_factory
    local subprocess = opts.subprocess or h.subprocess
    local logger = opts.logger or msg

    -- Private fields
    local self = {
        -- Args passed to constructor.
        -- Padding changes only this job's numeric timing fields, never the caller or sibling jobs.
        sub = h.shallow_copy(opts.sub),
        cfg_mgr = opts.cfg_mgr,
        output_dir_path = opts.output_dir_path,
        backend = opts.backend, -- ffmpeg or mpv
        audio_padding = opts.audio_padding,
        -- Initialized here.
        on_finish_fn = nil,
    }

    -- Public interface
    local job = {}

    ------------------------------------------------------------
    --- Private

    --- Return the active configuration for this encoder instance.
    local function config()
        return self.cfg_mgr.config()
    end

    --- Name the audio clip using its timing window and configured extension.
    local function make_audio_filename()
        -- Generates a filename for the audio
        return filenames.make_filename(self.sub["start"], self.sub["end"], config().audio_extension)
    end

    --- Apply padding only to this job's private timing copy.
    local function apply_padding()
        if self.audio_padding > 0 then
            -- Use this job's mp API for duration rather than reaching into the shared global API.
            self.sub["start"], self.sub["end"] = pad_timings(
                self.audio_padding,
                self.sub["start"],
                self.sub["end"],
                mp_api.get_property_number("duration")
            )
        end
    end

    local function start_audio()
        local source_path = mp_api.get_property("path")
        local output_path = utils.join_path(self.output_dir_path, job.filename)

        apply_padding()

        --- Start encoding and forward its completion to the media reporter.
        local function start_encoding(args)
            local completion =
                report_creation_result(output_path).on_finish(self.on_finish_fn).preview_audio(config().preview_audio)
            subprocess { args = args, completion_fn = completion.run }
        end

        self.backend.make_audio_args(source_path, output_path, self.sub["start"], self.sub["end"], start_encoding)
    end

    ------------------------------------------------------------
    --- Public

    job.filename = make_audio_filename()

    --- Start this single-use audio job using its captured timings and padding.
    job.run_async = function()
        job.run_async = refuse_to_run_again

        if h.is_empty(self.output_dir_path) then
            return handle_missing_output_directory(logger, self.on_finish_fn, "Audio")
        end

        if not h.is_empty(config().audio_field) then
            start_audio()
        else
            print("Audio will not be created.")
        end
    end

    --- Register the callback receiving the completed media path and error.
    job.on_finish = function(fn)
        self.on_finish_fn = fn
        return job
    end

    return job
end

--- Create an intentionally skipped job using the same completion API as real media jobs.
local function make_noop_job(opts)
    local logger = opts.logger or msg
    -- Private fields
    local self = {
        on_finish_fn = nil,
        job_type = opts.job_type,
    }

    -- Public interface
    local job = {}

    job.filename = nil

    --- Complete this single-use skipped job without an error.
    job.run_async = function()
        job.run_async = refuse_to_run_again
        -- Missing tracks or disabled fields are expected skips, not media-creation errors.
        logger.info(self.job_type .. " will not be created.")
        if type(self.on_finish_fn) == "function" then
            -- No media track or configured field: this is a skipped job, not a failure.
            self.on_finish_fn(nil, nil)
        end
    end

    --- Register the callback receiving the completed media path and error.
    job.on_finish = function(fn)
        self.on_finish_fn = fn
        return job
    end

    return job
end

------------------------------------------------------------
--- public interface

--- Create an encoder instance with independent backend and output-directory state.
local function make_encoder(components)
    components = components or {}
    local subprocess = components.subprocess or h.subprocess
    local has_video_track = components.has_video_track or h.has_video_track
    local has_audio_track = components.has_audio_track or h.has_audio_track
    local get_active_track = components.get_active_track or h.get_active_track
    local filenames = components.filename_factory or filename_factory
    local mp_api = components.mp or mp
    -- Contains the state of the encoder
    local self = {
        config = nil,
        encoder = nil,
        output_dir_path = nil,
    }

    local public = {
        snapshot = {},
        audio = {},
    }

    --- Private

    --- Return the active configuration for this encoder instance.
    local function config()
        return self.cfg_mgr.config()
    end

    --- Check whether the requested snapshot has a video track and configured image field.
    local function is_snapshot_job(job_type)
        return job_type == "snapshot" and has_video_track() and not h.is_empty(config().image_field)
    end

    --- Check whether the requested clip has an audio track and configured audio field.
    local function is_audioclip_job(job_type)
        return job_type == "audioclip" and has_audio_track() and not h.is_empty(config().audio_field)
    end

    --- Capture common job dependencies without exposing or mutating the caller's request.
    local function make_job_options(sub, audio_padding, snapshot_timestamp)
        return {
            sub = sub,
            snapshot_timestamp = snapshot_timestamp,
            audio_padding = audio_padding,
            get_active_track = get_active_track,
            mp_api = mp_api,
            cfg_mgr = self.cfg_mgr,
            filename_factory = filenames,
            output_dir_path = self.output_dir_path,
            backend = self.encoder,
            subprocess = subprocess,
            logger = components.logger,
            file_exists = components.file_exists,
            play_audio = components.play_audio,
        }
    end

    --- Prepare a single-use media job or an intentional skip when no track/field exists.
    local function create_job(job_type, sub, audio_padding, snapshot_timestamp)
        if is_snapshot_job(job_type) then
            return make_snapshot_job(make_job_options(sub, nil, snapshot_timestamp))
        elseif is_audioclip_job(job_type) then
            return make_audioclip_job(make_job_options(sub, audio_padding))
        else
            return make_noop_job {
                job_type = job_type,
                logger = components.logger,
            }
        end
    end

    --- Select the configured FFmpeg or mpv encoding backend.
    local function choose_backend()
        if config().use_ffmpeg then
            return ffmpeg_encoder.new(self.cfg_mgr, nil, { get_active_track = get_active_track, mp = mp_api })
        else
            return mpv_encoder.new(self.cfg_mgr, nil, { get_active_track = get_active_track, mp = mp_api })
        end
    end

    ------------------------------------------------------------
    --- Public

    --- Return the initialized encoding backend.
    function public.encoder()
        return self.encoder
    end

    --- Initialize this encoder from the supplied configuration manager.
    function public.init(cfg_mgr)
        -- Sets the module to its preconfigured status
        cfg_mgr.fail_if_not_ready()
        self.cfg_mgr = cfg_mgr
        self.encoder = choose_backend()
        self.encoder.init()
        return public
    end

    --- Set the collection media directory captured by subsequently constructed jobs.
    function public.set_output_dir(dir_path)
        -- Set directory where media files should be saved.
        -- This function is called every time a card is created or updated.
        self.output_dir_path = dir_path
    end

    --- Prepare a snapshot job, using current playback time when no timestamp is supplied.
    function public.snapshot.create_job(sub, timestamp)
        return create_job("snapshot", sub, nil, timestamp)
    end

    --- Toggle animated snapshots in the active configuration.
    function public.snapshot.toggle_animation()
        -- Toggles on and off animated snapshot generation at runtime. It is called whenever ctrl+g is pressed
        config().animated_snapshot_enabled = not config().animated_snapshot_enabled
        h.notify("Animation " .. (config().animated_snapshot_enabled and "enabled" or "disabled"), "info", 2)
    end

    --- Prepare an audio job for the supplied subtitle selection and padding.
    function public.audio.create_job(subtitle, padding)
        return create_job("audioclip", subtitle, padding)
    end

    --- Create an independently initialized encoder for another configuration provider.
    function public.new(cfg_mgr)
        return make_encoder(components).init(cfg_mgr)
    end

    return public
end

return {
    new = make_encoder,
    report_creation_result = report_creation_result,
}
