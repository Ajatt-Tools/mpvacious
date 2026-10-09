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

--- Run encoder completion-contract tests.
local function run_tests()
    test_report_creation_result()
    test_encoder_instances_are_isolated()
    test_backend_codec_initialization()
    test_backend_codecs_refresh_on_reload()
end

return {
    run_tests = run_tests,
}
