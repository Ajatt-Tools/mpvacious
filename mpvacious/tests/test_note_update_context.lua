--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Note update context tests.
]]

local h = require("helpers")
local fixtures = require("tests.fixtures")
local note_update_context = require("anki.note_update_context")
local snapshot = require("config.snapshot")
local subtitle_module = require("subtitles.subtitle")

--- Create an update configuration with the selected merge order.
local function make_update_test_config(append_media)
    return fixtures.make_update_config {
        secondary_field = "SentEng",
        miscinfo_field = "Notes",
        append_media = append_media,
    }
end

--- Test nested sentence fields retain the more complete normalized value.
local function test_join_field_content()
    h.assert_equals(
        note_update_context.join_field_content(
            "ヤツらの声に現実味が…",
            "あの遠さはヤツらの声に現実味が…"
        ),
        "あの遠さはヤツらの声に現実味が…"
    )
    h.assert_equals(
        note_update_context.join_field_content(
            "あの遠さはヤツらの声に現実味が…",
            "ヤツらの声に現実味が…"
        ),
        "あの遠さはヤツらの声に現実味が…"
    )
    h.assert_equals(note_update_context.join_field_content("new", "old"), "old<br>new")
end

--- Create a context with concrete test components for field-merge tests.
local function make_field_merge_test_context()
    return note_update_context.new {
        ankiconnect = {},
        quick_creation_opts = {},
        subs_observer = {},
        encoder = {},
        forvo = fixtures.make_forvo(),
        cfg_mgr = fixtures.make_config_manager(make_update_test_config(true)),
        notify = h.noop,
    }
end

--- Test targeted-sentence markup is preserved while merging fields.
local function test_make_new_note_data(test_context)
    local old_note = {
        SentKanji = "ヤツらの声に<b>現実味</b>が…",
    }
    local new_note = {
        SentKanji = "あの遠さはヤツらの声に現実味が…",
    }
    local expected = {
        SentKanji = "あの遠さはヤツらの声に<b>現実味</b>が…",
    }
    local new_data = test_context.make_new_note_data(old_note, new_note, { overwrite = false, disable_forvo = true })
    h.assert_equals(new_data.SentKanji, expected.SentKanji)
end

--- Return literal highlighted targets and sentences that must not match as patterns.
local function make_literal_target_test_cases()
    return {
        { target = "a.b", sentence = "axb", expected = "axb" },
        { target = "a.b", sentence = "before a.b after", expected = "before <b>a.b</b> after" },
        { target = "(word)", sentence = "before (word) after", expected = "before <b>(word)</b> after" },
        { target = "50%", sentence = "50% complete", expected = "<b>50%</b> complete" },
        { target = "[word]", sentence = "[word] here", expected = "<b>[word]</b> here" },
        { target = "a+b?", sentence = "a+b? here", expected = "<b>a+b?</b> here" },
        { target = "word", sentence = "word and word", expected = "<b>word</b> and word" },
        { target = "absent", sentence = "unchanged", expected = "unchanged" },
    }
end

--- Preserve literal target markup without replacing unrelated sentence characters.
local function test_literal_target_highlighting(test_context)
    for _, case in ipairs(make_literal_target_test_cases()) do
        local fields = test_context.make_new_note_data(
            { SentKanji = "<b>" .. case.target .. "</b>" },
            { SentKanji = case.sentence },
            { overwrite = true, disable_forvo = true }
        )
        h.assert_equals(fields.SentKanji, case.expected)
    end
end

--- Test equivalent apostrophe entities do not duplicate a sentence field.
local function test_html_escaping(test_context)
    -- HTML escaping
    local old_note = {
        SentKanji = "Well, that's the knighthood in the bag.",
    }
    local new_note = {
        SentKanji = "Well, that&apos;s the knighthood in the bag.",
    }
    h.assert_equals(test_context.join_fields(new_note, old_note).SentKanji, old_note.SentKanji)
    new_note = {
        SentKanji = "Well, that&#39;s the knighthood in the bag.",
    }
    h.assert_equals(test_context.join_fields(new_note, old_note).SentKanji, old_note.SentKanji)
end

--- Create fresh generated fields for a field-merge test.
local function make_join_fields_test_new_note()
    return {
        SentKanji = "それは…分からんよ",
        SentAudio = "[sound:s01e13_02m25s010ms_02m27s640ms.ogg]",
        SentEng = "Well...",
        Image = '<img alt="snapshot" src="s01e13_02m25s561ms.avif">',
    }
end

--- Create fresh stored fields for a field-merge test.
local function make_join_fields_test_old_note()
    return {
        SentAudio = "[sound:s01e13_02m21s340ms_02m24s140ms.ogg]",
        Image = '<img alt="snapshot" src="s01e13_02m22s225ms.avif">',
        VocabAudio = "",
        Notes = "",
        VocabDef = "",
        SentKanji = "勝ちって何に？",
        SentEng = "What would we win, exactly?",
    }
