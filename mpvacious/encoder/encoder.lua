--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Encoder creates audio clips and snapshots, both animated and static.
]]

local mp = require('mp')
local utils = require('mp.utils')
local h = require('helpers')
local filename_factory = require('utils.filename_factory')
local msg = require('mp.msg')
local exec = require('encoder.executables')
local mpv_encoder = require('encoder.mpv')
local ffmpeg_encoder = require('encoder.ffmpeg')

--Contains the state of the module
local self = {
    config = nil,
    encoder = nil,
    output_dir_path = nil,
}

------------------------------------------------------------
--- utility functions

local function pad_timings(padding, start_time, end_time)
    local video_duration = mp.get_property_number('duration')
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
        args = { exec.mpv, '--audio-display=no', '--force-window=no', '--keep-open=no', '--really-quiet', file_path },
        completion_fn = on_finish
    }
end

--- Report a created media path or a descriptive failure to the job callback.
local function report_creation_result(file_path, components)
    components = components or {}
    components.file_exists = components.file_exists or h.file_exists
    components.play_audio = components.play_audio or background_play
    components.logger = components.logger or msg

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

    --- Handle completion of an mpv or subprocess media command.
    --- https://github.com/mpv-player/mpv/blob/master/DOCS/man/lua.rst#mp-functions
    function public.run(success, result, error)
        -- result is nil on success for screenshot-to-file.
        if success and (result == nil or result.status == 0) and components.file_exists(file_path) then
            components.logger.info(string.format("Created file: %s", file_path))
            if type(private.on_finish_fn) == 'function' then
                private.on_finish_fn(file_path, nil)
            end
            if private.preview_audio then
                components.play_audio(file_path, function()
                    print("Played file: " .. file_path)
                end)
            end
        else
            local reason = error or string.format("Couldn't create file: %s", file_path)
            components.logger.error(reason)
            if type(private.on_finish_fn) == 'function' then
                private.on_finish_fn(nil, reason)
            end
        end
    end

    return public
end

------------------------------------------------------------
--- main interface

local create_animated_snapshot = function(start_timestamp, end_timestamp, source_path, output_path, on_finish_fn)
    -- Creates the animated snapshot and then calls on_finish_fn
    local args = self.encoder.make_animated_snapshot_args(source_path, output_path, start_timestamp, end_timestamp)
    h.subprocess { args = args, completion_fn = on_finish_fn }
end

local create_static_snapshot = function(timestamp, source_path, output_path, on_finish_fn)
    -- Creates a static snapshot, in other words an image, and then calls on_finish_fn
    if not self.config.screenshot then
        local args = self.encoder.make_static_snapshot_args(source_path, output_path, timestamp)
        h.subprocess { args = args, completion_fn = on_finish_fn }
    else
        local args = { 'screenshot-to-file', output_path, 'video', }
        mp.command_native_async(args, on_finish_fn)
    end
end

local create_snapshot = function(start_timestamp, end_timestamp, current_timestamp, filename, on_finish_fn)
    if h.is_empty(self.output_dir_path) then
        return msg.error("Output directory wasn't provided. Image file will not be created.")
    end

    -- Calls the proper function depending on whether or not the snapshot should be animated
    if not h.is_empty(self.config.image_field) then
        local source_path = mp.get_property("path")
        local output_path = utils.join_path(self.output_dir_path, filename)

        local on_finish_wrap = report_creation_result(output_path).on_finish(on_finish_fn)
        if self.config.animated_snapshot_enabled then
            create_animated_snapshot(start_timestamp, end_timestamp, source_path, output_path, on_finish_wrap.run)
        else
            create_static_snapshot(current_timestamp, source_path, output_path, on_finish_wrap.run)
        end
    else
        print("Snapshot will not be created.")
    end
end

local create_audio = function(start_timestamp, end_timestamp, filename, padding, on_finish_fn)
    if h.is_empty(self.output_dir_path) then
        return msg.error("Output directory wasn't provided. Audio file will not be created.")
    end

    if not h.is_empty(self.config.audio_field) then
        local source_path = mp.get_property("path")
        local output_path = utils.join_path(self.output_dir_path, filename)

        if padding > 0 then
            start_timestamp, end_timestamp = pad_timings(padding, start_timestamp, end_timestamp)
        end

        --- Start encoding and forward its completion to the media reporter.
        local function start_encoding(args)
            local completion = report_creation_result(output_path)
                    .on_finish(on_finish_fn)
                    .preview_audio(self.config.preview_audio)
            h.subprocess { args = args, completion_fn = completion.run }
        end

        self.encoder.make_audio_args(
                source_path, output_path, start_timestamp, end_timestamp, start_encoding
        )
    else
        print("Audio will not be created.")
    end
end

local make_snapshot_filename = function(start_time, end_time, timestamp)
    -- Generate a filename for the snapshot, taking care of its extension and whether it's animated or static
    if self.config.animated_snapshot_enabled then
        return filename_factory.make_filename(start_time, end_time, self.config.animated_snapshot_extension)
    else
        return filename_factory.make_filename(timestamp, self.config.snapshot_extension)
    end
