--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Note exporter tests.
]]

local fixtures = require("tests.fixtures")
local h = require("helpers")
local note_exporter = require("anki.note_exporter")
local ankiconnect = require("anki.ankiconnect")
local subtitles_observer = require("subtitles.observer")
local subtitle = require("subtitles.subtitle")
local base64 = require("utils.base64")
local forvo = require("utils.forvo")

--- Create a valid subtitle fixture retaining the real class methods and timings.
local function make_valid_update_test_subtitle(text)
    return subtitle.Subtitle:new {
        text = text or "new sentence",
        secondary = "",
        ["start"] = 0,
        ["end"] = 1,
    }
end

--- Create an invalid subtitle fixture for update tests.
local function make_invalid_update_test_subtitle()
    return {
        --- Mark the subtitle fixture as invalid.
        is_valid = function()
            return false
        end,
    }
end

--- Create the fixed configuration used by exporter tests.
local function make_update_test_config()
    return fixtures.make_update_config {
        card_overwrite_safeguard = 3,
        model_name = "Test model",
        note_tag = "",
    }
end

--- Return the stored sentence used by exporter tests.
local function make_exporter_test_stored_fields()
    return { SentKanji = "old sentence" }
end

--- Create an initialized exporter for update tests.
local function make_update_test_exporter(result, jobs, subtitle, options)
    options = options or {}
    return note_exporter.new().init {
        ankiconnect = options.ankiconnect or fixtures.make_update_ankiconnect(result, make_exporter_test_stored_fields),
        quick_creation_opts = options.quick_options
            or fixtures.make_quick_creation_options(result, { record_clear = true }),
        subs_observer = options.observer
            or fixtures.make_subtitle_observer(result, subtitle or make_valid_update_test_subtitle("new sentence")),
        encoder = fixtures.make_update_encoder(jobs, options.media),
        forvo = options.forvo or fixtures.make_forvo(result),
        cfg_mgr = fixtures.make_config_manager(options.config or make_update_test_config()),
        confirmation = options.confirmation or { cancel = h.noop, confirm = h.noop },
        notify = fixtures.make_notifier(result),
        mp = options.mp,
    }
end

--- Deliver a media job's success path or failure to its registered callback.
local function complete_export_test_job(job, error)
    local path = job.filename
    if error then
        path = nil
    end
    job.callback(path, error)
end

--- Complete requested export jobs, leaving synchronously skipped jobs alone.
local function complete_export_test_media(jobs)
    for _, job in ipairs(jobs) do
        if job.filename then
            complete_export_test_job(job, nil)
        end
    end
end

--- Return a note-field map for the update-test AnkiConnect fake.
local function update_test_note_fields(options, note_id)
    if options.note_fields then
        local sentence = options.note_fields[note_id]
        if sentence == nil then
            return nil
        end
        return { SentKanji = sentence }
    end
    return { SentKanji = options.stored_sentence or "new sentence" }
end

--- Record a field fetch and return the configured fields for one note.
local function get_update_test_note_fields(result, options, note_id)
    result.note_field_fetches = result.note_field_fetches or {}
    result.note_field_fetches[note_id] = (result.note_field_fetches[note_id] or 0) + 1
    if options.read_errors and options.read_errors[note_id] then
        return nil, options.read_errors[note_id]
    end
    local fields = update_test_note_fields(options, note_id)
    if fields == nil then
        return nil, string.format("Could not read note %s", tostring(note_id))
    end
    return fields, nil
end

--- Read a scenario's target fields as one fail-closed batch.
local function read_update_test_target_fields(result, options, note_ids)
    local fields_by_id = {}
    for _, note_id in ipairs(note_ids) do
        local fields, error = get_update_test_note_fields(result, options, note_id)
        if error then
            return nil, error
        end
        fields_by_id[note_id] = fields
    end
    return fields_by_id, nil
end

--- Return the AnkiConnect fake used by update tests.
local function make_update_test_ankiconnect(result, options)
    result.last_note_ids = options.last_note_ids
    result.selected_note_ids = options.selected_note_ids
    --- Supply scenario-specific fields after the shared fake records the request.
    result.read_fields = function(note_ids)
        return read_update_test_target_fields(result, options, note_ids)
    end
    --- Preview reads do not count as update-target field requests.
    result.read_preview = function(note_id)
        local fields = update_test_note_fields(options, note_id)
        if fields == nil then
            return nil, string.format("Could not read note %s", tostring(note_id))
        end
        return fields, nil
    end
    return fixtures.make_update_ankiconnect(
        result,
        function(note_id)
            return update_test_note_fields(options, note_id)
        end
    )
end

--- Create fresh subtitle data for a guarded exporter test scenario.
local function make_guarded_update_test_subtitle(options)
    local subtitle = make_valid_update_test_subtitle(options.current_sentence or "new sentence")
    if options.valid == false then
        subtitle.is_valid = function()
            return false
        end
    end
    return subtitle
end

--- Construct an exporter with controllable confirmation-test dependencies.
local function make_guarded_update_test_exporter(result, jobs, options)
    options = options or {}
    local confirmation = options.confirmation or { cancel = h.noop, confirm = h.noop }
    return note_exporter.new().init({
        ankiconnect = make_update_test_ankiconnect(result, options),
        quick_creation_opts = fixtures.make_quick_creation_options(result, {
            cards = options.card_count or #(options.last_note_ids or {}),
            record_clear = true,
        }),
        subs_observer = fixtures.make_subtitle_observer(result, make_guarded_update_test_subtitle(options)),
        encoder = fixtures.make_update_encoder(jobs),
        forvo = fixtures.make_forvo(result),
        cfg_mgr = fixtures.make_config_manager(make_update_test_config()),
        confirmation = confirmation,
        notify = fixtures.make_notifier(result),
    })