end

--- Create the expected output for a field-merge test.
local function make_join_fields_test_expected()
    return {
        SentKanji = "勝ちって何に？<br>それは…分からんよ",
        SentAudio = "[sound:s01e13_02m21s340ms_02m24s140ms.ogg]<br>[sound:s01e13_02m25s010ms_02m27s640ms.ogg]",
        SentEng = "What would we win, exactly?<br>Well...",
        Image = '<img alt="snapshot" src="s01e13_02m22s225ms.avif"><br><img alt="snapshot" src="s01e13_02m25s561ms.avif">',
        Notes = "",
    }
end

--- Create fresh field-merge input and expected-output fixtures.
local function make_join_fields_test_case()
    return {
        new_note = make_join_fields_test_new_note(),
        old_note = make_join_fields_test_old_note(),
        expected = make_join_fields_test_expected(),
    }
end

--- Create a scenario for equivalent quote variants.
local function make_quote_variant_duplicate_test_scenario()
    local text = "女の子の <b>女性</b>の　『お』から始まる…"
    return { old = text, new = "女の子の <b>女性</b>の “お”から始まる…", expected = text }
end

--- Create a scenario for equivalent nonbreaking spaces and quotes.
local function make_nonbreaking_space_duplicate_test_scenario()
    local text = "女の子の <b>女性</b>の　『お』から始まる…"
    return {
        old = text,
        new = "女の子の <b>女性</b>の\194\160〝お〟から始まる…\226\128\139",
        expected = text,
    }
end

--- Create a scenario for equivalent byte-order marks and quotes.
local function make_byte_order_mark_duplicate_test_scenario()
    local text = "女の子の <b>女性</b>の　『お』から始まる…"
    return {
        old = text,
        new = "\239\187\191女の子の <b>女性</b>の\226\128\175＂お＂から始まる…",
        expected = text,
    }
end

--- Create a scenario for distinct punctuation.
local function make_distinct_punctuation_test_scenario()
    return {
        old = "それは…分からんよ",
        new = "それは！分からんよ",
        expected = "それは…分からんよ<br>それは！分からんよ",
    }
end

--- Create a scenario for distinct surrounding quote text.
local function make_distinct_quote_text_test_scenario()
    return {
        old = "『お』から始まる",
        new = "“お”から終わる",
        expected = "『お』から始まる<br>“お”から終わる",
    }
end

--- Create fresh scenarios for duplicate field-content handling.
local function make_join_fields_duplicate_test_scenarios()
    return {
        make_quote_variant_duplicate_test_scenario(),
        make_nonbreaking_space_duplicate_test_scenario(),
        make_byte_order_mark_duplicate_test_scenario(),
        make_distinct_punctuation_test_scenario(),
        make_distinct_quote_text_test_scenario(),
    }
end

--- Test joining sentence, media, and translation fields.
local function test_join_fields(test_context)
    local test_case = make_join_fields_test_case()
    h.assert_equals(test_context.join_fields(test_case.new_note, test_case.old_note), test_case.expected)
end

--- Test equivalent HTML entities and subtitle punctuation do not duplicate fields.
local function test_join_fields_duplicates(test_context)
    for _, scenario in ipairs(make_join_fields_duplicate_test_scenarios()) do
        local actual = test_context.join_fields({ SentKanji = scenario.new }, { SentKanji = scenario.old })
        h.assert_equals(actual.SentKanji, scenario.expected)
    end
end

--- Return note-specific stored fields for update-context tests.
local function make_context_test_stored_fields(note_id)
    return { SentKanji = "stored " .. tostring(note_id) }
end

--- Return fresh state shared by update-context test doubles.
local function make_update_test_result()
    return { current_collections = 0, clear_count = 0, appended_note_ids = {} }
end

--- Complete both media jobs with their created filenames.
local function complete_update_test_media_jobs(jobs)
    jobs[1].callback("snapshot.avif", nil)
    jobs[2].callback("audio.ogg", nil)
end

--- Create a context and subtitle fixture from named update-test options.
local function make_update_test_context(options)
    local result = options.result
    local subtitle = options.subtitle or subtitle_module.make_subtitle("new sentence", 0, 1)
    result.fields_by_note = {}
    result.field_requests = {}
    result.preview_reads = {}
    return note_update_context.new {
        ankiconnect = fixtures.make_update_ankiconnect(result, make_context_test_stored_fields),
        quick_creation_opts = options.quick_options or fixtures.make_quick_creation_options(result, {
            lines = options.lines,
        }),
        subs_observer = options.observer or fixtures.make_subtitle_observer(result, subtitle, {
            user_altered = options.user_altered,
        }),
        encoder = options.encoder or fixtures.make_update_encoder(options.jobs),
        forvo = fixtures.make_forvo(),
        cfg_mgr = fixtures.make_config_manager(options.config or make_update_test_config(true)),
        notify = options.notify or fixtures.make_notifier(result),
        mp = options.mp,
    },
        subtitle
