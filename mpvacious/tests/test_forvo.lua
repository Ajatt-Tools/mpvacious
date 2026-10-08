--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Forvo downloader dependency and existing-behavior tests.
]]

local h = require('helpers')
local base64 = require('utils.base64')
local fixtures = require('tests.fixtures')
local forvo = require('utils.forvo')

--- Create an isolated downloader with fake responses and a fresh recording state.
local function make_forvo_test_context(config, responses)
    local state = { requests = {}, encodings = {}, removed = {}, warnings = {} }
    local downloader = forvo.new(fixtures.make_forvo_dependencies(state, responses))
    downloader.init(fixtures.make_config_manager(config))
    downloader.set_output_dir('/anki-test-media')
    return downloader, state
end

--- Return pronunciation settings with independent source and destination formats.
local function make_forvo_test_config(case)
    return {
        use_forvo = 'yes',
        vocab_field = 'Word',
        vocab_audio_field = 'VocabAudio',
        audio_field = 'SentenceAudio',
        audio_format = case.audio_format,
        audio_extension = case.output_extension or '.' .. case.source_format,
        audio_codec = case.codec,
        audio_bitrate = '32k',
        audio_template = '[sound:%s]',
    }
end

--- Construct the page's MP3 and OGG download parameters without making a request.
local function make_forvo_test_page()
    return string.format("Play('%s','%s');", base64.enc('clip.mp3'), base64.enc('clip.ogg'))
end

--- Check source requests and temporary-file cleanup for one existing format.
local function assert_forvo_test_requests(state, case, filename)
    h.assert_equals(state.requests, {
        { '-s', 'https://forvo.com/search/word/ja' },
        { 'https://audio00.forvo.com/' .. case.source_format .. '/clip.' .. case.source_format,
          '-s', '-L', '-o', '/forvo-test-tmp/' .. filename },
    })
    h.assert_equals(state.removed, { '/forvo-test-tmp/' .. filename })
    h.assert_equals(state.warnings, {})
end

--- Check that introducing injection does not change existing encoder arguments.
local function assert_forvo_test_encoding(state, case, filename)
    h.assert_equals(state.encodings, { {
        'mpv', '/forvo-test-tmp/' .. filename, '--loop-file=no', '--keep-open=no', '--video=no',
        '--no-ocopy-metadata', '--no-sub', '--audio-channels=mono', '--oacopts-add=vbr=on',
        '--oacopts-add=application=voip', '--oacopts-add=compression_level=10',
        '--af-append=silenceremove=1:0:-50dB', '--oac=' .. case.codec, '--of=' .. case.audio_format,
        '--oacopts-add=b=32k', '-o=/anki-test-media/' .. filename,
    } })
end

--- Return source-selection cases for all configured pronunciation destination extensions.
local function make_pronunciation_format_test_cases()
    local cases = {
        { source_format = 'mp3', audio_format = 'mp3', codec = 'libmp3lame' },
    }
    for _, extension in ipairs { '.ogg', '.opus', '.m4a', '.webm', '.caf' } do
        table.insert(cases, {
            source_format = 'ogg',
            audio_format = 'opus',
            codec = 'libopus',
            output_extension = extension,
        })
    end
    return cases
end

--- Verify download-source selection is independent of the destination extension.
local function test_existing_pronunciation_flow()
    for _, case in ipairs(make_pronunciation_format_test_cases()) do
        local config = make_forvo_test_config(case)
        local downloader, state = make_forvo_test_context(config, {
            { status = 0, stdout = make_forvo_test_page() },
            { status = 0 },
        })
        local fields = { SentenceAudio = '[sound:sentence.ogg]' }
        downloader.append(fields, { Word = 'word', VocabAudio = '' })
        local filename = 'forvo_word' .. config.audio_extension
        h.assert_equals(fields, { SentenceAudio = '[sound:sentence.ogg]', VocabAudio = '[sound:' .. filename .. ']' })
        assert_forvo_test_requests(state, case, filename)
        assert_forvo_test_encoding(state, case, filename)
    end
end

--- A page with no pronunciation leaves generated fields unchanged and emits a warning.
local function test_missing_pronunciation()
    local config = make_forvo_test_config { source_format = 'ogg', audio_format = 'opus', codec = 'libopus' }
    local downloader, state = make_forvo_test_context(config, { { status = 0, stdout = 'No pronunciation' } })
    local fields = { SentenceAudio = '[sound:sentence.ogg]' }
    downloader.append(fields, { Word = 'word', VocabAudio = '' })
    h.assert_equals(fields, { SentenceAudio = '[sound:sentence.ogg]' })
    h.assert_equals(#state.requests, 1)
    h.assert_equals(state.encodings, {})
    h.assert_equals(state.removed, {})
    h.assert_equals(state.warnings, { "Seems like Forvo doesn't have audio for word word." })
end

--- Disabled pronunciation lookup performs no external work.
local function test_disabled_forvo()
    local config = make_forvo_test_config { source_format = 'ogg', audio_format = 'opus', codec = 'libopus' }
    config.use_forvo = 'no'
    local downloader, state = make_forvo_test_context(config, {})
    local fields = {}
    downloader.append(fields, { Word = 'word', VocabAudio = '' })
    h.assert_equals(fields, {})
    h.assert_equals(state.requests, {})
    h.assert_equals(state.encodings, {})
    h.assert_equals(state.removed, {})
    h.assert_equals(state.warnings, {})
end

--- Run the isolated downloader's baseline behavior tests.
local function run_tests()
    test_existing_pronunciation_flow()
    test_missing_pronunciation()
    test_disabled_forvo()
end

return { run_tests = run_tests }
