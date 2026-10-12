--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Forvo downloader dependency and existing-behavior tests.
]]

local h = require("helpers")
local base64 = require("utils.base64")
local fixtures = require("tests.fixtures")
local forvo = require("utils.forvo")
local snapshot = require("config.snapshot")

--- Create an isolated downloader with fake responses and a fresh recording state.
local function make_forvo_test_context(config, responses)
    local state = { requests = {}, encodings = {}, removed = {}, warnings = {} }
    local downloader = forvo.new(fixtures.make_forvo_dependencies(state, responses))
    downloader.init(fixtures.make_config_manager(config))
    downloader.set_output_dir("/anki-test-media")
    return downloader, state
end

--- Return pronunciation settings with independent source and destination formats.
local function make_forvo_test_config(case)
    return {
        use_forvo = "yes",
        vocab_field = "Word",
        vocab_audio_field = "VocabAudio",
        audio_field = "SentenceAudio",
        audio_format = case.audio_format,
        audio_extension = case.output_extension or "." .. case.source_format,
        audio_codec = case.codec,
        audio_bitrate = "32k",
        audio_template = "[sound:%s]",
    }
end

--- Construct the page's MP3 and OGG download parameters without making a request.
local function make_forvo_test_page()
    return string.format("Play('%s','%s');", base64.enc("clip.mp3"), base64.enc("clip.ogg"))
end

--- Check source requests and temporary-file cleanup for one existing format.
local function assert_forvo_test_requests(state, case, filename)
    h.assert_equals(state.requests, {
        { "-f", "-s", "https://forvo.com/search/word/ja" },
        {
            "https://audio00.forvo.com/" .. case.source_format .. "/clip." .. case.source_format,
            "-f",
            "-s",
            "-L",
            "-o",
            "/forvo-test-tmp/" .. filename,
        },
    })
    h.assert_equals(state.removed, { "/forvo-test-tmp/" .. filename })
    h.assert_equals(state.warnings, {})
end

--- Check the selected codec, destination muxer, and output filename.
local function assert_forvo_test_encoding(state, case, filename, output_dir)
    output_dir = output_dir or "/anki-test-media"
    h.assert_equals(state.encodings, {
        {
            "mpv",
            "/forvo-test-tmp/" .. filename,
            "--loop-file=no",
            "--keep-open=no",
            "--video=no",
            "--no-ocopy-metadata",
            "--no-sub",
            "--audio-channels=mono",
            "--oacopts-add=vbr=on",
            "--oacopts-add=application=voip",
            "--oacopts-add=compression_level=10",
            "--af-append=silenceremove=1:0:-50dB",
            "--oac=" .. case.codec,
            "--of=" .. case.output_muxer,
            "--oacopts-add=b=32k",
            "-o=" .. output_dir .. "/" .. filename,
        },
    })
end