end

--- Test both configured media merge orders.
local function test_update_media_merge()
    for _, scenario in ipairs {
        { append_media = true, expected = "stored 13<br>new sentence" },
        { append_media = false, expected = "new sentence<br>stored 13" },
    } do
        local result = make_update_test_result()
        local jobs = {}
        local context, subtitle = make_update_test_context {
            result = result,
            jobs = jobs,
            config = make_update_test_config(scenario.append_media),
        }
        context.perform_update({ note_ids = { 13 }, overwrite = false, subtitle = subtitle })
        complete_update_test_media_jobs(jobs)
        h.assert_equals(result.fields_by_note[13].SentKanji, scenario.expected)
    end
end

--- Test collection from current and configured multi-line subtitles.
local function test_collect_subtitle()
    local current_result = make_update_test_result()
    local current_context, current_subtitle = make_update_test_context { result = current_result, jobs = {} }
    h.assert_equals(current_context.collect_subtitle(), current_subtitle)
    h.assert_equals(current_result.current_collections, 1)

    local multi_result = make_update_test_result()
    local multi_context, multi_subtitle = make_update_test_context { result = multi_result, jobs = {}, lines = 3 }
    h.assert_equals(multi_context.collect_subtitle(), multi_subtitle)
    h.assert_equals(multi_result.collected_lines, 3)
end

--- Check lookup results without collecting subtitles, reading fields, or starting an update.
local function assert_target_lookup_test_case(case, method)
    local result, jobs = make_update_test_result(), {}
    result.last_note_ids, result.selected_note_ids = case.recent_ids, case.selected_ids
    local config = make_update_test_config(true)
    config.card_overwrite_safeguard = 3
    local context = make_update_test_context {
        result = result,
        jobs = jobs,
        config = config,
        quick_options = fixtures.make_quick_creation_options(result, { cards = case.cards }),
    }
    local ids, warning, duration = context[method]()
    h.assert_equals(ids, case.expected_ids)
    h.assert_equals(warning, case.warning)
    h.assert_equals(duration, nil)
    h.assert_equals(result.requested_cards, case.cards)
    h.assert_equals(result.current_collections, 0)
    h.assert_equals(result.field_requests, {})
    h.assert_equals(result.clear_count, 0)
    h.assert_equals(result.notification, nil)
    h.assert_equals(jobs, {})
end

--- Validate missing and expired recent notes while preserving count and ordering.
local function test_find_recent_note_ids()
    local recent, older = h.minutes_ago(1), h.minutes_ago(11)
    for _, case in ipairs {
        { cards = 1, warning = "Couldn't find the target note." },
        { recent_ids = {}, cards = 2, warning = "Couldn't find the target note." },
        { recent_ids = { older }, cards = 1, warning = "Couldn't find the target note." },
        { recent_ids = { older, recent }, cards = 2, warning = "Couldn't find the target note." },
        { recent_ids = { recent }, cards = 1, expected_ids = { recent } },
        { recent_ids = { recent - 1, recent }, cards = 2, expected_ids = { recent - 1, recent } },
    } do
        assert_target_lookup_test_case(case, "find_recent_note_ids")
    end
end

--- Validate Browser selections against the captured safeguard without notifying.
local function test_find_selected_note_ids()
    local missing = "Couldn't find the target note(s). Did you select the notes you want in Anki?"
    for _, case in ipairs {
        { warning = missing },
        { selected_ids = {}, warning = missing },
        { selected_ids = { 13 }, expected_ids = { 13 } },
        { selected_ids = { 11, 12, 13 }, expected_ids = { 11, 12, 13 } },
        {
            selected_ids = { 11, 12, 13, 14 },
            warning = "More than 3 notes selected\nnot recommended, but you can change the limit in your config",
        },
    } do
        assert_target_lookup_test_case(case, "find_selected_note_ids")
    end
end

--- Keep the selected-note limit from the snapshot when the live profile changes.
local function test_selected_lookup_retains_snapshot_safeguard()
    local result = make_update_test_result()
    result.selected_note_ids = { 11, 12 }
    local config = make_update_test_config(true)
    config.card_overwrite_safeguard = 3
    local context = make_update_test_context { result = result, jobs = {}, config = config }
    local captured = context.new(snapshot.new(fixtures.make_config_manager(config)))
    config.card_overwrite_safeguard = 1
    local ids, warning = captured.find_selected_note_ids()
    h.assert_equals(ids, { 11, 12 })
    h.assert_equals(warning, nil)
    h.assert_equals(result.clear_count, 0)
