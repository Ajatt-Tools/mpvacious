--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Encoder tests.
]]

local h = require("helpers")
local encoder = require("encoder.encoder")
local fixtures = require("tests.fixtures")
local defaults = require("config.defaults")
local config_utils = require("config.utils")
local ffmpeg_backend = require("encoder.ffmpeg")
local mpv_backend = require("encoder.mpv")
local snapshot = require("config.snapshot")
local subtitle = require("subtitles.subtitle")
local executables = require("encoder.executables")
local eutils = require("encoder.utils")
local note_update_context = require("anki.note_update_context")

--- Record reporter messages without printing expected test failures.
local function make_encoder_test_logger(state)
    return {
        --- Record a successful media-creation message.
        info = function(message)
            state.level, state.message, state.count = "info", message, state.count + 1
        end,
        --- Record an expected media-creation failure message.
        error = function(message)
            state.level, state.message, state.count = "error", message, state.count + 1
        end,
    }
end

--- Check that a reporter emitted one expected test message.
local function assert_encoder_test_log(log, case)
    h.assert_equals(log.count, 1)
    h.assert_equals(log.level, case.expected_error and "error" or "info")
    h.assert_equals(log.message, case.expected_error or "Created file: output.ogg")
end

--- Check one reporter outcome without launching an audio preview subprocess.
local function assert_creation_result_test_case(case)
    local completed_path, completed_error, previewed_path
    local log = { count = 0 }
    local components = {
        --- Return the scenario's file-existence result for the expected path.
        file_exists = function(path)
            h.assert_equals(path, "output.ogg")
            return case.exists
        end,
        --- Record an audio preview without launching playback.
        play_audio = function(path)
            previewed_path = path
        end,
        logger = make_encoder_test_logger(log),
    }
    --- Capture the reported result without writing media files.
    local function on_finish(path, error)
        completed_path, completed_error = path, error
    end
    local completion =
        encoder.report_creation_result("output.ogg", components).on_finish(on_finish).preview_audio(case.preview)
    h.assert_equals(completion.run(case.success, case.result, case.error), nil)
    h.assert_equals(completed_path, case.expected_path)
    h.assert_equals(completed_error, case.expected_error)
    h.assert_equals(previewed_path, case.expected_preview)
    assert_encoder_test_log(log, case)
end

--- Verify completion outcomes and preview playback share the media reporter.
local function test_report_creation_result()
    for _, case in ipairs {
        {
            success = true,
            result = { status = 0 },
            exists = true,
            preview = true,
            expected_path = "output.ogg",
            expected_preview = "output.ogg",
        },
        { success = true, exists = true, preview = false, expected_path = "output.ogg" },
        {
            success = true,
            result = { status = 0 },
            exists = false,
            preview = true,
            expected_error = "Couldn't create file: output.ogg",
        },
        {
            success = false,
            result = { status = 1 },
            error = "encoder exited",
            preview = true,
            expected_error = "encoder exited",
        },
    } do
        assert_creation_result_test_case(case)
    end
end

--- Build validated codec settings for backend initialization scenarios.
local function make_backend_test_config(snapshot_format, animation_format, use_ffmpeg)
    local config = defaults.get_default()
    config.snapshot_format = snapshot_format
    config.animated_snapshot_format = animation_format
    config.use_ffmpeg = use_ffmpeg
    config_utils.validate_config(config)
    return config
end

--- Assert the codecs used by public still and animated command builders.
local function assert_backend_test_codecs(backend, still_codec, animated_codec)
    local still = backend.make_static_snapshot_args("source.mkv", "still.image", 1)
    local animated = backend.make_animated_snapshot_args("source.mkv", "animated.image", 0, 1)
    h.assert_equals(fixtures.backend_test_command_codec(still), still_codec)
    h.assert_equals(fixtures.backend_test_command_codec(animated), animated_codec)
end

--- Verify separately initialized encoders retain independent backend behavior.
local function test_encoder_instances_are_isolated()
    local first_config = make_backend_test_config("webp", "webp", false)
    local second_config = make_backend_test_config("jpg", "webp", true)
    local first = encoder.new()
    local second = encoder.new()
    first.init(fixtures.make_config_manager(first_config))
    second.init(fixtures.make_config_manager(second_config))
    h.assert_equals(first.encoder() == second.encoder(), false)
    assert_backend_test_codecs(first.encoder(), "libwebp", "libwebp")
    assert_backend_test_codecs(second.encoder(), "mjpeg", "libwebp")