--- Return source-selection cases for all configured pronunciation destination extensions.
local function make_pronunciation_format_test_cases()
    local cases = {
        { source_format = "mp3", audio_format = "mp3", codec = "libmp3lame", output_muxer = "mp3" },
    }
    local muxers = { ogg = "ogg", opus = "ogg", m4a = "mp4", webm = "webm", caf = "caf" }
    for _, extension in ipairs { ".ogg", ".opus", ".m4a", ".webm", ".caf" } do
        table.insert(cases, {
            source_format = "ogg",
            audio_format = "opus",
            codec = "libopus",
            output_extension = extension,
            output_muxer = muxers[extension:sub(2)],
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
        local fields = { SentenceAudio = "[sound:sentence.ogg]" }
        downloader.append(fields, { Word = "word", VocabAudio = "" })
        local filename = "forvo_word" .. config.audio_extension
        h.assert_equals(fields, { SentenceAudio = "[sound:sentence.ogg]", VocabAudio = "[sound:" .. filename .. "]" })
        assert_forvo_test_requests(state, case, filename)
        assert_forvo_test_encoding(state, case, filename)
    end
end

--- A page with no pronunciation leaves generated fields unchanged and emits a warning.
local function test_missing_pronunciation()
    local config = make_forvo_test_config { source_format = "ogg", audio_format = "opus", codec = "libopus" }
    local downloader, state = make_forvo_test_context(config, { { status = 0, stdout = "No pronunciation" } })
    local fields = { SentenceAudio = "[sound:sentence.ogg]" }
    downloader.append(fields, { Word = "word", VocabAudio = "" })
    h.assert_equals(fields, { SentenceAudio = "[sound:sentence.ogg]" })
    h.assert_equals(#state.requests, 1)
    h.assert_equals(state.encodings, {})
    h.assert_equals(state.removed, {})
    h.assert_equals(state.warnings, { "Seems like Forvo doesn't have audio for word word." })
end

--- Disabled pronunciation lookup performs no external work.
local function test_disabled_forvo()
    local config = make_forvo_test_config { source_format = "ogg", audio_format = "opus", codec = "libopus" }
    config.use_forvo = "no"
    local downloader, state = make_forvo_test_context(config, {})
    local fields = {}
    downloader.append(fields, { Word = "word", VocabAudio = "" })
    h.assert_equals(fields, {})
    h.assert_equals(state.requests, {})
    h.assert_equals(state.encodings, {})
    h.assert_equals(state.removed, {})
    h.assert_equals(state.warnings, {})
end

--- Return failed requests, missing source parameters, and empty decoded filenames.
local function make_invalid_page_test_cases()
    return {
        {},
        { response = false },
        { response = {} },
        { response = { status = 22, stdout = make_forvo_test_page() } },
        { response = { status = 0 } },
        { response = { status = 0, stdout = false } },
        { response = { status = 0, stdout = {} } },
        { response = { status = 0, stdout = "" } },
        { response = { status = 0, stdout = "Play();" } },
        { response = { status = 0, stdout = "Play('');" } },
        { response = { status = 0, stdout = "Play('Y2xpcC5tcDM=');" } },
        { response = { status = 0, stdout = "Play('','%%%');" } },
        { response = { status = 0, stdout = "Play('','a');" } },
    }
end

--- Invalid page data must not start downloads, encoding, or field changes.
local function test_invalid_pronunciation_pages()
    local config = make_forvo_test_config { source_format = "ogg", audio_format = "opus", codec = "libopus" }
    for _, case in ipairs(make_invalid_page_test_cases()) do
        local downloader, state = make_forvo_test_context(config, { case.response })
        local fields = { SentenceAudio = "[sound:sentence.ogg]" }
        downloader.append(fields, { Word = "word", VocabAudio = "" })
        h.assert_equals(fields, { SentenceAudio = "[sound:sentence.ogg]" })
        h.assert_equals(#state.requests, 1)
        h.assert_equals(state.encodings, {})
        h.assert_equals(state.removed, {})
        h.assert_equals(#state.warnings, 1)
    end
end

--- Failed or missing download responses leave fields unchanged and clean up temporary files.
local function test_failed_pronunciation_downloads()
    local config = make_forvo_test_config { source_format = "ogg", audio_format = "opus", codec = "libopus" }
    for _, case in ipairs { {}, { response = false }, { response = {} }, { response = { status = 22 } } } do
        local downloader, state = make_forvo_test_context(config, {
            { status = 0, stdout = make_forvo_test_page() },
            case.response,
        })
        local fields = {}
        downloader.append(fields, { Word = "word", VocabAudio = "" })
        h.assert_equals(fields, {})
        h.assert_equals(#state.requests, 2)
        h.assert_equals(state.encodings, {})
        h.assert_equals(state.removed, { "/forvo-test-tmp/forvo_word.ogg" })
        h.assert_equals(state.warnings, { "Couldn't download audio for word word from Forvo." })
    end
end

--- Missing or failed encoder responses do not append broken pronunciation references.
local function test_failed_pronunciation_encoding()
    local config = make_forvo_test_config { source_format = "ogg", audio_format = "opus", codec = "libopus" }
    for _, case in ipairs { {}, { response = false }, { response = {} }, { response = { status = 1 } } } do
        local downloader, state = make_forvo_test_context(config, {
            { status = 0, stdout = make_forvo_test_page() },
            { status = 0 },
        })
        state.encoding_response = function() return case.response end
        local fields = {}
        downloader.append(fields, { Word = "word", VocabAudio = "" })
        h.assert_equals(fields, {})
        h.assert_equals(#state.encodings, 1)
        h.assert_equals(state.removed, { "/forvo-test-tmp/forvo_word.ogg" })
        h.assert_equals(#state.warnings, 1)
    end
end

--- Valid Base64 filenames remain usable when Forvo omits trailing padding.
local function test_unpadded_pronunciation_sources()
    for _, case in ipairs {
        { source_format = "mp3", audio_format = "mp3", codec = "libmp3lame" },
        { source_format = "ogg", audio_format = "opus", codec = "libopus" },
    } do
        local page = make_forvo_test_page():gsub("=", "")
        local downloader, state = make_forvo_test_context(make_forvo_test_config(case), {
            { status = 0, stdout = page },
            { status = 0 },
        })
        local fields = {}
        downloader.append(fields, { Word = "word", VocabAudio = "" })
        h.assert_equals(fields.VocabAudio, "[sound:forvo_word." .. case.source_format .. "]")
        h.assert_equals(state.warnings, {})
    end
end

--- Construct a new downloader with captured settings and the original fake I/O dependencies.
local function make_forvo_constructor_test_context(case)
    local original_config = make_forvo_test_config { source_format = "mp3", audio_format = "mp3", codec = "libmp3lame" }
    local original, state = make_forvo_test_context(original_config, {
        { status = 0, stdout = make_forvo_test_page() },
        { status = 0 },
        { status = 0, stdout = make_forvo_test_page() },
        { status = 0 },
        { status = 0, stdout = "No pronunciation" },
    })
    h.assert_equals(original.init(fixtures.make_config_manager(original_config)), original)
    local config = make_forvo_test_config(case)
    local fresh = original.new(snapshot.new(fixtures.make_config_manager(config)))
    h.assert_equals(fresh == original, false)
    config.use_forvo, config.audio_extension, config.audio_codec = "no", ".changed", "changed"
    original.set_output_dir("/later-media")
    fresh.set_output_dir("/request-media")
    return original, fresh, state
end

--- Verify later parent operations do not use the child's settings or output directory.
local function assert_forvo_parent_constructor_test_flow(original, fresh, state)
    local fields = {}
    original.append(fields, { Word = "word", VocabAudio = "" })
    h.assert_equals(fields.VocabAudio, "[sound:forvo_word.mp3]")
    h.assert_equals(state.requests[4][1], "https://audio00.forvo.com/mp3/clip.mp3")
    local command = state.encodings[2]
    h.assert_equals(command[#command], "-o=/later-media/forvo_word.mp3")
    h.assert_equals(#state.removed, 2)
    fresh.append({}, { Word = "missing", VocabAudio = "" })
    h.assert_equals(state.warnings, { "Seems like Forvo doesn't have audio for word missing." })
end

--- Verify reconstruction preserves all fake I/O and isolates configuration and directories.
local function test_forvo_instance_constructors()
    for _, case in ipairs(make_pronunciation_format_test_cases()) do
        local original, fresh, state = make_forvo_constructor_test_context(case)
        local filename = "forvo_word" .. (case.output_extension or "." .. case.source_format)
        local fields = { SentenceAudio = "[sound:sentence.ogg]" }
        fresh.append(fields, { Word = "word", VocabAudio = "" })
        h.assert_equals(fields.VocabAudio, "[sound:" .. filename .. "]")
        assert_forvo_test_requests(state, case, filename)
        assert_forvo_test_encoding(state, case, filename, "/request-media")
        assert_forvo_parent_constructor_test_flow(original, fresh, state)
    end
end

--- Reject an unready provider while retaining the original downloader's settings.
local function test_forvo_constructor_requires_ready_manager()
    local config = make_forvo_test_config { source_format = "ogg", audio_format = "opus", codec = "libopus" }
    local original, state = make_forvo_test_context(config, { { status = 0, stdout = "No pronunciation" } })
    local cfg_mgr = fixtures.make_config_manager({})
    cfg_mgr.fail_if_not_ready = h.as_callback(error, "config not loaded")
    local success, error = pcall(original.new, cfg_mgr)
    h.assert_equals(success, false)
    h.assert_equals(h.is_substr(error, "config not loaded"), true)
    original.append({}, { Word = "word", VocabAudio = "" })
    h.assert_equals(#state.requests, 1)
end

--- Run the isolated downloader's behavior, constructor, and response-validation tests.
local function run_tests()
    test_existing_pronunciation_flow()
    test_missing_pronunciation()
    test_disabled_forvo()
    test_invalid_pronunciation_pages()
    test_failed_pronunciation_downloads()
    test_failed_pronunciation_encoding()
    test_unpadded_pronunciation_sources()
    test_forvo_instance_constructors()
    test_forvo_constructor_requires_ready_manager()
end

return { run_tests = run_tests }