end

--- Test media completion writes each note and notifies the user.
local function test_update_completion()
    local result = make_update_test_result()
    local jobs = {}
    local context, subtitle = make_update_test_context { result = result, jobs = jobs }
    context.perform_update({ note_ids = { 11, 12 }, overwrite = true, subtitle = subtitle })
    h.assert_equals(#jobs, 2)
    jobs[1].callback("snapshot.avif", nil)
    h.assert_equals(result.appended_note_ids, {})
    jobs[2].callback("audio.ogg", nil)
    h.assert_equals(result.appended_note_ids, { 11, 12 })
    h.assert_equals(result.browse_query, "nid:11 OR nid:12")
    h.assert_equals(result.notification, "Updated 2 notes.")
    h.assert_equals(result.clear_count, 1)
end

--- Keep captured IDs, field pairs, and completion counts after caller changes during media creation.
local function test_update_retains_captured_targets()
    local result, jobs = make_update_test_result(), {}
    result.write_callbacks = {}
    local context, sub = make_update_test_context { result = result, jobs = jobs }
    local ids = { 23, 11 }
    context.perform_update { note_ids = ids, overwrite = true, subtitle = sub }
    h.assert_equals(result.field_requests, { { 23, 11 } })
    ids[1] = 99
    table.insert(ids, 42)
    result.read_fields = h.as_callback(error, "captured targets must not be read again")
    complete_update_test_media_jobs(jobs)
    h.assert_equals(result.appended_note_ids, { 23, 11 })
    result.write_callbacks[11](nil, nil)
    h.assert_equals(result.notification, nil)
    result.write_callbacks[23](nil, nil)
    h.assert_equals(result.browse_query, "nid:23 OR nid:11")
    h.assert_equals(result.notification, "Updated 2 notes.")
end

--- Verify a failed media job never writes fields after target reading.
local function test_update_media_failures()
    for _, case in ipairs {
        { snapshot_error = "image conversion failed", expected = "snapshot: image conversion failed" },
        { audio_error = "sound conversion failed", expected = "audio: sound conversion failed" },
        {
            snapshot_error = "image conversion failed",
            audio_error = "sound conversion failed",
            expected = "snapshot: image conversion failed; audio: sound conversion failed",
        },
    } do
        local result = make_update_test_result()
        local jobs = {}
        local context, subtitle = make_update_test_context { result = result, jobs = jobs }
        context.perform_update({ note_ids = { 11 }, overwrite = true, subtitle = subtitle })
        jobs[1].callback(case.snapshot_error and nil or "snapshot.avif", case.snapshot_error)
        h.assert_equals(result.notification, nil)
        jobs[2].callback(case.audio_error and nil or "audio.ogg", case.audio_error)
        h.assert_equals(result.field_requests, { { 11 } })
        h.assert_equals(result.appended_note_ids, {})
        h.assert_equals(result.browse_query, nil)
        h.assert_equals(result.notification, "Failed to create media: " .. case.expected)
        h.assert_equals(result.notification_level, "error")
    end
end

--- A missing Anki media directory must not start jobs or discard the selection.
local function test_update_without_media_directory()
    local result = make_update_test_result()
    result.media_dir_error = "AnkiConnect unavailable"
    local jobs = {}
    local context, subtitle = make_update_test_context { result = result, jobs = jobs }
    context.perform_update({ note_ids = { 11 }, overwrite = true, subtitle = subtitle })
    h.assert_equals(#jobs, 0)
    h.assert_equals(result.field_requests, { { 11 } })
    h.assert_equals(result.appended_note_ids, {})
    h.assert_equals(result.clear_count, 0)
    h.assert_equals(result.notification_level, "error")
    h.assert_equals(result.notification, "AnkiConnect unavailable")
end

--- A skipped media job has no filename and must not block the other job.
local function test_update_skipped_media_job()
    local result = make_update_test_result()
    local jobs = {}
    local context, subtitle = make_update_test_context { result = result, jobs = jobs }
    context.perform_update({ note_ids = { 11 }, overwrite = true, subtitle = subtitle })
    jobs[1].callback(nil, nil)
    jobs[2].callback("audio.ogg", nil)
    h.assert_equals(result.appended_note_ids, { 11 })
    h.assert_equals(result.notification, "Updated note: stored 11.")
end

--- Verify delayed Anki write failures cannot trigger a success notification.
local function test_update_write_outcomes()
    local cases = {
        {
            errors = {},
            results = { [11] = "updated", [12] = "updated" },
            notification = "Updated 2 notes.",
            browse_query = "nid:11 OR nid:12",
        },
        { errors = { [12] = "denied" }, notification = "Failed to update notes: note 12: denied" },
        {
            errors = { [12] = "denied", [11] = "busy" },
            notification = "Failed to update notes: note 12: denied; note 11: busy",
        },
    }
    for _, case in ipairs(cases) do
        local result = make_update_test_result()
        result.write_callbacks = {}
        local jobs = {}
        local context, subtitle = make_update_test_context { result = result, jobs = jobs }
        context.perform_update({ note_ids = { 11, 12 }, overwrite = true, subtitle = subtitle })
        complete_update_test_media_jobs(jobs)
        h.assert_equals(result.notification, nil)
        result.write_callbacks[12](case.results and case.results[12], case.errors[12])
        h.assert_equals(result.notification, nil)
        result.write_callbacks[11](case.results and case.results[11], case.errors[11])
        h.assert_equals(result.notification, case.notification)
        h.assert_equals(result.browse_query, case.browse_query)
    end
end

--- Test one updated note opens the matching browser query and notification.
local function test_single_note_update_completion()
    local result = make_update_test_result()
    local jobs = {}
    local context, subtitle = make_update_test_context { result = result, jobs = jobs }
    context.perform_update({ note_ids = { 11 }, overwrite = true, subtitle = subtitle })
    complete_update_test_media_jobs(jobs)
    h.assert_equals(result.browse_query, "nid:11")
    h.assert_equals(result.notification, "Updated note: stored 11.")
end

--- Assert one failed bulk field request prevents every write in the batch.
local function assert_update_test_field_failure(case)
    local result = make_update_test_result()
    local jobs = {}
    local context, subtitle = make_update_test_context { result = result, jobs = jobs }
    --- Fail the bulk read before any note in the scenario has been written.
    result.read_fields = function(note_ids)
        h.assert_equals(result.appended_note_ids, {})
        h.assert_equals(note_ids, { 11, 12 })
        return nil, "read failed"
    end
    context.perform_update({ note_ids = { 11, 12 }, overwrite = case.overwrite, subtitle = subtitle })
    h.assert_equals(jobs, {})
    h.assert_equals(result.media_dir_requests, nil)
    h.assert_equals(result.clear_count, 0)
    h.assert_equals(result.appended_note_ids, {})
    h.assert_equals(result.fields_by_note, {})
    h.assert_equals(result.field_requests, { { 11, 12 } })
    h.assert_equals(result.browse_query, nil)
    h.assert_equals(result.notification_level, "error")
    h.assert_equals(result.notification, "read failed")
end

--- Test one failed bulk read prevents both append and overwrite operations.
local function test_update_field_read_failures()
    for _, case in ipairs {
        { overwrite = false },
        { overwrite = true },
    } do
        assert_update_test_field_failure(case)
    end
end

--- Test all fields are fetched once before writing, and stay paired with their own note IDs.
local function test_update_preflight_field_reads()
    local result = make_update_test_result()
    local jobs = {}
    local context, subtitle = make_update_test_context { result = result, jobs = jobs }
    --- Supply each target's original fields before any writes begin.
    result.read_fields = function(note_ids)
        h.assert_equals(result.appended_note_ids, {})
        h.assert_equals(note_ids, { 11, 12 })
        return {
            [11] = { SentKanji = "stored 11" },
            [12] = { SentKanji = "stored 12" },
        },
            nil
    end
    context.perform_update({ note_ids = { 11, 12 }, overwrite = false, subtitle = subtitle })
    h.assert_equals(result.field_requests, { { 11, 12 } })
    result.read_fields = h.as_callback(error, "captured target fields must not be read again")
    complete_update_test_media_jobs(jobs)
    h.assert_equals(result.field_requests, { { 11, 12 } })
    h.assert_equals(result.fields_by_note[11].SentKanji, "stored 11<br>new sentence")
    h.assert_equals(result.fields_by_note[12].SentKanji, "stored 12<br>new sentence")
    h.assert_equals(result.notification, "Updated 2 notes.")
end

--- Test a failed notification-only preview read falls back to the updated note ID.
local function test_update_notification_field_read_failure()
    local result = make_update_test_result()
    local jobs = {}
    local context, subtitle = make_update_test_context { result = result, jobs = jobs }
    --- Fail only the notification preview after a successful update.
    result.read_preview = function()
        return nil, "preview unavailable"
    end
    context.perform_update({ note_ids = { 11 }, overwrite = true, subtitle = subtitle })
    complete_update_test_media_jobs(jobs)
    h.assert_equals(result.appended_note_ids, { 11 })
    h.assert_equals(result.field_requests, { { 11 } })
    h.assert_equals(result.preview_reads, { 11 })
    h.assert_equals(result.notification, "Updated note #11.")
end

--- A missing note type in the notification preview does not hide a successful write.
local function test_update_notification_model_lookup_failure()
    local result = make_update_test_result()
    result.first_field_error = "Note type missing"
    local jobs = {}
    local context, subtitle = make_update_test_context { result = result, jobs = jobs }
    context.perform_update({ note_ids = { 11 }, overwrite = true, subtitle = subtitle })
    complete_update_test_media_jobs(jobs)
    h.assert_equals(result.appended_note_ids, { 11 })
    h.assert_equals(result.preview_reads, {})
    h.assert_equals(result.notification, "Updated note #11.")
end

--- Construct real blank subtitles retaining secondary text and timings.
local function make_blank_update_test_subtitle(case)
    local values = { text = case.text, secondary = "translation", ["start"] = 1, ["end"] = 3, is_secondary = true }
    return subtitle_module.Subtitle:new(values)
end

--- Verify blank updates preserve stored text or fail before touching interactive state.
local function assert_blank_update_test_outcome(result, jobs, case)
    if case.preflight_error then
        h.assert_equals(jobs, {})
        h.assert_equals(result.appended_note_ids, {})
        h.assert_equals(result.clear_count, 0)
        h.assert_equals(result.notification, case.preflight_error)
    else
        complete_update_test_media_jobs(jobs)
        h.assert_equals(result.fields_by_note[13].SentKanji, "stored 13")
        h.assert_equals(result.fields_by_note[13].SentEng, "translation")
        h.assert_equals(result.clear_count, 1)
    end
end

--- Check caller data directly because subtitle defaults can conceal a removed text key.
local function assert_blank_update_test_request(request, sub, original)
    h.assert_equals(rawequal(request.subtitle, sub), true)
    h.assert_equals(rawget(sub, "text"), rawget(original.subtitle, "text"))
    h.assert_equals(sub.secondary, "translation")
    h.assert_equals(sub["start"], 1)
    h.assert_equals(sub["end"], 3)
    h.assert_equals(sub.is_secondary, true)
    h.assert_equals(request, original)
end

--- Exercise preparation and completion without modifying the caller's blank subtitle.
local function assert_blank_update_test_case(case)
    local result, jobs = make_update_test_result(), {}
    result.media_dir_error = case.preflight_error
    local sub = make_blank_update_test_subtitle(case)
    local context = make_update_test_context { result = result, jobs = jobs, subtitle = sub }
    local request = { note_ids = { 13 }, overwrite = case.overwrite, subtitle = sub }
    local original = h.deep_copy(request)
    context.perform_update(request)
    assert_blank_update_test_request(request, sub, original)
    assert_blank_update_test_outcome(result, jobs, case)
    assert_blank_update_test_request(request, sub, original)
end

--- Preserve caller data for empty and absent text with successful or failed preparation.
local function test_blank_update_subtitle()
    for _, case in ipairs {
        { text = "", overwrite = false },
        { text = "", overwrite = true },
        { overwrite = true },
        { overwrite = false },
        { text = "", overwrite = true, preflight_error = "AnkiConnect unavailable" },
        { text = "", overwrite = false, preflight_error = "AnkiConnect unavailable" },
        { overwrite = false, preflight_error = "AnkiConnect unavailable" },
        { overwrite = true, preflight_error = "AnkiConnect unavailable" },
    } do
        assert_blank_update_test_case(case)
    end
end

--- Create the mp API for metadata and duration tests.
local function make_update_test_mp_api(filename)
    filename = filename or "episode.mkv"
    return {
        --- Return the test media filename.
        get_property = function(name)
            if name == "filename" then
                return filename
            elseif name == "path" then
                return "/videos/" .. filename
            end
        end,
        --- Return the test media duration.
        get_property_number = function(name)
            if name == "duration" then
                return 1
            elseif name == "time-pos" then
                return 65
            end
        end,
    }
end

--- Assert tag substitution and audio padding for automatic and altered timings.
local function assert_update_test_media_metadata(mp_api)
    local config = make_update_test_config(true)
    config.audio_padding = 0.5
    local result = make_update_test_result()
    local context = make_update_test_context { result = result, jobs = {}, config = config, mp = mp_api }
    local altered_context = make_update_test_context {
        result = result,
        jobs = {},
        config = config,
        user_altered = true,
        mp = mp_api,
    }
    h.assert_equals(context.substitute_fmt("source_%n"), "source_episode")
    h.assert_equals(context.substitute_fmt("%f %t"), "/videos/episode.mkv 01m05s000ms")
    h.assert_equals(context.audio_padding(), 0.5)
    h.assert_equals(altered_context.audio_padding(), 0.0)
end

--- Test tag substitution and audio padding for automatic and altered timings.
local function test_media_metadata()
    assert_update_test_media_metadata(make_update_test_mp_api())
end

--- Verify the padding selected by the context is passed to the fake audio-job constructor.
local function assert_audio_padding_job_test_case(case)
    local result, jobs = make_update_test_result(), {}
    local config = make_update_test_config(true)
    config.audio_padding = case.padding
    local context, sub = make_update_test_context {
        result = result,
        jobs = jobs,
        config = config,
        user_altered = case.user_altered,
        mp = fixtures.make_mp_property_reader { duration = case.duration },
    }
    context.perform_update { note_ids = { 13 }, overwrite = true, subtitle = sub }
    h.assert_equals(#jobs, 2)
    h.assert_equals(jobs[1].argument, nil)
    h.assert_equals(jobs[2].argument, case.expected)
end

--- Pass automatic padding or zero for manual timings, disabled padding, and absent duration.
local function test_audio_job_receives_selected_padding()
    for _, case in ipairs {
        { padding = 0.5, duration = 200, expected = 0.5 },
        { padding = 0.5, duration = 200, user_altered = true, expected = 0 },
        { padding = 0, duration = 200, expected = 0 },
        { padding = 0.5, expected = 0 },
    } do
        assert_audio_padding_job_test_case(case)
    end
end

--- Preserve literal percent signs in filenames and paths, including repeated placeholders.
local function test_literal_tag_substitutions()
    for _, case in ipairs {
        { filename = "100% fun.mkv", name = "100%_fun" },
        { filename = "part%1.mkv", name = "part%1" },
        { filename = "part%%.mkv", name = "part%%" },
    } do
        local context = make_update_test_context {
            result = make_update_test_result(),
            jobs = {},
            mp = make_update_test_mp_api(case.filename),
        }
        h.assert_equals(
            context.substitute_fmt("%n|%f|%n"),
            case.name .. "|/videos/" .. case.filename .. "|" .. case.name
        )
    end
end

--- Preserve the environment value literally during its placeholder substitution.
local function test_environment_tag_substitution()
    local context = make_update_test_context {
        result = make_update_test_result(),
        jobs = {},
        mp = make_update_test_mp_api(),
    }
    local env_tags = os.getenv("SUBS2SRS_TAGS") or ""
    -- Full-path substitution still follows environment substitution, as in production.
    local expected = h.str_replace(env_tags, "%f", "/videos/episode.mkv")
    h.assert_equals(context.substitute_fmt("%e"), h.remove_leading_trailing_spaces(expected))
end

--- Assert every target receives the invocation tag rather than later playback metadata.
local function assert_update_invocation_tag_test_results(result, case)
    local expected = case.name .. "|/videos/" .. case.filename .. "|01m05s000ms|" .. case.name
    for _, note_id in ipairs(case.note_ids) do
        h.assert_equals(result.tags_by_note[note_id], expected)
    end
    h.assert_equals(result.clear_count, 1)
end

--- Advance playback between media completions while retaining the original update tag.
local function assert_update_invocation_tag_test_case(case)
    local result, jobs = make_update_test_result(), {}
    local properties = { filename = case.filename, path = "/videos/" .. case.filename, ["time-pos"] = 65 }
    local config = make_update_test_config(true)
    config.note_tag = "%n|%f|%t|%n"
    local context, subtitle = make_update_test_context {
        result = result,
        jobs = jobs,
        config = config,
        mp = fixtures.make_mp_property_reader(properties),
    }
    local request = { note_ids = case.note_ids, overwrite = case.overwrite, subtitle = subtitle }
    local original_request = h.deep_copy(request)
    context.perform_update(request)
    properties.filename, properties.path, properties["time-pos"] = "later.mkv", "/later/later.mkv", 125
    jobs[1].callback("snapshot.avif", nil)
    h.assert_equals(result.tags_by_note, nil)
    properties.filename, properties.path, properties["time-pos"] = "last.mkv", "/last/last.mkv", 185
    jobs[2].callback("audio.ogg", nil)
    assert_update_invocation_tag_test_results(result, case)
    h.assert_equals(request, original_request)
end

--- Capture literal filename/path values and playback time for single and multi-note updates.
local function test_update_captures_invocation_tag()
    for _, case in ipairs {
        { filename = "episode.mkv", name = "episode", note_ids = { 11 }, overwrite = false },
        { filename = "100% fun.mkv", name = "100%_fun", note_ids = { 11, 12 }, overwrite = true },
        { filename = "part%1.mkv", name = "part%1", note_ids = { 11, 12 }, overwrite = false },
    } do
        assert_update_invocation_tag_test_case(case)
    end
end

--- Return separate original and later selections for lifecycle scenarios.
local function make_reentrant_update_test_state()
    local initial = subtitle_module.make_subtitle("Initial selection", 0, 1)
    local state = make_update_test_result()
    state.selection, state.original_selection = initial, initial
    state.later_selection = subtitle_module.make_subtitle("Later selection", 3, 4)
    state.job_starts = {}
    return state
end

--- Build a context whose completion callback installs new interactive state.
local function make_reentrant_update_test_context(state, media)
    local jobs = {}
    local quick_options = fixtures.make_quick_creation_options(state, { lines = 3, cards = 5, record_clear = true })
    local encoder_options = h.shallow_copy(media, {
        on_start = fixtures.make_update_start_test_recorder(state, quick_options),
    })
    local context = make_update_test_context {
        result = state,
        jobs = jobs,
        subtitle = state.original_selection,
        quick_options = quick_options,
        observer = fixtures.make_reentrant_update_test_observer(state),
        encoder = fixtures.make_update_encoder(jobs, encoder_options),
        notify = fixtures.make_reentrant_update_test_notifier(state, quick_options),
    }
    return context, jobs, quick_options
end

--- Assert a completion callback's later selection and options survive the original request.
local function assert_reentrant_update_test_state(state, quick_options)
    h.assert_equals(state.selection, state.later_selection)
    h.assert_equals(quick_options:get_lines(), 7)
    h.assert_equals(quick_options:get_cards(), 9)
    h.assert_equals(state.selection_at_finish, nil)
    h.assert_equals(state.clear_count, 2)
    h.assert_equals(state.appended_note_ids, { 11 })
end

--- Run a lifecycle scenario with synchronous skips or deferred media/write completion.
local function assert_update_start_lifecycle_test_case(case)
    local state = make_reentrant_update_test_state()
    if case.defer_write then state.write_callbacks = {} end
    local context, jobs, quick_options = make_reentrant_update_test_context(state, case.media)
    context.perform_update { note_ids = { 11 }, overwrite = true, subtitle = state.original_selection }
    h.assert_equals(state.job_starts, { { cards = 1 }, { cards = 1 } })
    for _, job in ipairs(jobs) do
        if job.filename then job.callback(job.filename, nil) end
    end
    if case.defer_write then
        h.assert_equals(state.notification, nil)
        state.write_callbacks[11](nil, nil)
    end
    assert_reentrant_update_test_state(state, quick_options)
end

--- Clear old interactive state before any job can invoke synchronous or reentrant callbacks.
local function test_update_clears_state_before_job_start()
    for _, case in ipairs {
        { media = { skip_snapshot = true, skip_audio = true } },
        { media = { skip_snapshot = true, skip_audio = true }, defer_write = true },
        { media = { skip_snapshot = true } },
        { media = { skip_audio = true } },
        { media = {}, defer_write = true },
    } do
        assert_update_start_lifecycle_test_case(case)
    end
end

--- Preserve both selection and quick options when preparation fails before job startup.
local function test_update_preflight_preserves_interactive_state()
    local state = make_reentrant_update_test_state()
    state.media_dir_error = "AnkiConnect unavailable"
    local context, jobs, quick_options = make_reentrant_update_test_context(state, {})
    context.perform_update { note_ids = { 11 }, overwrite = true, subtitle = state.original_selection }
    h.assert_equals(state.selection, state.original_selection)
    h.assert_equals(quick_options:get_lines(), 3)
    h.assert_equals(quick_options:get_cards(), 5)
    h.assert_equals(state.clear_count, 0)
    h.assert_equals(jobs, {})
    h.assert_equals(state.job_starts, {})
    h.assert_equals(state.appended_note_ids, {})
    h.assert_equals(state.notification, "AnkiConnect unavailable")
end

--- Run context tests without requiring mpv-backed components.
local function run_tests(context)
    context = context or make_field_merge_test_context()
    test_join_field_content()
    test_collect_subtitle()
    test_find_recent_note_ids()
    test_find_selected_note_ids()
    test_selected_lookup_retains_snapshot_safeguard()
    test_update_completion()
    test_update_retains_captured_targets()
    test_update_media_failures()
    test_update_without_media_directory()
    test_update_skipped_media_job()
    test_update_write_outcomes()
    test_single_note_update_completion()
    test_update_field_read_failures()
    test_update_preflight_field_reads()
    test_update_notification_field_read_failure()
    test_update_notification_model_lookup_failure()
    test_blank_update_subtitle()
    test_media_metadata()
    test_audio_job_receives_selected_padding()
    test_literal_tag_substitutions()
    test_environment_tag_substitution()
    test_update_captures_invocation_tag()
    test_update_clears_state_before_job_start()
    test_update_preflight_preserves_interactive_state()
    test_update_media_merge()
    test_join_fields(context)
    test_join_fields_duplicates(context)
    test_html_escaping(context)
    test_make_new_note_data(context)
    test_literal_target_highlighting(context)
end

return {
    run_tests = run_tests,
}