end

--- Return a confirmation fake that retains and cancels one pending request.
local function make_update_test_confirmation(result)
    return {
        cancel = function()
            if result.confirmation then
                result.confirmation.on_cancel()
                result.confirmation = nil
            end
        end,
        confirm = function(options)
            result.confirmation = options
        end,
    }
end

--- Create a started mismatched-update test fixture.
local function make_mismatched_update_test_fixture()
    local result = { append_count = 0 }
    local jobs = {}
    local note_id = h.minutes_ago(1)
    make_guarded_update_test_exporter(result, jobs, {
        confirmation = make_update_test_confirmation(result),
        current_sentence = "それは うまくすれば 鉛から黄金を生み出すことも 可能になる",
        stored_sentence = "まあ 無理やり手伝った というのが正しいけれど それで稼いだお金よ",
        last_note_ids = { note_id },
    }).update_last_note(true)
    return result, jobs, note_id
end

--- Test that a mismatched note remains unchanged until acceptance.
local function test_mismatched_update_requires_confirmation()
    local result, jobs, note_id = make_mismatched_update_test_fixture()
    h.assert_equals(#jobs, 0)
    h.assert_equals(
        result.confirmation.prompt,
        "The target note's SentKanji does not match the current subtitle.\nUpdate this note anyway?"
    )
    result.confirmation.on_accept()
    h.assert_equals(#jobs, 2)
    jobs[1].callback()
    jobs[2].callback()
    h.assert_equals(result.append_count, 1)
    h.assert_equals(result.note_field_fetches[note_id], 1)
    h.assert_equals(result.clear_count, 2)
end

--- Test that cancelling a mismatched update preserves its selection.
local function test_cancelled_update_preserves_selection()
    local result, jobs = make_mismatched_update_test_fixture()
    result.confirmation.on_cancel()
    h.assert_equals(#jobs, 0)
    h.assert_equals({ result.clear_count, result.menu_updates }, { nil, nil })
end

--- Test a valid but empty current subtitle requires confirmation before media generation.
local function test_empty_current_subtitle_requires_confirmation()
    local result = { append_count = 0 }
    local jobs = {}
    make_guarded_update_test_exporter(result, jobs, {
        confirmation = make_update_test_confirmation(result),
        current_sentence = "",
        last_note_ids = { h.minutes_ago(1) },
    }).update_last_note(true)
    h.assert_equals(#jobs, 0)
    h.assert_equals(
        result.confirmation.prompt,
        "Couldn't verify the current subtitle against target notes' SentKanji field.\nUpdate this note anyway?"
    )
    result.confirmation.on_cancel()
    h.assert_equals({ result.clear_count, result.menu_updates }, { nil, nil })
end

--- Test an accepted recent update reuses target fields read before confirmation.
local function test_accepted_update_reuses_target_snapshot()
    local note_id = h.minutes_ago(1)
    local result = { append_count = 0 }
    local jobs = {}
    local options = {
        confirmation = make_update_test_confirmation(result),
        current_sentence = "new sentence",
        note_fields = { [note_id] = "old sentence" },
        last_note_ids = { note_id },
    }
    make_guarded_update_test_exporter(result, jobs, options).update_last_note(true)
    options.note_fields[note_id] = "changed sentence"
    result.confirmation.on_accept()
    jobs[1].callback()
    jobs[2].callback()
    h.assert_equals(result.forvo_stored_data.SentKanji, "old sentence")
    h.assert_equals(result.note_field_fetches[note_id], 1)
end

--- Return recent note IDs for exporter update tests.
local function make_recent_note_test_ids()
    return { h.minutes_ago(2), h.minutes_ago(1) }
end

--- Test that matching recent notes update without a confirmation prompt.
local function test_update_last_note_with_matching_sentences()
    local note_ids = make_recent_note_test_ids()
    local result = { append_count = 0 }
    local jobs = {}
    make_guarded_update_test_exporter(result, jobs, {
        current_sentence = "shared sentence",
        note_fields = { [note_ids[1]] = "shared sentence", [note_ids[2]] = "shared sentence" },
        last_note_ids = note_ids,
    }).update_last_note(true)
    h.assert_equals(#jobs, 2)
    h.assert_equals(result.clear_count, 2)
    h.assert_equals(result.menu_updates, 1)
    h.assert_equals(result.note_field_fetches[note_ids[1]], 1)
    h.assert_equals(result.note_field_fetches[note_ids[2]], 1)
end

--- Test that mixed recent notes show a mismatch warning before updating.
local function test_update_last_note_with_mismatched_sentences()
    local note_ids = make_recent_note_test_ids()
    local result = { append_count = 0 }
    local jobs = {}
    make_guarded_update_test_exporter(result, jobs, {
        confirmation = make_update_test_confirmation(result),
        current_sentence = "new sentence",
        note_fields = { [note_ids[1]] = "old sentence", [note_ids[2]] = "new sentence" },
        last_note_ids = note_ids,
    }).update_last_note(true)
    h.assert_equals(#jobs, 0)
    h.assert_equals(
        result.confirmation.prompt,
        "Only 1 of 2 target notes have SentKanji matching the current subtitle.\n" .. "Update all 2 notes anyway?"
    )
    h.assert_equals(result.note_field_fetches[note_ids[1]], 1)
    h.assert_equals(result.note_field_fetches[note_ids[2]], 1)
end

--- A blank stored sentence is readable but requires explicit confirmation.
local function test_update_last_note_with_unverifiable_field()
    local note_ids = make_recent_note_test_ids()
    local result = { append_count = 0 }
    local jobs = {}
    make_guarded_update_test_exporter(result, jobs, {
        confirmation = make_update_test_confirmation(result),
        note_fields = { [note_ids[1]] = "old sentence", [note_ids[2]] = "" },
        last_note_ids = note_ids,
    }).update_last_note(true)
    h.assert_equals(#jobs, 0)
    h.assert_equals(
        result.confirmation.prompt,
        "Only 0 of 2 target notes have SentKanji matching the current subtitle.\nUpdate all 2 notes anyway?"
    )
    h.assert_equals(result.note_field_fetches[note_ids[2]], 1)
end

--- One failed field read aborts every target without a confirmation or media job.
local function test_update_last_note_aborts_on_field_error()
    local note_ids = make_recent_note_test_ids()
    local result = { append_count = 0 }
    local jobs = {}
    make_guarded_update_test_exporter(result, jobs, {
        confirmation = make_update_test_confirmation(result),
        note_fields = { [note_ids[1]] = "old sentence", [note_ids[2]] = "old sentence" },
        read_errors = { [note_ids[2]] = string.format("Could not read note %s", tostring(note_ids[2])) },
        last_note_ids = note_ids,
    }).update_last_note(true)
    h.assert_equals(#jobs, 0)
    h.assert_equals(result.append_count, 0)
    h.assert_equals(result.confirmation, nil)
    h.assert_equals(result.clear_count, nil)
    h.assert_equals(result.notification, string.format("Could not read note %s", tostring(note_ids[2])))
    h.assert_equals(result.notification_level, "error")
end

--- Test that a file transition cancels the pending update rather than accepting stale timings.
local function test_cancel_pending_update_cancels_confirmation()
    local result = { append_count = 0 }
    local jobs = {}
    local confirmation = make_update_test_confirmation(result)
    local exporter = make_guarded_update_test_exporter(result, jobs, {
        confirmation = confirmation,
        current_sentence = "new sentence",
        stored_sentence = "old sentence",
        last_note_ids = { h.minutes_ago(1) },
    })
    exporter.update_last_note(true)
    h.assert_equals(type(result.confirmation), "table")
    exporter.cancel_pending_update()
    exporter.cancel_pending_update()
    h.assert_equals({ #jobs, result.clear_count, result.confirmation }, { 0, nil, nil })
end

--- File transitions cancel confirmations and reset subtitle and card options.
local function test_file_change_cancels_and_clears()
    note_exporter.new().cancel_pending_update_for_file_change() -- safe before init
    local result = { append_count = 0 }
    local jobs = {}
    local confirmation = make_update_test_confirmation(result)
    local exporter = make_guarded_update_test_exporter(result, jobs, {
        confirmation = confirmation,
        stored_sentence = "old sentence",
        last_note_ids = { h.minutes_ago(1) },
    })
    exporter.update_last_note(true)
    h.assert_equals(type(result.confirmation), "table")
    exporter.cancel_pending_update_for_file_change()
    h.assert_equals(result.confirmation, nil)
    h.assert_equals(result.clear_count, 2)
    h.assert_equals(#jobs, 0)
end

--- Return blocked lookup scenarios with the required 4-second warning duration.
local function make_blocked_update_test_cases()
    return {
        { method = "update_last_note", last_note_ids = { h.minutes_ago(11) }, duration = 4 },
        { method = "update_selected_note", selected_note_ids = {}, duration = 4 },
        { method = "update_selected_note", selected_note_ids = { 1, 2, 3, 4 }, duration = 4 },
    }
end

--- Test that blocked note-update entry points cancel a pending confirmation.
local function test_blocked_updates_cancel_confirmation()
    for _, scenario in ipairs(make_blocked_update_test_cases()) do
        local result = { append_count = 0, cancel_count = 0 }
        local confirmation = make_update_test_confirmation(result)
        confirmation.cancel = function()
            result.cancel_count = result.cancel_count + 1
        end
        local exporter = make_guarded_update_test_exporter(result, {}, {
            confirmation = confirmation,
            last_note_ids = scenario.last_note_ids,
            selected_note_ids = scenario.selected_note_ids,
        })
        exporter[scenario.method](true)
        h.assert_equals({ result.cancel_count, result.append_count }, { 1, 0 })
        h.assert_equals(result.notification_duration, scenario.duration)
    end
end

--- Test that selected-note updates remain immediate when their fields differ.
local function test_mismatched_selected_note_update()
    local result = { append_count = 0 }
    local jobs = {}
    make_guarded_update_test_exporter(result, jobs, {
        confirmation = make_update_test_confirmation(result),
        current_sentence = "selected sentence",
        stored_sentence = "different sentence",
        selected_note_ids = { 1 },
    }).update_selected_note(true)
    h.assert_equals(result.confirmation, nil)
    h.assert_equals(#jobs, 2)
    jobs[1].callback()
    jobs[2].callback()
    h.assert_equals(result.append_count, 1)
    h.assert_equals(result.note_field_fetches[1], 1)
end

--- Wait for both media jobs and pass original stored fields to pronunciation merging.
local function test_update_notes_after_media_created()
    local result = { append_count = 0, clear_count = 0 }
    local jobs = {}
    make_update_test_exporter(result, jobs).update_notes({ 1 }, true)
    h.assert_equals(#jobs, 2)
    jobs[1].callback("snapshot.avif", nil)
    h.assert_equals(result.append_count, 0)
    h.assert_equals(result.forvo_stored_data, nil)
    jobs[2].callback("audio.ogg", nil)
    h.assert_equals(result.forvo_stored_data, { SentKanji = "old sentence" })
    h.assert_equals(result.append_count, 1)
    h.assert_equals(result.clear_count, 2)
    h.assert_equals(result.field_requests, { { 1 } })
    h.assert_equals(result.preview_reads, { 1 })
    h.assert_equals(result.note_id, 1)
    h.assert_equals(result.fields.SentKanji, "new sentence")
    h.assert_equals(result.fields.SentAudio, "[sound:audio.ogg]")
    h.assert_equals(result.fields.Image, '<img alt="snapshot" src="snapshot.avif">')
end

--- Update media for a blank real subtitle without replacing its stored sentence or source text.
local function test_blank_subtitle_update()
    local result, jobs = { append_count = 0, clear_count = 0 }, {}
    local sub = subtitle.Subtitle:new { text = "", secondary = "", ["start"] = 0, ["end"] = 1 }
    local exporter = make_update_test_exporter(result, jobs, sub)
    h.assert_equals(rawequal(exporter.update_notes({ 13 }, true), exporter), true)
    h.assert_equals(rawget(sub, "text"), "")
    h.assert_equals(result.append_count, 0)
    complete_export_test_media(jobs)
    h.assert_equals(result.fields.SentKanji, "old sentence")
    h.assert_equals(result.fields.SentAudio, "[sound:audio.ogg]")
    h.assert_equals(result.fields.Image, '<img alt="snapshot" src="snapshot.avif">')
    h.assert_equals(rawget(sub, "text"), "")
    h.assert_equals(sub:duration(), 1)
end

--- Test that invalid subtitles do not start an update.
local function test_invalid_subtitle_does_not_start_update()
    local result = { append_count = 0, clear_count = 0 }
    local jobs = {}
    local exporter = make_update_test_exporter(result, jobs, make_invalid_update_test_subtitle())
    h.assert_equals(rawequal(exporter.update_notes({ 1 }, true), exporter), true)
    h.assert_equals(#jobs, 0)
    h.assert_equals(result.append_count, 0)
    h.assert_equals(result.clear_count, 0)
end

--- Preserve the public return value and interactive state when target lookup fails.
local function assert_lookup_warning_test_case(case)
    local result, jobs = { append_count = 0, clear_count = 0 }, {}
    result.last_note_ids, result.selected_note_ids = case.recent_ids, case.selected_ids
    local config = make_update_test_config()
    config.card_overwrite_safeguard = 3
    local exporter = make_update_test_exporter(result, jobs, nil, { config = config })
    h.assert_equals(rawequal(exporter[case.method](true), exporter), true)
    h.assert_equals(result.notification, case.warning)
    h.assert_equals(result.notification_level, "warn")
    h.assert_equals(result.notification_duration, 4)
    h.assert_equals(result.current_collections, nil)
    h.assert_equals(result.field_requests, nil)
    h.assert_equals(result.clear_count, 0)
    h.assert_equals(result.append_count, 0)
    h.assert_equals(jobs, {})
end

--- Use a unified warning duration for missing, expired, and excessive lookup targets.
local function test_lookup_warnings()
    for _, case in ipairs {
        { method = "update_last_note", recent_ids = {}, warning = "Couldn't find the target note." },
        {
            method = "update_last_note",
            recent_ids = { h.minutes_ago(11) },
            warning = "Couldn't find the target note.",
        },
        {
            method = "update_selected_note",
            selected_ids = {},
            warning = "Couldn't find the target note(s). Did you select the notes you want in Anki?",
        },
        {
            method = "update_selected_note",
            selected_ids = { 11, 12, 13, 14 },
            warning = "More than 3 notes selected\nnot recommended, but you can change the limit in your config",
        },
    } do
        assert_lookup_warning_test_case(case)
    end
end

--- Dispatch validated IDs and overwrite mode without replacing their captured context.
local function assert_lookup_dispatch_test_case(case)
    local result, jobs = { append_count = 0, clear_count = 0 }, {}
    result.last_note_ids, result.selected_note_ids = case.recent_ids, case.selected_ids
    local config = make_update_test_config()
    config.card_overwrite_safeguard = 3
    local exporter = make_update_test_exporter(result, jobs, nil, {
        config = config,
        confirmation = fixtures.make_accepting_confirmation(),
    })
    h.assert_equals(rawequal(exporter[case.method](case.overwrite), exporter), true)
    h.assert_equals(#jobs, 2)
    h.assert_equals(result.field_requests, { case.expected_ids })
    h.assert_equals(#result.client_cfg_mgrs, 1)
    h.assert_equals(rawequal(jobs[1].cfg_mgr, result.client_cfg_mgrs[1]), true)
    complete_export_test_media(jobs)
    h.assert_equals(result.field_requests, { case.expected_ids })
    h.assert_equals(result.append_count, #case.expected_ids)
    for _, note_id in ipairs(case.expected_ids) do
        h.assert_equals(result.fields_by_note[note_id].SentKanji, case.sentence)
    end
end

--- Retain immediate recent and selected updates using the original captured provider.
local function test_lookup_dispatch()
    local recent = h.minutes_ago(1)
    for _, case in ipairs {
        {
            method = "update_last_note",
            recent_ids = { recent },
            expected_ids = { recent },
            overwrite = true,
            sentence = "new sentence",
        },
        {
            method = "update_selected_note",
            selected_ids = { 11, 12, 13 },
            expected_ids = { 11, 12, 13 },
            overwrite = false,
            sentence = "new sentence<br>old sentence",
        },
    } do
        assert_lookup_dispatch_test_case(case)
    end
end

--- Test ordinary exports use the context to create and write note fields.
local function test_export_to_anki()
    local result = { append_count = 0, clear_count = 0 }
    local jobs = {}
    make_update_test_exporter(result, jobs).export_to_anki(false)
    h.assert_equals(#jobs, 2)
    h.assert_equals(jobs[1].started, true)
    h.assert_equals(jobs[2].started, true)
    h.assert_equals(result.fields, nil)
    h.assert_equals(result.clear_count, 1)
    jobs[2].callback("audio.ogg", nil)
    h.assert_equals(result.fields, nil)
    jobs[1].callback("snapshot.avif", nil)
    h.assert_equals(result.fields.SentKanji, "new sentence")
    h.assert_equals(result.fields.SentAudio, "[sound:audio.ogg]")
    h.assert_equals(result.fields.Image, '<img alt="snapshot" src="snapshot.avif">')
    h.assert_equals(result.tag, "")
    h.assert_equals(result.gui, false)
    h.assert_equals(result.clear_count, 1)
    h.assert_equals(result.add_count, 1)
end

--- Keep the subtitle and skip note creation until Anki's media directory is available.
local function test_export_without_media_directory()
    local result = { append_count = 0, clear_count = 0, media_dir_error = "AnkiConnect unavailable" }
    local jobs = {}
    local subtitle = make_valid_update_test_subtitle("new sentence")
    local exporter = make_update_test_exporter(result, jobs, subtitle)
    exporter.export_to_anki(false)
    h.assert_equals(#jobs, 0)
    h.assert_equals(result.fields, nil)
    h.assert_equals(result.clear_count, 0)
    h.assert_equals(result.notification, "AnkiConnect unavailable")
    h.assert_equals(result.notification_level, "error")

    result.media_dir_error = nil
    exporter.export_to_anki(false)
    h.assert_equals(#jobs, 2)
    complete_export_test_media(jobs)
    h.assert_equals(result.fields.SentKanji, "new sentence")
    h.assert_equals(result.clear_count, 1)
end

--- Failed model lookup aborts before media creation and keeps the selection for a retry.
local function test_export_without_first_field()
    local result = { append_count = 0, clear_count = 0, first_field_error = "Note type missing" }
    local jobs = {}
    local exporter = make_update_test_exporter(result, jobs)
    exporter.export_to_anki(false)
    h.assert_equals(#jobs, 0)
    h.assert_equals(result.fields, nil)
    h.assert_equals(result.clear_count, 0)
    h.assert_equals(result.notification, "Note type missing")
    h.assert_equals(result.notification_level, "error")
    result.first_field_error = nil
    exporter.export_to_anki(false)
    h.assert_equals(#jobs, 2)
    complete_export_test_media(jobs)
    h.assert_equals(result.fields.SentKanji, "new sentence")
    h.assert_equals(result.clear_count, 1)
end

--- An unset first field still receives the fallback required by Anki.
local function test_export_populates_first_field()
    local result = { append_count = 0, clear_count = 0, first_field = "Word" }
    local jobs = {}
    make_update_test_exporter(result, jobs).export_to_anki(false)
    complete_export_test_media(jobs)
    h.assert_equals(result.fields.Word, "[empty]")
    h.assert_equals(result.fields.SentKanji, "new sentence")
end

--- Complete a failed media pair without allowing any note addition.
local function assert_export_media_failure(case)
    local result = { clear_count = 0 }
    local jobs = {}
    make_update_test_exporter(result, jobs).export_to_anki(false)
    complete_export_test_job(jobs[1], case.snapshot_error)
    h.assert_equals(result.fields, nil)
    h.assert_equals(result.notification, nil)
    complete_export_test_job(jobs[2], case.audio_error)
    h.assert_equals(result.fields, nil)
    h.assert_equals(result.add_count, nil)
    h.assert_equals(result.notification, "Failed to create media: " .. case.expected)
    h.assert_equals(result.notification_level, "error")
    h.assert_equals(result.clear_count, 1)
end

--- Each requested media failure prevents adding a note after the entire batch finishes.
local function test_export_media_failures()
    for _, case in ipairs {
        { snapshot_error = "image failed", expected = "snapshot: image failed" },
        { audio_error = "audio failed", expected = "audio: audio failed" },
        {
            snapshot_error = "image failed",
            audio_error = "audio failed",
            expected = "snapshot: image failed; audio: audio failed",
        },
    } do
        assert_export_media_failure(case)
    end
end

--- Skipped tracks count as completions without adding nonexistent filenames to fields.
local function test_export_skipped_media()
    for _, media in ipairs {
        { skip_snapshot = true },
        { skip_audio = true },
        { skip_snapshot = true, skip_audio = true },
    } do
        local result = { clear_count = 0 }
        local jobs = {}
        make_update_test_exporter(result, jobs, nil, { media = media }).export_to_anki(true)
        complete_export_test_media(jobs)
        h.assert_equals(result.add_count, 1)
        h.assert_equals(result.gui, true)
        h.assert_equals(result.fields.Image ~= nil, not media.skip_snapshot)
        h.assert_equals(result.fields.SentAudio ~= nil, not media.skip_audio)
        h.assert_equals(result.clear_count, 1)
    end
end

--- Completion writes the captured fields and tag without clearing a later subtitle selection.
local function test_export_captures_request()
    local result = { clear_count = 0 }
    local jobs = {}
    local subtitle = make_valid_update_test_subtitle()
    local config = make_update_test_config()
    config.note_tag = "%t"
    local properties = { filename = "episode.mkv", ["time-pos"] = 65, duration = 200 }
    local exporter = make_update_test_exporter(result, jobs, subtitle, {
        config = config,
        mp = fixtures.make_mp_property_reader(properties),
    })
    exporter.export_to_anki(false)
    subtitle.text = "later subtitle selection"
    properties["time-pos"] = 125
    complete_export_test_media(jobs)
    h.assert_equals(result.fields.SentKanji, "new sentence")
    h.assert_equals(result.tag, "01m05s000ms")
    h.assert_equals(subtitle.text, "later subtitle selection")
    h.assert_equals(result.clear_count, 1)
end

--- Return note and transport settings representing the original export profile.
local function make_export_destination_test_config()
    local config = make_update_test_config()
    config.deck_name = "Original deck"
    config.allow_duplicates = false
    config.ankiconnect_url = "http://original-server:8765"
    config.ankiconnect_api_key = "original-key"
    return config
end

--- Verify the captured request payload and transport use the same original profile.
local function assert_export_destination_test_request(result)
    h.assert_equals(#result.note_requests, 1)
    local note = result.note_requests[1].params.note
    h.assert_equals(note.deckName, "Original deck")
    h.assert_equals(note.modelName, "Test model")
    h.assert_equals(note.options.allowDuplicate, false)
    h.assert_equals(note.fields.SentKanji, "new sentence")
    h.assert_equals(result.transport_calls[1].url, "http://original-server:8765")
    h.assert_equals(result.note_requests[1].key, nil)
    h.assert_equals(result.transport_calls[1].request_json:match('"key"%s*:%s*"([^"]*)"'), "original-key")
end

--- Pending exports retain their original destination when the live profile changes.
local function test_export_captures_destination()
    local result, jobs = {}, {}
    local config = make_export_destination_test_config()
    local client = fixtures.make_note_add_client(result, ankiconnect.new, config, {
        platform = fixtures.make_recording_anki_platform(result),
    })
    local exporter = make_update_test_exporter(result, jobs, nil, { config = config, ankiconnect = client })
    exporter.export_to_anki(false)
    h.assert_equals(result.note_requests, nil)
    config.deck_name = "Different deck"
    config.model_name = "Different model"
    config.allow_duplicates = true
    config.ankiconnect_url = "http://different-server:8765"
    config.ankiconnect_api_key = "different-key"
    complete_export_test_media(jobs)
    assert_export_destination_test_request(result)
end

--- Return settings whose field, pronunciation, and transport values change during an update.
local function make_transaction_update_test_config(append_media)
    return h.shallow_copy({
        append_media = append_media,
        disable_gui_browse = false,
        note_tag = "original-tag",
        card_overwrite_safeguard = 1,
        use_forvo = "always",
        vocab_field = "Word",
        vocab_audio_field = "VocabAudio",
        audio_format = "opus",
        audio_codec = "libopus",
        audio_extension = ".ogg",
        audio_bitrate = "32k",
    }, make_export_destination_test_config())
end

--- Build raw stored fields and endpoint-specific media directories for recording clients.
local function make_transaction_update_test_state(note_ids)
    local state = {
        target_ids = note_ids,
        stored_fields = {},
        media_dirs = {
            ["http://original-server:8765"] = "/original-media",
            ["http://different-server:8765"] = "/different-media",
        },
    }
    for _, note_id in ipairs(note_ids) do
        state.stored_fields[note_id] = {
            SentKanji = "stored sentence",
            SentAudio = "[sound:stored.ogg]",
            Image = '<img src="stored.jpg">',
            Word = "word",
            VocabAudio = "",
        }
    end
    return state
end

--- Construct an exporter using real Anki request serialization with fake responses.
local function make_transaction_update_test_exporter(state, jobs, config, pronunciation)
    local cfg_mgr = fixtures.make_config_manager(config)
    local client = fixtures.make_update_transport_test_client(state, ankiconnect.new, cfg_mgr)
    return make_update_test_exporter(state, jobs, nil, {
        config = config,
        ankiconnect = client,
        forvo = pronunciation,
        mp = fixtures.make_mp_property_reader { filename = "episode.mkv", ["time-pos"] = 65, duration = 200 },
        confirmation = fixtures.make_accepting_confirmation(),
    })
end

--- Change live settings after media starts without modifying captured providers.
local function change_transaction_update_test_profile(config)
    h.shallow_copy({
        sentence_field = "DifferentSentence",
        audio_field = "DifferentAudio",
        image_field = "DifferentImage",
        model_name = "Different model",
        append_media = not config.append_media,
        ankiconnect_url = "http://different-server:8765",
        ankiconnect_api_key = "different-key",
        disable_gui_browse = true,
        note_tag = "different-tag",
        use_forvo = "no",
        audio_format = "mp3",
        audio_codec = "libmp3lame",
        audio_extension = ".mp3",
        audio_bitrate = "96k",
    }, config)
end

--- Construct real Forvo behavior with recording page, download, encoding, and cleanup boundaries.
local function make_transaction_update_test_pronunciation(config)
    local state = { requests = {}, encodings = {}, removed = {}, warnings = {} }
    local page = string.format("Play('%s','%s');", base64.enc("clip.mp3"), base64.enc("clip.ogg"))
    local dependencies = fixtures.make_forvo_dependencies(state, {
        { status = 0, stdout = page },
        { status = 0 },
    })
    return forvo.new(dependencies).init(fixtures.make_config_manager(config)), state
end

--- Assert original fields and pronunciation settings were used after a live profile change.
local function assert_transaction_update_test_write(state, pronunciation, note_id, append_media)
    local request = state.anki_requests[#state.anki_requests].request
    h.assert_equals(request.action, "updateNoteFields")
    h.assert_equals(request.params.note.id, note_id)
    local fields = request.params.note.fields
    local expected = "new sentence<br>stored sentence"
    if append_media then expected = "stored sentence<br>new sentence" end
    h.assert_equals(fields.SentKanji, expected)
    h.assert_equals(fields.DifferentSentence, nil)
    -- Reverse merge keeps stored ancillary fields. Encoding must retain its settings in either order.
    if append_media then
        h.assert_equals(fields.VocabAudio, "[sound:forvo_word.ogg]")
    end
    h.assert_equals(pronunciation.requests[2][1], "https://audio00.forvo.com/ogg/clip.ogg")
    local args = pronunciation.encodings[1]
    h.assert_equals(args[#args], "-o=/original-media/forvo_word.ogg")
    h.assert_equals(args[#args - 1], "--oacopts-add=b=32k")
    h.assert_equals(args[#args - 3], "--oac=libopus")
    h.assert_equals(pronunciation.warnings, {})
end

--- Assert every serialized read, write, tag, and Browser request uses its own captured provider.
local function assert_transaction_update_test_transport(state)
    for index, options in ipairs(state.anki_transport) do
        local record = state.anki_requests[index]
        local config = record.cfg_mgr.config()
        h.assert_equals(options.url, config.ankiconnect_url)
        h.assert_equals(options.request_json:match('"key"%s*:%s*"([^"]*)"'), config.ankiconnect_api_key)
        if record.request.action == "findModelsByName" then
            h.assert_equals(record.request.params.modelNames, { config.model_name })
        elseif record.request.action == "addTags" then
            h.assert_equals(record.request.params.tags, config.note_tag)
        end
    end
end

--- Exercise one entry point across both media and deferred Anki-write profile changes.
local function assert_transaction_update_test_case(case)
    local note_id = h.minutes_ago(0) + 1
    local state, jobs = make_transaction_update_test_state({ note_id }), {}
    local config = make_transaction_update_test_config(case.append_media)
    local pronunciation, pronunciation_state = make_transaction_update_test_pronunciation(config)
    local exporter = make_transaction_update_test_exporter(state, jobs, config, pronunciation)
    if case.command == "update_notes" then
        exporter.update_notes({ note_id }, false)
    else
        exporter[case.command](false)
    end
    change_transaction_update_test_profile(config)
    complete_export_test_media(jobs)
    assert_transaction_update_test_write(state, pronunciation_state, note_id, case.append_media)
    config.ankiconnect_url, config.ankiconnect_api_key = "http://third-server:8765", "third-key"
    state.anki_write_callbacks[note_id](true, {}, nil)
    assert_transaction_update_test_transport(state)
    h.assert_equals(state.notification, "Updated note: stored sentence.")
    h.assert_equals(state.clear_count, 2) -- Selection and quick options are cleared once each.
end

--- Verify direct, recent, and selected updates retain original settings through completion.
local function test_update_transactions_capture_profile()
    for _, case in ipairs {
        { command = "update_notes", append_media = true },
        { command = "update_notes", append_media = false },
        { command = "update_last_note", append_media = true },
        { command = "update_selected_note", append_media = true },
    } do
        assert_transaction_update_test_case(case)
    end
end

--- Start a recent-note prompt with real request serialization and invocation metadata.
local function make_waiting_profile_test_fixture()
    local note_id = h.minutes_ago(1)
    local state, jobs = make_transaction_update_test_state({ note_id }), {}
    local config = make_transaction_update_test_config(true)
    config.note_tag, config.miscinfo_format = "%t|%f", "%t|%f"
    config.miscinfo_enable, config.miscinfo_field, config.use_forvo = true, "Notes", "no"
    local properties = { filename = "original.mkv", path = "/videos/original%1.mkv", ["time-pos"] = 65, duration = 200 }
    local client =
        fixtures.make_update_transport_test_client(state, ankiconnect.new, fixtures.make_config_manager(config))
    local exporter = make_update_test_exporter(state, jobs, make_valid_update_test_subtitle("new sentence"), {
        config = config,
        ankiconnect = client,
        mp = fixtures.make_mp_property_reader(properties),
        confirmation = make_update_test_confirmation(state),
    })
    exporter.update_last_note(false)
    return state, jobs, config, properties, note_id
end

--- Verify all captured transport calls and formatted tags use their pre-prompt values.
local function assert_waiting_profile_test_transport(state)
    local expected = "01m05s000ms|/videos/original%1.mkv"
    for index, options in ipairs(state.anki_transport) do
        h.assert_equals(options.url, "http://original-server:8765")
        h.assert_equals(options.request_json:match('"key"%s*:%s*"([^"]*)"'), "original-key")
        local request = state.anki_requests[index].request
        if request.action == "addTags" then h.assert_equals(request.params.tags, expected) end
    end
end

--- Verify media timestamp and prepared fields remain paired with the original transaction.
local function assert_waiting_profile_test_result(state, jobs)
    h.assert_equals(jobs[1].argument, 65)
    local write = state.anki_requests[#state.anki_requests].request
    h.assert_equals(write.params.note.fields.Notes, "01m05s000ms|/videos/original%1.mkv")
    h.assert_equals(write.params.note.fields.SentKanji, "stored sentence<br>new sentence")
    assert_waiting_profile_test_transport(state)
end

--- Change profiles and playback while a prompt waits without retargeting the accepted update.
local function test_confirmation_captures_profile_and_metadata()
    local state, jobs, config, properties, note_id = make_waiting_profile_test_fixture()
    h.assert_equals(jobs, {})
    change_transaction_update_test_profile(config)
    properties.filename, properties.path, properties["time-pos"] = "later.mkv", "/later/later.mkv", 125
    state.confirmation.on_accept()
    complete_export_test_media(jobs)
    assert_waiting_profile_test_result(state, jobs)
    state.anki_write_callbacks[note_id](true, {}, nil)
    assert_waiting_profile_test_transport(state)
    local note_field_reads = 0
    for _, item in ipairs(state.anki_requests) do
        if item.request.action == "notesInfo" then note_field_reads = note_field_reads + 1 end
    end
    h.assert_equals(note_field_reads, 2) -- One target-field read and one notification-only preview.
end

--- Complete one media pair without completing later requests' pending jobs.
local function complete_transaction_update_test_pair(jobs, first_index)
    complete_export_test_job(jobs[first_index], nil)
    complete_export_test_job(jobs[first_index + 1], nil)
end

--- Assert encoder, Forvo, and Anki providers remain paired within overlapping requests.
local function assert_concurrent_update_test_ownership(state, jobs)
    h.assert_equals(jobs[1].cfg_mgr == jobs[2].cfg_mgr, true)
    h.assert_equals(jobs[3].cfg_mgr == jobs[4].cfg_mgr, true)
    h.assert_equals(jobs[1].cfg_mgr == jobs[3].cfg_mgr, false)
    h.assert_equals(jobs[1].output_dir, "/original-media")
    h.assert_equals(jobs[3].output_dir, "/different-media")
    h.assert_equals(state.forvo_calls[1].cfg_mgr == jobs[1].cfg_mgr, true)
    h.assert_equals(state.forvo_calls[2].cfg_mgr == jobs[3].cfg_mgr, true)
    h.assert_equals(state.forvo_calls[1].output_dir, "/original-media")
    h.assert_equals(state.forvo_calls[2].output_dir, "/different-media")
end

--- Verify overlapping updates own different providers and pronunciation destinations.
local function test_update_transactions_isolate_media_directories()
    local state, jobs = make_transaction_update_test_state({ 11, 12 }), {}
    local config = make_transaction_update_test_config(true)
    local exporter = make_transaction_update_test_exporter(state, jobs, config)
    exporter.update_notes({ 11 }, true)
    config.ankiconnect_url, config.ankiconnect_api_key = "http://different-server:8765", "different-key"
    config.note_tag = "second-tag"
    exporter.update_notes({ 12 }, true)
    complete_transaction_update_test_pair(jobs, 1)
    complete_transaction_update_test_pair(jobs, 3)
    assert_concurrent_update_test_ownership(state, jobs)
    h.assert_equals(state.notification, nil)
    state.anki_write_callbacks[12](true, {}, nil)
    state.anki_write_callbacks[11](true, {}, nil)
    assert_transaction_update_test_transport(state)
end

--- Build a file-transition fixture using the real subtitle selection implementation.
local function make_file_change_test_context()
    local observer = subtitles_observer.new()
    observer.import_subs { subtitle.make_subtitle("Old file selection", 20, 22) }
    local options = fixtures.make_quick_creation_options({}, { lines = 3, cards = 5 })
    local state, jobs = {}, {}
    local exporter = note_exporter.new().init {
        ankiconnect = fixtures.make_update_ankiconnect(state, make_exporter_test_stored_fields),
        quick_creation_opts = options,
        subs_observer = observer,
        encoder = fixtures.make_update_encoder(jobs),
        forvo = fixtures.make_forvo(),
        cfg_mgr = fixtures.make_config_manager(make_update_test_config()),
    }
    return exporter, observer, options, state, jobs
end

--- File changes discard the old selection and quick options without creating notes or media.
local function test_reset_for_file_change()
    local uninitialized = note_exporter.new()
    h.assert_equals(uninitialized.reset_for_file_change(), uninitialized)
    local exporter, observer, options, state, jobs = make_file_change_test_context()
    h.assert_equals(observer.get_timing("start"), 20)
    h.assert_equals(options:get_lines(), 3)
    h.assert_equals(exporter.reset_for_file_change(), exporter)
    h.assert_equals(observer.get_selected_primary_text(), "")
    h.assert_equals(observer.has_recorded_dialogs(), false)
    h.assert_equals(observer.get_timing("start"), -1)
    h.assert_equals(observer.get_timing("end"), -1)
    h.assert_equals(observer.user_altered(), false)
    h.assert_equals(options:get_lines(), nil)
    h.assert_equals(options:get_cards(), 1)
    h.assert_equals(state.add_count, nil)
    h.assert_equals(state.append_count, nil)
    h.assert_equals(#jobs, 0)
end

--- Run exporter tests.
local function run_tests()
    test_update_notes_after_media_created()
    test_blank_subtitle_update()
    test_invalid_subtitle_does_not_start_update()
    test_lookup_warnings()
    test_lookup_dispatch()
    test_export_to_anki()
    test_export_without_media_directory()
    test_export_without_first_field()
    test_export_populates_first_field()
    test_export_media_failures()
    test_export_skipped_media()
    test_export_captures_request()
    test_export_captures_destination()
    test_update_transactions_capture_profile()
    test_update_transactions_isolate_media_directories()
    test_confirmation_captures_profile_and_metadata()
    test_reset_for_file_change()
    test_mismatched_update_requires_confirmation()
    test_cancelled_update_preserves_selection()
    test_empty_current_subtitle_requires_confirmation()
    test_accepted_update_reuses_target_snapshot()
    test_update_last_note_with_matching_sentences()
    test_update_last_note_with_mismatched_sentences()
    test_update_last_note_with_unverifiable_field()
    test_update_last_note_aborts_on_field_error()
    test_cancel_pending_update_cancels_confirmation()
    test_file_change_cancels_and_clears()
    test_blocked_updates_cancel_confirmation()
    test_mismatched_selected_note_update()
end

return {
    run_tests = run_tests,
}