end

--- Check selection, fallback, and non-AVIF codecs without exposing private state.
local function assert_backend_codec_test_case(make_backend, case)
    local config = make_backend_test_config(case.still, case.animated, false)
    local original = h.deep_copy(config)
    local backend = fixtures.make_backend_codec_test_context(make_backend, config, case.supported)
    h.assert_equals(fixtures.backend_test_public_keys(backend), {
        "init",
        "make_animated_snapshot_args",
        "make_audio_args",
        "make_static_snapshot_args",
    })
    backend.init()
    backend.init()
    assert_backend_test_codecs(backend, case.expected_still, case.expected_animated)
    h.assert_equals(config, original)
end

--- Verify both backends initialize local codecs and leave configuration untouched.
local function test_backend_codec_initialization()
    local cases = {
        {
            still = "avif",
            animated = "avif",
            supported = { ["libsvtav1"] = true, ["libaom-av1"] = true },
            expected_still = "libsvtav1",
            expected_animated = "libsvtav1",
        },
        {
            still = "avif",
            animated = "avif",
            supported = {},
            expected_still = "libaom-av1",
            expected_animated = "libaom-av1",
        },
        {
            still = "avif",
            animated = "webp",
            supported = { ["libsvtav1"] = true },
            expected_still = "libsvtav1",
            expected_animated = "libwebp",
        },
        {
            still = "jpg",
            animated = "avif",
            supported = { ["libsvtav1"] = true },
            expected_still = "mjpeg",
            expected_animated = "libsvtav1",
        },
        {
            still = "webp",
            animated = "webp",
            supported = { ["libsvtav1"] = true },
            expected_still = "libwebp",
            expected_animated = "libwebp",
        },
    }
    for _, make_backend in ipairs { ffmpeg_backend.new, mpv_backend.new } do
        for _, case in ipairs(cases) do
            assert_backend_codec_test_case(make_backend, case)
        end
    end
end

--- Verify reloads refresh private codecs when the manager replaces its config table.
local function test_backend_codecs_refresh_on_reload()
    for _, make_backend in ipairs { ffmpeg_backend.new, mpv_backend.new } do
        local config = make_backend_test_config("avif", "avif", false)
        local backend, state = fixtures.make_backend_codec_test_context(make_backend, config, { ["libsvtav1"] = true })
        backend.init()
        assert_backend_test_codecs(backend, "libsvtav1", "libsvtav1")
        state.config = make_backend_test_config("jpg", "webp", false)
        local original = h.deep_copy(state.config)
        backend.init()
        assert_backend_test_codecs(backend, "mjpeg", "libwebp")
        h.assert_equals(state.config, original)
        state.config = make_backend_test_config("avif", "avif", false)
        backend.init()
        assert_backend_test_codecs(backend, "libsvtav1", "libsvtav1")
    end
end

--- Verify instance construction returns public methods and selects the supplied backend.
local function assert_encoder_constructor_test_case(use_ffmpeg)
    local original_config = make_backend_test_config("webp", "webp", not use_ffmpeg)
    local original = encoder.new()
    h.assert_equals(original.init(fixtures.make_config_manager(original_config)), original)
    local config = make_backend_test_config("jpg", "webp", use_ffmpeg)
    local fresh = original.new(snapshot.new(fixtures.make_config_manager(config)))
    h.assert_equals(fresh == original, false)
    h.assert_equals(fresh.encoder() == original.encoder(), false)
    config.snapshot_format, config.snapshot_codec = "webp", "libwebp"
    assert_backend_test_codecs(fresh.encoder(), "mjpeg", "libwebp")
    assert_backend_test_codecs(original.encoder(), "libwebp", "libwebp")
    local command = fresh.encoder().make_static_snapshot_args("source.mkv", "still.jpg", 1)
    local executable = executables.mpv
    if use_ffmpeg then executable = executables.ffmpeg end
    h.assert_equals(command[1], executable)
end

