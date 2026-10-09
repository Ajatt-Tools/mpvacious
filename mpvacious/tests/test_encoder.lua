--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Encoder tests.
]]

local h = require('helpers')
local encoder = require('encoder.encoder')
local fixtures = require('tests.fixtures')

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

--- Verify separately initialized encoders retain their own backend and config.
local function test_encoder_instances_are_isolated()
    local first_config = fixtures.make_update_config { use_ffmpeg = false }
    local second_config = fixtures.make_update_config { use_ffmpeg = true }
    local first = encoder.new()
    local second = encoder.new()
    first.init(fixtures.make_config_manager(first_config))
    second.init(fixtures.make_config_manager(second_config))
    h.assert_equals(first.encoder() == second.encoder(), false)
    h.assert_equals(first.encoder().config == first_config, true)
    h.assert_equals(second.encoder().config == second_config, true)
end

--- Run encoder completion-contract tests.
local function run_tests()
    test_report_creation_result()
    test_encoder_instances_are_isolated()
end

return {
    run_tests = run_tests,
}
