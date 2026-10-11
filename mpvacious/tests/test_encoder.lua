--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Encoder tests.
]]

local h = require('helpers')
local encoder = require('encoder.encoder')
local fixtures = require('tests.fixtures')
local defaults = require('config.defaults')
local config_utils = require('config.utils')
local ffmpeg_backend = require('encoder.ffmpeg')
local mpv_backend = require('encoder.mpv')
local snapshot = require('config.snapshot')
local subtitle = require('subtitles.subtitle')
local executables = require('encoder.executables')

--- Record reporter messages without printing expected test failures.
local function make_encoder_test_logger(state)
    return {
        --- Record a successful media-creation message.
        info = function(message)
            state.level, state.message, state.count = 'info', message, state.count + 1
        end,
        --- Record an expected media-creation failure message.
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
        --- Return the scenario's file-existence result for the expected path.
        file_exists = function(path)
            h.assert_equals(path, 'output.ogg')
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
    local completion = encoder.report_creation_result('output.ogg', components)
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
    local still = backend.make_static_snapshot_args('source.mkv', 'still.image', 1)
    local animated = backend.make_animated_snapshot_args('source.mkv', 'animated.image', 0, 1)
    h.assert_equals(fixtures.backend_test_command_codec(still), still_codec)
    h.assert_equals(fixtures.backend_test_command_codec(animated), animated_codec)
end

--- Verify separately initialized encoders retain independent backend behavior.
local function test_encoder_instances_are_isolated()
    local first_config = make_backend_test_config('webp', 'webp', false)
    local second_config = make_backend_test_config('jpg', 'webp', true)
    local first = encoder.new()
    local second = encoder.new()
    first.init(fixtures.make_config_manager(first_config))
    second.init(fixtures.make_config_manager(second_config))
    h.assert_equals(first.encoder() == second.encoder(), false)
    assert_backend_test_codecs(first.encoder(), 'libwebp', 'libwebp')
    assert_backend_test_codecs(second.encoder(), 'mjpeg', 'libwebp')
end

--- Check selection, fallback, and non-AVIF codecs without exposing private state.
local function assert_backend_codec_test_case(make_backend, case)
    local config = make_backend_test_config(case.still, case.animated, false)
    local original = h.deep_copy(config)
    local backend = fixtures.make_backend_codec_test_context(make_backend, config, case.supported)
    h.assert_equals(fixtures.backend_test_public_keys(backend), {
        'init', 'make_animated_snapshot_args', 'make_audio_args', 'make_static_snapshot_args',
    })
    backend.init()
    backend.init()
    assert_backend_test_codecs(backend, case.expected_still, case.expected_animated)
    h.assert_equals(config, original)
end

--- Verify both backends initialize local codecs and leave configuration untouched.
local function test_backend_codec_initialization()
    local cases = {
        { still = 'avif', animated = 'avif', supported = { ['libsvtav1'] = true, ['libaom-av1'] = true },
          expected_still = 'libsvtav1', expected_animated = 'libsvtav1' },
        { still = 'avif', animated = 'avif', supported = {},
          expected_still = 'libaom-av1', expected_animated = 'libaom-av1' },
        { still = 'avif', animated = 'webp', supported = { ['libsvtav1'] = true },
          expected_still = 'libsvtav1', expected_animated = 'libwebp' },
        { still = 'jpg', animated = 'avif', supported = { ['libsvtav1'] = true },
          expected_still = 'mjpeg', expected_animated = 'libsvtav1' },
        { still = 'webp', animated = 'webp', supported = { ['libsvtav1'] = true },
          expected_still = 'libwebp', expected_animated = 'libwebp' },
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
        local config = make_backend_test_config('avif', 'avif', false)
        local backend, state = fixtures.make_backend_codec_test_context(
                make_backend, config, { ['libsvtav1'] = true }
        )
        backend.init()
        assert_backend_test_codecs(backend, 'libsvtav1', 'libsvtav1')
        state.config = make_backend_test_config('jpg', 'webp', false)
        local original = h.deep_copy(state.config)
        backend.init()
        assert_backend_test_codecs(backend, 'mjpeg', 'libwebp')
        h.assert_equals(state.config, original)
        state.config = make_backend_test_config('avif', 'avif', false)
        backend.init()
        assert_backend_test_codecs(backend, 'libsvtav1', 'libsvtav1')
    end
end

--- Verify instance construction returns public methods and selects the supplied backend.
local function assert_encoder_constructor_test_case(use_ffmpeg)
    local original_config = make_backend_test_config('webp', 'webp', not use_ffmpeg)
    local original = encoder.new()
    h.assert_equals(original.init(fixtures.make_config_manager(original_config)), original)
    local config = make_backend_test_config('jpg', 'webp', use_ffmpeg)
    local fresh = original.new(snapshot.new(fixtures.make_config_manager(config)))
    h.assert_equals(fresh == original, false)
    h.assert_equals(fresh.encoder() == original.encoder(), false)
    config.snapshot_format, config.snapshot_codec = 'webp', 'libwebp'
    assert_backend_test_codecs(fresh.encoder(), 'mjpeg', 'libwebp')
    assert_backend_test_codecs(original.encoder(), 'libwebp', 'libwebp')
    local command = fresh.encoder().make_static_snapshot_args('source.mkv', 'still.jpg', 1)
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
        local config = make_backend_test_config('jpg', 'webp', use_ffmpeg)
        local cfg_mgr = fixtures.make_config_manager(config)
        local original = encoder.new(fixtures.make_recording_encoder_components(state)).init(cfg_mgr)
        original.set_output_dir('/original-media')
        local fresh = original.new(snapshot.new(cfg_mgr))
        fresh.set_output_dir('/request-media')
        original.set_output_dir('/later-media')
        local sub = subtitle.make_subtitle('Line', 0, 1)
        fresh.snapshot.create_job(sub).run_async()
        original.snapshot.create_job(sub).run_async()
        h.assert_equals(#state.commands, 2)
        h.assert_equals(fixtures.encoder_test_output_path(state.commands[1]), '/request-media/encoder-test.jpg')
        h.assert_equals(fixtures.encoder_test_output_path(state.commands[2]), '/later-media/encoder-test.jpg')
    end
end

--- Reject construction from an unready manager without changing the original encoder.
local function test_encoder_constructor_requires_ready_manager()
    local original = encoder.new().init(fixtures.make_config_manager(make_backend_test_config('jpg', 'webp', false)))
    local cfg_mgr = fixtures.make_config_manager({})
    cfg_mgr.fail_if_not_ready = h.as_callback(error, 'config not loaded')
    local success, error = pcall(original.new, cfg_mgr)
    h.assert_equals(success, false)
    h.assert_equals(h.is_substr(error, 'config not loaded'), true)
    assert_backend_test_codecs(original.encoder(), 'mjpeg', 'libwebp')
end

--- Build a normalization profile with distinctive original encoding and user arguments.
local function make_loudnorm_profile_test_config(audio_format)
    local config = make_backend_test_config('jpg', 'webp', false)
    config.audio_format = audio_format
    config.opus_container = 'm4a'
    config.audio_bitrate = '32k'
    config.loudnorm = true
    config.ffmpeg_audio_args = '-ar 24000 -af highpass=f=80'
    config.mpv_audio_args = '--audio-samplerate=24000 --speed=1.25'
    config_utils.validate_config(config)
    return config
end

--- Change all settings consulted between analysis and final command generation.
local function change_loudnorm_profile_test_config(config)
    local audio_format = 'opus'
    if config.audio_format == 'opus' then audio_format = 'mp3' end
    h.shallow_copy({
        audio_format = audio_format, opus_container = 'webm', audio_bitrate = '96k',
        loudnorm = false, loudnorm_target = -9, loudnorm_range = 4, loudnorm_peak = -0.5,
        ffmpeg_audio_args = '-ar 48000 -af lowpass=f=5000',
        mpv_audio_args = '--audio-samplerate=48000 --speed=2',
    }, config)
    config_utils.validate_config(config)
end

--- Assert successful and fallback analysis both retain the original normalization targets.
local function assert_loudnorm_profile_test_filter(args, case, success)
    local filter = fixtures.encoder_test_option_value(args, case.filter_option)
    h.assert_equals(h.is_substr(filter, 'loudnorm=I=-16:LRA=11:TP=-1.5:dual_mono=true'), true)
    h.assert_equals(h.is_substr(filter, 'measured_I=-20'), success)
    if case.make_backend == ffmpeg_backend.new then
        h.assert_equals(h.is_substr(filter, 'highpass=f=80'), true)
        h.assert_equals(h.is_substr(filter, 'lowpass=f=5000'), false)
    else
        h.assert_equals(fixtures.encoder_test_option_value(args, '--speed'), '1.25')
    end
end

--- Verify original codecs, containers, bitrate, custom arguments, and analysis outcomes.
local function assert_loudnorm_profile_test_command(state, case, config, success)
    h.assert_equals(#state.encoding, 1)
    local args = state.encoding[1]
    h.assert_equals(fixtures.encoder_test_option_value(args, case.codec_option), config.audio_codec)
    h.assert_equals(fixtures.encoder_test_option_value(args, case.bitrate_option), '32k')
    h.assert_equals(fixtures.encoder_test_option_value(args, case.rate_option), '24000')
    if config.audio_format == 'opus' then
        h.assert_equals(fixtures.encoder_test_option_value(args, case.container_option), 'mp4')
    end
    assert_loudnorm_profile_test_filter(args, case, success)
    local warnings = {}
    if not success then
        warnings = { 'Failed to measure loudnorm stats, falling back on dynamic loudnorm.' }
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
    local _, reference = fixtures.make_loudnorm_test_context(
            case.make_backend, fixtures.make_config_manager(h.deep_copy(original))
    )
    fixtures.complete_loudnorm_test_analysis(reference, success)
    local _, state = fixtures.make_loudnorm_test_context(
            case.make_backend, snapshot.new(fixtures.make_config_manager(live))
    )
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
        { make_backend = ffmpeg_backend.new, codec_option = '-c:a', bitrate_option = '-b:a',
          container_option = '-f', filter_option = '-af', rate_option = '-ar' },
        { make_backend = mpv_backend.new, codec_option = '--oac', bitrate_option = '--oacopts-add=b',
          container_option = '--of', filter_option = '--af-append', rate_option = '--audio-samplerate' },
    }
    for _, case in ipairs(cases) do
        for _, audio_format in ipairs { 'opus', 'mp3' } do
            for _, success in ipairs { true, false } do
                assert_loudnorm_profile_isolation_test_case(case, audio_format, success)
            end
        end
    end
end

--- Run encoder completion, constructor, codec, and deferred normalization tests.
local function run_tests()
    test_report_creation_result()
    test_encoder_instances_are_isolated()
    test_backend_codec_initialization()
    test_backend_codecs_refresh_on_reload()
    test_encoder_instance_constructors()
    test_encoder_instance_output_directories()
    test_encoder_constructor_requires_ready_manager()
    test_loudnorm_profile_isolation()
end

return {
    run_tests = run_tests,
}