end

local make_audio_filename = function(start_time, end_time)
    -- Generates a filename for the audio
    return filename_factory.make_filename(start_time, end_time, self.config.audio_extension)
end

local create_job = function(job_type, sub, audio_padding)
    local current_timestamp, on_finish_fn
    local job = {}
    if job_type == 'snapshot' and h.has_video_track() and not h.is_empty(self.config.image_field) then
        current_timestamp = mp.get_property_number("time-pos", 0)
        job.filename = make_snapshot_filename(sub['start'], sub['end'], current_timestamp)
        job.run_async = function()
            create_snapshot(sub['start'], sub['end'], current_timestamp, job.filename, on_finish_fn)
        end
    elseif job_type == 'audioclip' and h.has_audio_track() and not h.is_empty(self.config.audio_field) then
        job.filename = make_audio_filename(sub['start'], sub['end'])
        job.run_async = function()
            create_audio(sub['start'], sub['end'], job.filename, audio_padding, on_finish_fn)
        end
    else
        job.filename = nil
        job.run_async = function()
            print(job_type .. " will not be created.")
            if type(on_finish_fn) == 'function' then
                -- No media track or configured field: this is a skipped job, not a failure.
                on_finish_fn(nil, nil)
            end
        end
    end
    job.on_finish = function(fn)
        on_finish_fn = fn
        return job
    end
    return job
end

------------------------------------------------------------
-- public interface

local public = {
    snapshot = {},
    audio = {},
}

function public.encoder()
    return self.encoder
end

function public.init(cfg_mgr)
    -- Sets the module to its preconfigured status
    cfg_mgr.fail_if_not_ready()
    self.cfg_mgr = cfg_mgr
    self.config = cfg_mgr.config()
    self.encoder = self.config.use_ffmpeg and ffmpeg_encoder.new(cfg_mgr) or mpv_encoder.new(cfg_mgr)
    self.encoder.set_avif_encoder()
end

function public.set_output_dir(dir_path)
    -- Set directory where media files should be saved.
    -- This function is called every time a card is created or updated.
    self.output_dir_path = dir_path
end

function public.snapshot.create_job(sub)
    return create_job('snapshot', sub)
end

function public.snapshot.toggle_animation()
    -- Toggles on and off animated snapshot generation at runtime. It is called whenever ctrl+g is pressed
    self.config.animated_snapshot_enabled = not self.config.animated_snapshot_enabled
    h.notify("Animation " .. (self.config.animated_snapshot_enabled and "enabled" or "disabled"), "info", 2)
end

function public.audio.create_job(subtitle, padding)
    return create_job('audioclip', subtitle, padding)
end

------------------------------------------------------------
--- Tests: executed by both standalone and mpv-backed runners.

--- Record reporter messages without printing expected test failures.
local function make_encoder_test_logger(state)
    return {
        info = function(message)
            state.level, state.message, state.count = 'info', message, state.count + 1
        end,
        error = function(message)
            state.level, state.message, state.count = 'error', message, state.count + 1
        end,
    }
end

--- Check that a reporter emitted one expected test message.
local function assert_encoder_test_log(log, case)
    h.assert_equals(log.count, 1)
    h.assert_equals(log.level, case.expected_error and 'error' or 'info')
    h.assert_equals(log.message, case.expected_error or 'Created file: output.ogg')
end

--- Check one reporter outcome without launching an audio preview subprocess.
local function assert_creation_result_test_case(case)
    local completed_path, completed_error, previewed_path
    local log = { count = 0 }
    local components = {
        file_exists = function(path)
            h.assert_equals(path, 'output.ogg')
            return case.exists
        end,
        play_audio = function(path)
            previewed_path = path
        end,
        logger = make_encoder_test_logger(log),
    }
    --- Capture the reported result without writing media files.
    local function on_finish(path, error)
        completed_path, completed_error = path, error
    end
    local completion = report_creation_result('output.ogg', components)
            .on_finish(on_finish)
            .preview_audio(case.preview)
    h.assert_equals(completion.run(case.success, case.result, case.error), nil)
    h.assert_equals(completed_path, case.expected_path)
    h.assert_equals(completed_error, case.expected_error)
    h.assert_equals(previewed_path, case.expected_preview)
    assert_encoder_test_log(log, case)
end

--- Verify completion outcomes and preview playback share the media reporter.
local function test_report_creation_result()
    for _, case in ipairs {
        { success = true, result = { status = 0 }, exists = true, preview = true,
          expected_path = 'output.ogg', expected_preview = 'output.ogg' },
        { success = true, exists = true, preview = false, expected_path = 'output.ogg' },
        { success = true, result = { status = 0 }, exists = false, preview = true,
          expected_error = "Couldn't create file: output.ogg" },
        { success = false, result = { status = 1 }, error = 'encoder exited', preview = true,
          expected_error = 'encoder exited' },
    } do
        assert_creation_result_test_case(case)
    end
end

--- Run encoder completion-contract tests.
function public.run_tests()
    test_report_creation_result()
end

return public