--- Verify both backend choices work through the encoder's instance constructor.
local function test_encoder_instance_constructors()
    for _, use_ffmpeg in ipairs { false, true } do
        assert_encoder_constructor_test_case(use_ffmpeg)
    end
end

--- Verify reconstructed encoders preserve fake I/O but own separate output directories.
local function test_encoder_instance_output_directories()
    for _, use_ffmpeg in ipairs { false, true } do
        local state = { commands = {} }
        local config = make_backend_test_config("jpg", "webp", use_ffmpeg)
        local cfg_mgr = fixtures.make_config_manager(config)
        local original = encoder.new(fixtures.make_recording_encoder_components(state)).init(cfg_mgr)
        original.set_output_dir("/original-media")
        local fresh = original.new(snapshot.new(cfg_mgr))
        fresh.set_output_dir("/request-media")
        original.set_output_dir("/later-media")
        local sub = subtitle.make_subtitle("Line", 0, 1)
        fresh.snapshot.create_job(sub).run_async()
        original.snapshot.create_job(sub).run_async()
        h.assert_equals(#state.commands, 2)
        h.assert_equals(fixtures.encoder_test_output_path(state.commands[1]), "/request-media/encoder-test.jpg")
        h.assert_equals(fixtures.encoder_test_output_path(state.commands[2]), "/later-media/encoder-test.jpg")
    end
end

--- Honor explicit snapshot times, including zero, and retain the current-time default.
local function test_snapshot_job_captures_explicit_timestamp()
    for _, use_ffmpeg in ipairs { false, true } do
        local state = { commands = {} }
        local components = fixtures.make_recording_encoder_components(state)
        components.mp = fixtures.make_mp_property_reader { path = "encoder-test.mkv", ["time-pos"] = 125 }
        local cfg_mgr = fixtures.make_config_manager(make_backend_test_config("jpg", "webp", use_ffmpeg))
        local instance = encoder.new(components).init(snapshot.new(cfg_mgr))
        instance.set_output_dir("/request-media")
        instance.snapshot.create_job(subtitle.make_subtitle("Line", 0, 1), 65).run_async()
        h.assert_equals(fixtures.encoder_test_snapshot_timestamp(state.commands[1]), "65.000")
        instance.snapshot.create_job(subtitle.make_subtitle("Line", 0, 1), 0).run_async()
        h.assert_equals(fixtures.encoder_test_snapshot_timestamp(state.commands[2]), "0.000")
        instance.snapshot.create_job(subtitle.make_subtitle("Line", 0, 1)).run_async()
        h.assert_equals(fixtures.encoder_test_snapshot_timestamp(state.commands[3]), "125.000")
    end
end

--- Reject construction from an unready manager without changing the original encoder.
local function test_encoder_constructor_requires_ready_manager()
    local original = encoder.new().init(fixtures.make_config_manager(make_backend_test_config("jpg", "webp", false)))
    local cfg_mgr = fixtures.make_config_manager({})
    cfg_mgr.fail_if_not_ready = h.as_callback(error, "config not loaded")
    local success, error = pcall(original.new, cfg_mgr)
    h.assert_equals(success, false)
    h.assert_equals(h.is_substr(error, "config not loaded"), true)
    assert_backend_test_codecs(original.encoder(), "mjpeg", "libwebp")
end

--- Build a normalization profile with distinctive original encoding and user arguments.
local function make_loudnorm_profile_test_config(audio_format)
    local config = make_backend_test_config("jpg", "webp", false)
    config.audio_format = audio_format
    config.opus_container = "m4a"
    config.audio_bitrate = "32k"
    config.loudnorm = true
    config.ffmpeg_audio_args = "-ar 24000 -af highpass=f=80"
    config.mpv_audio_args = "--audio-samplerate=24000 --speed=1.25"
    config_utils.validate_config(config)
    return config
end

--- Change all settings consulted between analysis and final command generation.
local function change_loudnorm_profile_test_config(config)
    local audio_format = "opus"
    if config.audio_format == "opus" then audio_format = "mp3" end
    h.shallow_copy({
        audio_format = audio_format,
        opus_container = "webm",
        audio_bitrate = "96k",
        loudnorm = false,
        loudnorm_target = -9,
        loudnorm_range = 4,
        loudnorm_peak = -0.5,
        ffmpeg_audio_args = "-ar 48000 -af lowpass=f=5000",
        mpv_audio_args = "--audio-samplerate=48000 --speed=2",
    }, config)
    config_utils.validate_config(config)
end

--- Assert successful and fallback analysis both retain the original normalization targets.
local function assert_loudnorm_profile_test_filter(args, case, success)
    local filter = fixtures.encoder_test_option_value(args, case.filter_option)
    h.assert_equals(h.is_substr(filter, "loudnorm=I=-16:LRA=11:TP=-1.5:dual_mono=true"), true)
    h.assert_equals(h.is_substr(filter, "measured_I=-20"), success)
    if case.make_backend == ffmpeg_backend.new then
        h.assert_equals(h.is_substr(filter, "highpass=f=80"), true)
        h.assert_equals(h.is_substr(filter, "lowpass=f=5000"), false)
    else
        h.assert_equals(fixtures.encoder_test_option_value(args, "--speed"), "1.25")
    end
end

--- Verify original codecs, containers, bitrate, custom arguments, and analysis outcomes.
local function assert_loudnorm_profile_test_command(state, case, config, success)
    h.assert_equals(#state.encoding, 1)
    local args = state.encoding[1]
    h.assert_equals(fixtures.encoder_test_option_value(args, case.codec_option), config.audio_codec)
    h.assert_equals(fixtures.encoder_test_option_value(args, case.bitrate_option), "32k")
    h.assert_equals(fixtures.encoder_test_option_value(args, case.rate_option), "24000")
    if config.audio_format == "opus" then
        h.assert_equals(fixtures.encoder_test_option_value(args, case.container_option), "mp4")
    end
    assert_loudnorm_profile_test_filter(args, case, success)
    local warnings = {}
    if not success then
        warnings = { "Failed to measure loudnorm stats, falling back on dynamic loudnorm." }
    end
    h.assert_equals(state.warnings, warnings)
    local parsed_count = 0
    if success then parsed_count = 1 end
    h.assert_equals(state.parsed_json_count or 0, parsed_count)
end

--- Complete deferred analysis after a profile change and compare against an unchanged reference.
local function assert_loudnorm_profile_isolation_test_case(case, audio_format, success)
    local live = make_loudnorm_profile_test_config(audio_format)
    local original = h.deep_copy(live)
    local _, reference =
        fixtures.make_loudnorm_test_context(case.make_backend, fixtures.make_config_manager(h.deep_copy(original)))
    fixtures.complete_loudnorm_test_analysis(reference, success)
    local _, state =
        fixtures.make_loudnorm_test_context(case.make_backend, snapshot.new(fixtures.make_config_manager(live)))
    h.assert_equals(#state.analysis, 1)
    h.assert_equals(state.encoding, {})
    h.assert_equals(state.analysis[1].args, reference.analysis[1].args)
    change_loudnorm_profile_test_config(live)
    fixtures.complete_loudnorm_test_analysis(state, success)
    h.assert_equals(state.encoding, reference.encoding)
    assert_loudnorm_profile_test_command(state, case, original, success)
end

--- Verify both backend command stages retain captured profiles on success and fallback.
local function test_loudnorm_profile_isolation()
    local cases = {
        {
            make_backend = ffmpeg_backend.new,
            codec_option = "-c:a",
            bitrate_option = "-b:a",
            container_option = "-f",
            filter_option = "-af",
            rate_option = "-ar",
        },
        {
            make_backend = mpv_backend.new,
            codec_option = "--oac",
            bitrate_option = "--oacopts-add=b",
            container_option = "--of",
            filter_option = "--af-append",
            rate_option = "--audio-samplerate",
        },
    }
    for _, case in ipairs(cases) do
        for _, audio_format in ipairs { "opus", "mp3" } do
            for _, success in ipairs { true, false } do
                assert_loudnorm_profile_isolation_test_case(case, audio_format, success)
            end
        end
    end
end

--- Give static and animated profiles intentionally different formats, quality, and dimensions.
local function make_cover_snapshot_test_config(format, use_ffmpeg, animated)
    local config = make_backend_test_config(format, "avif", use_ffmpeg)
    config.snapshot_quality, config.snapshot_height = 40, 240
    config.animated_snapshot_quality, config.animated_snapshot_height = 8, 120
    config.animated_snapshot_enabled = animated
    config_utils.validate_config(config)
    return config
end

--- Assert static dimensions and format-specific quality are retained in cover commands.
local function assert_cover_static_profile_test_args(args, config, use_ffmpeg)
    local command = table.concat(args, " ")
    h.assert_equals(h.is_substr(command, eutils.static_scale_filter(config)), true)
    local option, expected
    if config.snapshot_format == "avif" then
        option, expected = "--ovcopts-add=crf", tostring(eutils.quality_to_crf_avif(40))
        if use_ffmpeg then option = "-crf" end
    elseif config.snapshot_format == "webp" then
        option, expected = "--ovcopts-add=quality", "40"
        if use_ffmpeg then option = "-quality" end
    else
        option, expected =
            "--ovcopts", string.format("global_quality=%d*QP2LAMBDA,flags=+qscale", eutils.quality_to_jpeg_qscale(40))
        if use_ffmpeg then
            option, expected = "-q:v", tostring(eutils.quality_to_jpeg_qscale(40))
        end
    end
    h.assert_equals(fixtures.encoder_test_option_value(args, option), expected)
end

--- Verify timed video still seeks and selected covers are extracted without seeking.
local function assert_cover_backend_test_case(case, format, track)
    local config = make_cover_snapshot_test_config(format, case.use_ffmpeg, true)
    local original = h.deep_copy(config)
    local backend = fixtures.make_cover_backend_test_context(case.make_backend, config, track)
    local args = backend.make_static_snapshot_args("source.m4b", "snapshot" .. config.snapshot_extension, 65, track)
    local seek, selection = eutils.toms(65), nil
    if track.albumart then
        seek = nil
        selection = tostring(track.id or "auto")
        if case.use_ffmpeg then
            selection = "0:v:0"
            if track["ff-index"] ~= nil then selection = "0:" .. tostring(track["ff-index"]) end
        end
    end
    h.assert_equals(fixtures.encoder_test_option_value(args, case.seek), seek)
    h.assert_equals(fixtures.encoder_test_option_value(args, case.selection), selection)
    h.assert_equals(fixtures.backend_test_command_codec(args), config.snapshot_codec)
    assert_cover_static_profile_test_args(args, config, case.use_ffmpeg)
    h.assert_equals(config, original)
end

--- Test both static backends with ordinary video, explicit covers, and missing stream identifiers.
local function test_cover_backend_static_args()
    local cases = {
        { make_backend = ffmpeg_backend.new, use_ffmpeg = true, seek = "-ss", selection = "-map" },
        { make_backend = mpv_backend.new, use_ffmpeg = false, seek = "--start", selection = "--vid" },
    }
    for _, case in ipairs(cases) do
        for _, format in ipairs { "jpg", "webp", "avif" } do
            for _, track in ipairs {
                { type = "video", selected = true, id = 7, ["ff-index"] = 2, albumart = false },
                { type = "video", selected = true, id = 7, ["ff-index"] = 2, albumart = true },
                { type = "video", selected = true, albumart = true },
            } do
                assert_cover_backend_test_case(case, format, track)
            end
        end
    end
end

--- Retain range timing and animation filters for ordinary video.
local function assert_normal_animated_job_test_args(args, config, use_ffmpeg)
    local seek, finish, frames = "--start", "--end", "--frames"
    if use_ffmpeg then
        seek, finish, frames = "-ss", "-to", "-frames:v"
    end
    h.assert_equals(fixtures.encoder_test_option_value(args, seek), eutils.toms(60))
    h.assert_equals(fixtures.encoder_test_option_value(args, finish), eutils.toms(70))
    h.assert_equals(fixtures.encoder_test_option_value(args, frames), nil)
    local command = table.concat(args, " ")
    h.assert_equals(h.is_substr(command, eutils.animated_scale_filter(config)), true)
    h.assert_equals(h.is_substr(command, "fps=" .. tostring(config.animated_snapshot_fps)), true)
end

--- Assert encoded covers use static commands while ordinary video retains animation.
local function assert_cover_encoded_job_test_args(args, config, case)
    if case.animated and not case.albumart then
        assert_normal_animated_job_test_args(args, config, case.use_ffmpeg)
        return
    end
    assert_cover_static_profile_test_args(args, config, case.use_ffmpeg)
    if case.albumart then
        h.assert_equals(fixtures.encoder_test_option_value(args, "-ss"), nil)
        h.assert_equals(fixtures.encoder_test_option_value(args, "--start"), nil)
        local selection, expected = "--vid", "7"
        if case.use_ffmpeg then
            selection, expected = "-map", "0:2"
        end
        h.assert_equals(fixtures.encoder_test_option_value(args, selection), expected)
    end
end

--- Assert only ordinary animated video uses range timing and the animated extension.
local function assert_cover_snapshot_job_test_result(state, job, config, case)
    local animated = case.animated and not case.albumart
    local extension = config.snapshot_extension
    if animated then extension = config.animated_snapshot_extension end
    h.assert_equals(job.filename, "snapshot" .. extension)
    local filename_args = { 65, extension }
    if animated then filename_args = { 60, 70, extension } end
    h.assert_equals(state.filename_args, { filename_args })
    if case.screenshot and not animated then
        h.assert_equals(state.commands, {})
        h.assert_equals(state.screenshots, { { "screenshot-to-file", "/test-media/" .. job.filename, "video" } })
        return
    end
    h.assert_equals(state.screenshots, {})
    h.assert_equals(#state.commands, 1)
    local args = state.commands[1]
    h.assert_equals(fixtures.encoder_test_output_path(args), "/test-media/" .. job.filename)
    assert_cover_encoded_job_test_args(args, config, case)
end

--- Verify animation requests on cover-only sources use static filenames and settings.
local function assert_cover_snapshot_job_test_case(case, format)
    local config = make_cover_snapshot_test_config(format, case.use_ffmpeg, case.animated)
    config.screenshot = case.screenshot
    local original = h.deep_copy(config)
    local state = { commands = {}, screenshots = {}, filename_args = {} }
    local track = { type = "video", selected = true, albumart = case.albumart, id = 7, ["ff-index"] = 2 }
    local instance = encoder
        .new(fixtures.make_cover_encoder_test_components(state, track))
        .init(fixtures.make_config_manager(config))
    instance.set_output_dir("/test-media")
    local job = instance.snapshot.create_job(subtitle.make_subtitle("Line", 60, 70))
    job.run_async()
    assert_cover_snapshot_job_test_result(state, job, config, case)
    h.assert_equals(config, original)
end

--- Exercise static covers regardless of animation preference and preserve native screenshot behavior.
local function test_cover_snapshot_jobs_use_static_settings()
    for _, use_ffmpeg in ipairs { false, true } do
        for _, animated in ipairs { false, true } do
            for _, format in ipairs { "jpg", "webp", "avif" } do
                assert_cover_snapshot_job_test_case({
                    use_ffmpeg = use_ffmpeg,
                    albumart = true,
                    animated = animated,
                    screenshot = false,
                }, format)
            end
            for _, albumart in ipairs { false, true } do
                assert_cover_snapshot_job_test_case({
                    use_ffmpeg = use_ffmpeg,
                    albumart = albumart,
                    animated = animated,
                    screenshot = true,
                }, "jpg")
            end
        end
    end
end

--- Keep each deferred media job's destination independent of later parent directory changes.
local function assert_media_job_directory_test_case(media_type, use_ffmpeg)
    local state = { commands = {} }
    local config = make_backend_test_config("jpg", "webp", use_ffmpeg)
    config.loudnorm = false
    local instance =
        encoder.new(fixtures.make_recording_audio_encoder_components(state)).init(fixtures.make_config_manager(config))
    local sub = subtitle.make_subtitle("Line", 0, 1)
    instance.set_output_dir("/first-media")
    local first = instance[media_type].create_job(sub, 0)
    instance.set_output_dir("/second-media")
    local second = instance[media_type].create_job(sub, 0)
    first.run_async()
    second.run_async()
    h.assert_equals(fixtures.encoder_test_output_path(state.commands[1]), "/first-media/" .. first.filename)
    h.assert_equals(fixtures.encoder_test_output_path(state.commands[2]), "/second-media/" .. second.filename)
end

--- Verify snapshot and audio closures capture their own output directory on both backends.
local function test_media_jobs_capture_output_directory()
    for _, use_ffmpeg in ipairs { false, true } do
        for _, media_type in ipairs { "snapshot", "audio" } do
            assert_media_job_directory_test_case(media_type, use_ffmpeg)
        end
    end
end

--- Assert a missing directory is reported as failure without executing a media command.
local function assert_media_missing_directory_test_result(state, log, with_callback, media_type)
    local label = "Image"
    if media_type == "audio" then label = "Audio" end
    local reason = "Output directory wasn't provided. " .. label .. " file will not be created."
    h.assert_equals(log, { count = 1, level = "error", message = reason })
    h.assert_equals(state.commands, {})
    if with_callback then
        h.assert_equals(state.completion_count, 1)
        h.assert_equals(state.completed_path, nil)
        h.assert_equals(state.completed_error, reason)
    else
        h.assert_equals(state.completion_count, nil)
    end
end

--- Missing destinations must report failure rather than successful skips, with optional callbacks.
local function assert_media_missing_directory_test_case(case, use_ffmpeg, media_type)
    local state, log = { commands = {} }, { count = 0 }
    local components = fixtures.make_recording_audio_encoder_components(state)
    components.logger = make_encoder_test_logger(log)
    local instance =
        encoder.new(components).init(fixtures.make_config_manager(make_backend_test_config("jpg", "webp", use_ffmpeg)))
    instance.set_output_dir(case.directory)
    local job = instance[media_type].create_job(subtitle.make_subtitle("Line", 0, 1), 0)
    if case.callback then job.on_finish(fixtures.make_media_result_test_recorder(state)) end
    h.assert_equals(pcall(job.run_async), true)
    assert_media_missing_directory_test_result(state, log, case.callback, media_type)
end

--- Cover missing and blank destinations with and without a completion callback on both backends.
local function test_media_jobs_missing_output_directory()
    for _, use_ffmpeg in ipairs { false, true } do
        for _, case in ipairs {
            {},
            { callback = true },
            { directory = "" },
            { directory = "", callback = true },
        } do
            for _, media_type in ipairs { "snapshot", "audio" } do
                assert_media_missing_directory_test_case(case, use_ffmpeg, media_type)
            end
        end
    end
end

--- Assert backend timing options without executing an audio encoder or animated snapshot.
local function assert_media_padding_test_timings(args, start_time, end_time, use_ffmpeg)
    local start_option, end_option = "--start", "--end"
    if use_ffmpeg then
        start_option, end_option = "-ss", "-to"
    end
    h.assert_equals(fixtures.encoder_test_option_value(args, start_option), eutils.toms(start_time))
    h.assert_equals(fixtures.encoder_test_option_value(args, end_option), eutils.toms(end_time))
end

--- Check padding affects only the audio command, not the caller, sibling snapshot, or filenames.
local function assert_audio_padding_test_result(state, sub, original, config, case, use_ffmpeg)
    h.assert_equals(sub, original)
    h.assert_equals(rawget(sub, "start"), case.start_time)
    h.assert_equals(rawget(sub, "end"), case.end_time)
    h.assert_equals(#state.commands, 2)
    assert_media_padding_test_timings(state.commands[1], case.padded_start, case.padded_end, use_ffmpeg)
    assert_media_padding_test_timings(state.commands[2], case.start_time, case.end_time, use_ffmpeg)
    h.assert_equals(state.filename_args, {
        { case.start_time, case.end_time, config.animated_snapshot_extension },
        { case.start_time, case.end_time, config.audio_extension },
    })
end

--- Execute padded audio before a sibling snapshot to expose accidental shared-subtitle mutation.
local function assert_audio_padding_ownership_test_case(case, use_ffmpeg)
    local state = { commands = {} }
    local config = make_backend_test_config("jpg", "webp", use_ffmpeg)
    config.loudnorm, config.animated_snapshot_enabled = false, true
    local instance =
        encoder.new(fixtures.make_recording_audio_encoder_components(state)).init(fixtures.make_config_manager(config))
    instance.set_output_dir("/request-media")
    local sub = subtitle.make_subtitle("Line", case.start_time, case.end_time)
    local original = h.deep_copy(sub)
    local snapshot_job = instance.snapshot.create_job(sub)
    local audio_job = instance.audio.create_job(sub, case.padding)
    audio_job.run_async()
    snapshot_job.run_async()
    assert_audio_padding_test_result(state, sub, original, config, case, use_ffmpeg)
end

--- Preserve caller-owned timing fields for zero padding, ordinary padding, and clamped boundaries.
local function test_audioclip_padding_owns_subtitle()
    for _, use_ffmpeg in ipairs { false, true } do
        for _, case in ipairs {
            { start_time = 3, end_time = 7, padding = 0, padded_start = 3, padded_end = 7 },
            { start_time = 3, end_time = 7, padding = 0.5, padded_start = 2.5, padded_end = 7.5 },
            { start_time = 0.1, end_time = 99.9, padding = 1, padded_start = 0, padded_end = 100 },
        } do
            assert_audio_padding_ownership_test_case(case, use_ffmpeg)
        end
    end
end

--- Assert skipped jobs perform no I/O and complete successfully only when a callback is registered.
local function assert_noop_encoder_test_result(state, media_type, with_callback)
    local label = "snapshot"
    if media_type == "audio" then label = "audioclip" end
    h.assert_equals(state.messages, { label .. " will not be created." })
    h.assert_equals(state.commands, {})
    h.assert_equals(state.filename_args, nil)
    h.assert_equals(state.failed_errors, nil)
    if with_callback then
        h.assert_equals(state.completion_count, 1)
        h.assert_equals(state.completed_path, nil)
        h.assert_equals(state.completed_error, nil)
        h.assert_equals(state.success_count, 1)
    else
        h.assert_equals(state.completion_count, nil)
        h.assert_equals(state.success_count, nil)
    end
end

--- Create a real skipped encoder job and optionally connect it to the real completion collector.
local function assert_noop_encoder_test_case(case, media_type, use_ffmpeg, with_callback)
    local state = { commands = {}, messages = {} }
    local config = make_backend_test_config("jpg", "webp", use_ffmpeg)
    local field = "image_field"
    if media_type == "audio" then field = "audio_field" end
    if case.skip_field then config[field] = case.field_value end
    local instance = encoder
        .new(fixtures.make_noop_encoder_test_components(state, case.has_track))
        .init(fixtures.make_config_manager(config))
    local job = instance[media_type].create_job(subtitle.make_subtitle("Line", 0, 1), 0)
    h.assert_equals(job.filename, nil)
    if with_callback then
        local callback = fixtures.make_recording_completion_test_callback(
            state,
            note_update_context.make_completion_collector,
            media_type
        )
        h.assert_equals(job.on_finish(callback), job)
    end
    h.assert_equals(pcall(job.run_async), true)
    assert_noop_encoder_test_result(state, media_type, with_callback)
end

--- Preserve successful skipped-job completion for absent tracks and blank or missing fields.
local function test_encoder_noop_jobs()
    for _, use_ffmpeg in ipairs { false, true } do
        for _, media_type in ipairs { "snapshot", "audio" } do
            for _, with_callback in ipairs { false, true } do
                for _, case in ipairs {
                    { has_track = false },
                    { has_track = true, skip_field = true, field_value = "" },
                    { has_track = true, skip_field = true },
                } do
                    assert_noop_encoder_test_case(case, media_type, use_ffmpeg, with_callback)
                end
            end
        end
    end
end

--- Run encoder completion, constructor, codec, normalization, and cover-art tests.
local function run_tests()
    test_report_creation_result()
    test_encoder_instances_are_isolated()
    test_backend_codec_initialization()
    test_backend_codecs_refresh_on_reload()
    test_encoder_instance_constructors()
    test_encoder_instance_output_directories()
    test_snapshot_job_captures_explicit_timestamp()
    test_encoder_constructor_requires_ready_manager()
    test_loudnorm_profile_isolation()
    test_cover_backend_static_args()
    test_cover_snapshot_jobs_use_static_settings()
    test_media_jobs_capture_output_directory()
    test_media_jobs_missing_output_directory()
    test_audioclip_padding_owns_subtitle()
    test_encoder_noop_jobs()
end

return {
    run_tests = run_tests,
}
