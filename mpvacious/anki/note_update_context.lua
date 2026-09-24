--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Prepare and perform one Anki note update request.
]]

local mp = require('mp')
local h = require('helpers')
local dec_counter = require('utils.dec_counter')
local fixtures = require('test_fixtures')

--- Normalize two fields before joining them.
--- Instead of comparing fields literally, normalize them to match different representations.
local function normalize_field_content(new_text, old_text, cfg)
    -- lowercase
    new_text, old_text = new_text:lower(), old_text:lower()

    -- Avoid duplicate sentence/media content when equivalent HTML entities differ,
    -- e.g. "'" versus "&apos;".
    new_text, old_text = h.unescape_special_characters(new_text), h.unescape_special_characters(old_text)

    -- Primary and secondary subtitles are compared as normalized plain text.
    if cfg.plaintext_compare then
        return h.normalize_subtitle_text(new_text), h.normalize_subtitle_text(old_text)
    else
        return new_text, old_text
    end
end

--- Join field content unless one normalized value contains the other.
--- Expected cfg fields: str separator, bool plaintext_compare
local function join_field_content(new_text, old_text, cfg)
    cfg = cfg or {}

    -- By default, join fields with a HTML newline.
    cfg.separator = cfg.separator or "<br>"

    local cmp_new_text, cmp_old_text = normalize_field_content(new_text, old_text, cfg)

    if h.is_empty(cmp_old_text) then
        -- If 'old_text' is empty, there's no need to join content with the separator.
        return new_text
    end

    if h.is_substr(cmp_old_text, cmp_new_text) then
        -- If 'old_text' (field) already contains new_text (sentence, image, audio, etc.),
        -- there's no need to add 'new_text' to 'old_text'.
        return old_text
    end

    if h.is_substr(cmp_new_text, cmp_old_text) then
        -- If 'new_text' (field) already contains old_text (sentence, image, audio, etc.),
        -- there's no need to add 'new_text' to 'old_text'.
        return new_text
    end

    return string.format("%s%s%s", old_text, cfg.separator, new_text)
end

--- Create a formatter for media-tag substitutions.
local function make_substitute_fmt(cfg_mgr, mp_api)
    --- Return the active configuration.
    local function config()
        return cfg_mgr.config()
    end

    --- Replace the filename placeholder in a tag.
    local function substitute_filename(tag, filename)
        return tag:gsub("%%n", filename)
    end

    --- Replace the episode-number placeholder in a tag.
    local function substitute_episode_number(tag, episode)
        return tag:gsub("%%d", episode)
    end

    --- Replace the playback-time placeholder in a tag.
    local function substitute_time_pos(tag)
        local time_pos = h.human_readable_time(mp_api.get_property_number('time-pos'))
        return tag:gsub("%%t", time_pos)
    end

    --- Replace the environment-tag placeholder in a tag.
    local function substitute_envvar(tag)
        local env_tags = os.getenv('SUBS2SRS_TAGS') or ''
        return tag:gsub("%%e", env_tags)
    end

    --- Replace the full-path placeholder in a tag.
    local function substitute_fullpath(tag)
        local full_path = mp_api.get_property("path") or ''
        return tag:gsub("%%f", full_path)
    end

    --- Remove the configured episode-number portion from a filename.
    local function remove_episode_number(filename, start_index, end_index)
        if config().tag_del_episode_num == true and not h.is_empty(start_index) then
            if config().tag_del_after_episode_num == true then
                -- Removing everything (e.g. episode name) after the episode number including itself.
                return filename:sub(1, start_index)
            else
                -- Removing the first found instance of the episode number.
                return filename:sub(1, start_index) .. filename:sub(end_index + 1, -1)
            end
        end
        return filename
    end

    --- Apply configured cleanup rules to a tag filename.
    local function clean_tag_filename(filename)
        if config().tag_nuke_brackets == true then
            filename = h.remove_text_in_brackets(filename)
        end
        if config().tag_nuke_parentheses == true then
            filename = h.remove_filename_text_in_parentheses(filename)
        end

        if config().tag_filename_lowercase == true then
            filename = filename:lower()
        end

        filename = h.remove_leading_trailing_spaces(filename)
        filename = filename:gsub(" ", "_")
        filename = filename:gsub("_%-_", "_") -- Replaces garbage _-_ substrings with a underscore
        filename = h.remove_leading_trailing_dashes(filename)
        return filename
    end

    --- Format a filename and return its detected episode number.
    local function tag_format(filename)
        filename = h.remove_extension(filename)
        filename = h.remove_common_resolutions(filename)
        local start_index, end_index, episode_num = h.get_episode_number(filename)
        filename = remove_episode_number(filename, start_index, end_index)
        return clean_tag_filename(filename), episode_num or ''
    end

    --- Substitute all supported placeholders in a media tag.
    return function(tag)
        if not h.is_empty(tag) then
            local filename, episode_num = tag_format(mp_api.get_property("filename"))
            tag = substitute_filename(tag, filename)
            tag = substitute_episode_number(tag, episode_num)
            tag = substitute_time_pos(tag)
            tag = substitute_envvar(tag)
            tag = substitute_fullpath(tag)
            tag = h.remove_leading_trailing_spaces(tag)
        end
        return tag
    end
end

--- Create a context that prepares and applies Anki note updates.
local function make_note_update_context(components)
    local mp_api = components.mp or mp
    local self = {
        ankiconnect = components.ankiconnect,
        quick_creation_opts = components.quick_creation_opts,
        subs_observer = components.subs_observer,
        encoder = components.encoder,
        forvo = components.forvo,
        cfg_mgr = components.cfg_mgr,
        notify = components.notify or h.notify,
        substitute_fmt = make_substitute_fmt(components.cfg_mgr, mp_api)
    }
    local pub = {}

    ------------------------------------------------------------
    --- Private

    --- Return the current update configuration.
    local function config()
        return self.cfg_mgr.config()
    end

    --- Raise an error when no update configuration is available.
    local function fail_if_not_ready()
        if h.is_empty(config()) then
            error("config not assigned")
        end
    end

    --- Prepare subtitle text for an Anki field.
    local function prepare_for_exporting(sub_text)
        if not h.is_empty(sub_text) then
            sub_text = self.subs_observer.clipboard_prepare(sub_text)
            sub_text = h.escape_special_characters(sub_text)
        end
        return sub_text
    end

    --- Preserve targeted-sentence markup when the generated sentence contains its target.
    local function update_sentence(new_data, stored_data)
        -- adds support for TSCs
        -- https://tatsumoto-ren.github.io/blog/discussing-various-card-templates.html#targeted-sentence-cards
        -- if the target word was marked by Rikaitan, this function makes sure that the highlighting doesn't get erased.

        if h.is_empty(stored_data[config().sentence_field]) then
            -- sentence field is empty. can't continue.
            return new_data
        elseif h.is_empty(new_data[config().sentence_field]) then
            -- *new* sentence field is empty, but old one contains data. don't delete the existing sentence.
            new_data[config().sentence_field] = stored_data[config().sentence_field]
            return new_data
        end

        local _, opentag, target, closetag, _ = stored_data[config().sentence_field]:match('^(.-)(<[^>]+>)(.-)(</[^>]+>)(.-)$')
        if target then
            local prefix, _, suffix = new_data[config().sentence_field]:match(table.concat { '^(.-)(', target, ')(.-)$' })
            if prefix and suffix then
                new_data[config().sentence_field] = table.concat { prefix, opentag, target, closetag, suffix }
            end
        end
        return new_data
    end

    --- Build an Anki Browser query for the updated notes.
    local function make_browse_query(note_ids)
        -- Construct a search query for the Anki Browser.
        local queries = {}
        for _, note_id in ipairs(note_ids) do
            table.insert(queries, string.format("nid:%s", tostring(note_id)))
        end
        return table.concat(queries, " OR ")
    end

    --- Notify the user about one updated note.
    local function notify_single_updated_note(note_id)
        local first_field = self.ankiconnect.get_first_field(config().model_name)
        local note_fields, error = self.ankiconnect.get_note_fields(note_id)
        if error then
            -- The update succeeded. An unavailable notification preview must not hide that success.
            return self.notify(string.format("Updated note #%s.", tostring(note_id)))
        end
        local field_data = note_fields[first_field]
        if not h.is_empty(field_data) then
            local max_len = 20
            if string.len(field_data) > max_len then
                field_data = h.str_limit(field_data, max_len)
            end
            self.notify(string.format("Updated note: %s.", field_data))
        else
            self.notify(string.format("Updated note #%s.", tostring(note_id)))
        end
    end

    --- Notify the user after every requested note has been updated.
    local function notify_user_on_finish(note_ids)
        --- Run this callback once all notes are changed.
        self.ankiconnect.gui_browse(make_browse_query(note_ids))
        -- Notify the user.
        if #note_ids > 1 then
            self.notify(string.format("Updated %i notes.", #note_ids))
        else
            notify_single_updated_note(note_ids[1])
        end
    end

    --- Collect Anki write failures and notify only after every target completes.
    local function make_update_write_completion(note_ids)
        local errors = {}

        --- Report all completed writes without claiming success after any failure.
        local function on_finish()
            if #errors > 0 then
                self.notify("Failed to update notes: " .. table.concat(errors, "; "), 'error', 5)
            else
                notify_user_on_finish(note_ids)
            end
        end

        local countdown = dec_counter.new(#note_ids).on_finish(on_finish)
        --- Record the result for one note before counting its completion.
        return function(note_id)
            --- Record any AnkiConnect error with its corresponding note ID.
            return function(error)
                if error ~= nil then
                    table.insert(errors, string.format("note %s: %s", tostring(note_id), tostring(error)))
                end
                countdown.decrease()
            end
        end
    end

    --- Fetch all targets before any write; never return a partial snapshot on failure.
    local function collect_target_fields(note_ids)
        local fields_by_note_id, error = self.ankiconnect.get_notes_fields(note_ids)
        if error then
            return nil, error
        end
        local targets = {}
        for _, note_id in pairs(note_ids) do
            table.insert(targets, { note_id = note_id, fields = fields_by_note_id[note_id] })
        end
        return targets, nil
    end

    --- Start writes using completed target snapshots, without fetching their fields again.
    local function write_target_fields(request, new_data, targets)
        local completion_for = make_update_write_completion(request.note_ids)
        for _, target in pairs(targets) do
            self.ankiconnect.append_media(
                    target.note_id,
                    pub.make_new_note_data(
                            target.fields,
                            h.deep_copy(new_data),
                            { overwrite = request.overwrite }
                    ),
                    self.substitute_fmt(config().note_tag),
                    completion_for(target.note_id)
            )
        end
    end

    --- Write generated fields after media creation completes.
    local function change_fields(request, new_data)
        -- Run this callback once audio and image files are created.
        -- Read every target first: a later read failure must not leave earlier notes partly updated.
        local targets, error = collect_target_fields(request.note_ids)
        if error then
            return self.notify(error, 'error', 5)
        end
        write_target_fields(request, new_data, targets)
    end

    --- Configure output paths and create update media jobs.
    local function create_update_media(request)
        local anki_media_dir = self.ankiconnect.get_media_dir_path()
        self.encoder.set_output_dir(anki_media_dir)
        self.forvo.set_output_dir(anki_media_dir)
        local snapshot = self.encoder.snapshot.create_job(request.subtitle)
        local audio = self.encoder.audio.create_job(request.subtitle, pub.audio_padding())
        local new_data = pub.construct_note_fields {
            primary_text = request.subtitle['text'],
            secondary_text = request.subtitle['secondary'],
            snapshot_filename = snapshot.filename,
            audio_filename = audio.filename,
        }
        return {
            snapshot = snapshot,
            audio = audio,
            new_data = new_data,
        }
    end

    --- Start media jobs and schedule the resulting note write.
    local function start_update_media(request, future)
        local create_files_countdown = dec_counter.new(2).on_finish(
                h.as_callback(change_fields, request, future.new_data)
        )
        future.snapshot.on_finish(create_files_countdown.decrease).run_async()
        future.audio.on_finish(create_files_countdown.decrease).run_async()
    end

    --- Clear subtitle selection after an update starts.
    local function clear_update_state()
        self.subs_observer.clear()
        self.quick_creation_opts:clear_options()
    end

    ------------------------------------------------------------
    --- Public

    --- Join generated and stored fields according to current update configuration.
    function pub.join_fields(new_data, stored_data)
        fail_if_not_ready()
        for _, field in pairs { config().audio_field, config().image_field, config().miscinfo_field } do
            if not h.is_empty(field) then
                new_data[field] = join_field_content(h.table_get(new_data, field, ""), h.table_get(stored_data, field, ""))
            end
        end

        for _, field in pairs { config().sentence_field, config().secondary_field } do
            if not h.is_empty(field) then
                -- Strip html tags to compare text only.
                new_data[field] = join_field_content(h.table_get(new_data, field, ""), h.table_get(stored_data, field, ""), { plaintext_compare = true })
            end
        end

        return new_data
    end

    --- Merge generated note fields with stored fields according to update options.
    --- cfg.disable_forvo skips pronunciation media; cfg.overwrite replaces rather than appends.
    function pub.make_new_note_data(stored_data, new_data, cfg)
        cfg = cfg or {}

        if stored_data then
            if not cfg.disable_forvo then
                new_data = self.forvo.append(new_data, stored_data)
            end
            new_data = update_sentence(new_data, stored_data)
            if not cfg.overwrite then
                if config().append_media then
                    new_data = pub.join_fields(new_data, stored_data)
                else
                    new_data = pub.join_fields(stored_data, new_data)
                end
            end
        end
        -- If the text is still empty, put some dummy text to let the user know why
        -- there's no text in the sentence field.
        if h.is_empty(new_data[config().sentence_field]) then
            new_data[config().sentence_field] = string.format("mpvacious wasn't able to grab subtitles (%s)", os.time())
        end
        return new_data
    end

    --- Construct fields for ordinary new-note export.
    --- Construct generated note fields from subtitle text and media filenames.
    function pub.construct_note_fields(kwargs)
        local ret = {
            [config().sentence_field] = prepare_for_exporting(kwargs.primary_text),
        }
        if not h.is_empty(config().secondary_field) then
            ret[config().secondary_field] = prepare_for_exporting(kwargs.secondary_text)
        end
        if not h.is_empty(config().image_field) and not h.is_empty(kwargs.snapshot_filename) then
            ret[config().image_field] = string.format(config().image_template, kwargs.snapshot_filename)
        end
        if not h.is_empty(config().audio_field) and not h.is_empty(kwargs.audio_filename) then
            ret[config().audio_field] = string.format(config().audio_template, kwargs.audio_filename)
        end
        if config().miscinfo_enable then
            ret[config().miscinfo_field] = self.substitute_fmt(config().miscinfo_format)
        end
        return ret
    end

    --- Return audio padding for ordinary new-note export unless the user manually selected timings.
    function pub.audio_padding()
        local video_duration = mp_api.get_property_number('duration')
        if config().audio_padding == 0.0 or not video_duration then
            return 0.0
        end
        if self.subs_observer.user_altered() then
            return 0.0
        end
        return config().audio_padding
    end

    --- Apply media-tag substitutions using the current update configuration.
    function pub.substitute_fmt(tag)
        return self.substitute_fmt(tag)
    end

    --- Collect the current subtitle selection for one note update.
    function pub.collect_subtitle()
        local n_lines = self.quick_creation_opts:get_lines()
        if n_lines then
            return self.subs_observer.collect_from_all_dialogues(n_lines)
        else
            return self.subs_observer.collect_from_current()
        end
    end

    --- Start media creation and write note fields after both jobs finish.
    --- Create media and update fields for `request`,
    --- which contains the captured "subtitle", target "note_ids", and "overwrite" mode.
    function pub.perform_update(request)
        if h.is_empty(request.subtitle['text']) then
            -- In this case, don't modify whatever existing text there is and just
            -- modify the other fields we can. The user might be trying to add
            -- audio to a card which they've manually transcribed (either the video
            -- has no subtitles or it has image subtitles).
            request.subtitle['text'] = nil
        end
        start_update_media(request, create_update_media(request))
        clear_update_state()
        return pub
    end

    return pub
end

------------------------------------------------------------
--- Tests: executed by both standalone and mpv-backed runners.

--- Create an update configuration with the selected merge order.
local function make_update_test_config(append_media)
    return fixtures.make_update_config {
        secondary_field = "SentEng",
        miscinfo_field = 'Notes',
        append_media = append_media,
    }
end

--- Test nested sentence fields retain the more complete normalized value.
local function test_join_field_content()
    h.assert_equals(join_field_content("ヤツらの声に現実味が…", "あの遠さはヤツらの声に現実味が…"), "あの遠さはヤツらの声に現実味が…")
    h.assert_equals(join_field_content("あの遠さはヤツらの声に現実味が…", "ヤツらの声に現実味が…"), "あの遠さはヤツらの声に現実味が…")
    h.assert_equals(join_field_content('new', 'old'), 'old<br>new')
end

--- Create a context with concrete test components for field-merge tests.
local function make_field_merge_test_context()
    return make_note_update_context {
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
    return { SentKanji = 'stored ' .. tostring(note_id) }
end

--- Return fresh state shared by update-context test doubles.
local function make_update_test_result()
    return { current_collections = 0, clear_count = 0, appended_note_ids = {} }
end

--- Complete both media jobs with their real callback success values.
local function complete_update_test_media_jobs(jobs)
    jobs[1].callback(true)
    jobs[2].callback(true)
end

--- Create a context and subtitle fixture from named update-test options.
local function make_update_test_context(options)
    local result = options.result
    local subtitle = { text = 'new sentence', secondary = '' }
    result.fields_by_note = {}
    result.field_requests = {}
    result.preview_reads = {}
    return make_note_update_context {
        ankiconnect = fixtures.make_update_ankiconnect(result, make_context_test_stored_fields),
        quick_creation_opts = fixtures.make_quick_creation_options(result, { lines = options.lines }),
        subs_observer = fixtures.make_subtitle_observer(result, subtitle, { user_altered = options.user_altered }),
        encoder = fixtures.make_update_encoder(options.jobs),
        forvo = fixtures.make_forvo(),
        cfg_mgr = fixtures.make_config_manager(options.config or make_update_test_config(true)),
        notify = fixtures.make_notifier(result),
        mp = options.mp,
    }, subtitle
end

--- Test both configured media merge orders.
local function test_update_media_merge()
    for _, scenario in ipairs {
        { append_media = true, expected = 'stored 13<br>new sentence' },
        { append_media = false, expected = 'new sentence<br>stored 13' },
    } do
        local result = make_update_test_result()
        local jobs = {}
        local context, subtitle = make_update_test_context {
            result = result, jobs = jobs, config = make_update_test_config(scenario.append_media),
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

--- Test media completion writes each note and notifies the user.
local function test_update_completion()
    local result = make_update_test_result()
    local jobs = {}
    local context, subtitle = make_update_test_context { result = result, jobs = jobs }
    context.perform_update({ note_ids = { 11, 12 }, overwrite = true, subtitle = subtitle })
    h.assert_equals(#jobs, 2)
    jobs[1].callback(true)
    h.assert_equals(result.appended_note_ids, {})
    jobs[2].callback(true)
    h.assert_equals(result.appended_note_ids, { 11, 12 })
    h.assert_equals(result.browse_query, 'nid:11 OR nid:12')
    h.assert_equals(result.notification, 'Updated 2 notes.')
    h.assert_equals(result.clear_count, 1)
end

--- Verify delayed Anki write failures cannot trigger a success notification.
local function test_update_write_outcomes()
    local cases = {
        { errors = {}, notification = 'Updated 2 notes.', browse_query = 'nid:11 OR nid:12' },
        { errors = { [12] = 'denied' }, notification = 'Failed to update notes: note 12: denied' },
        { errors = { [12] = 'denied', [11] = 'busy' },
          notification = 'Failed to update notes: note 12: denied; note 11: busy' },
    }
    for _, case in ipairs(cases) do
        local result = make_update_test_result()
        result.write_callbacks = {}
        local jobs = {}
        local context, subtitle = make_update_test_context { result = result, jobs = jobs }
        context.perform_update({ note_ids = { 11, 12 }, overwrite = true, subtitle = subtitle })
        complete_update_test_media_jobs(jobs)
        h.assert_equals(result.notification, nil)
        result.write_callbacks[12](case.errors[12])
        h.assert_equals(result.notification, nil)
        result.write_callbacks[11](case.errors[11])
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
    h.assert_equals(result.browse_query, 'nid:11')
    h.assert_equals(result.notification, 'Updated note: stored 11.')
end

--- Assert one failed bulk field request prevents every write in the batch.
local function assert_update_test_field_failure(case)
    local result = make_update_test_result()
    local jobs = {}
    local context, subtitle = make_update_test_context { result = result, jobs = jobs }
    result.read_fields = function(note_ids)
        h.assert_equals(result.appended_note_ids, {})
        h.assert_equals(note_ids, { 11, 12 })
        return nil, 'read failed'
    end
    context.perform_update({ note_ids = { 11, 12 }, overwrite = case.overwrite, subtitle = subtitle })
    complete_update_test_media_jobs(jobs)
    h.assert_equals(result.appended_note_ids, {})
    h.assert_equals(result.fields_by_note, {})
    h.assert_equals(result.field_requests, { { 11, 12 } })
    h.assert_equals(result.browse_query, nil)
    h.assert_equals(result.notification_level, 'error')
    h.assert_equals(result.notification, 'read failed')
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
    result.read_fields = function(note_ids)
        h.assert_equals(result.appended_note_ids, {})
        h.assert_equals(note_ids, { 11, 12 })
        return {
            [11] = { SentKanji = 'stored 11' },
            [12] = { SentKanji = 'stored 12' },
        }, nil
    end
    context.perform_update({ note_ids = { 11, 12 }, overwrite = false, subtitle = subtitle })
    complete_update_test_media_jobs(jobs)
    h.assert_equals(result.field_requests, { { 11, 12 } })
    h.assert_equals(result.fields_by_note[11].SentKanji, 'stored 11<br>new sentence')
    h.assert_equals(result.fields_by_note[12].SentKanji, 'stored 12<br>new sentence')
    h.assert_equals(result.notification, 'Updated 2 notes.')
end

--- Test a failed notification-only preview read falls back to the updated note ID.
local function test_update_notification_field_read_failure()
    local result = make_update_test_result()
    local jobs = {}
    local context, subtitle = make_update_test_context { result = result, jobs = jobs }
    result.read_preview = function()
        return nil, 'preview unavailable'
    end
    context.perform_update({ note_ids = { 11 }, overwrite = true, subtitle = subtitle })
    complete_update_test_media_jobs(jobs)
    h.assert_equals(result.appended_note_ids, { 11 })
    h.assert_equals(result.field_requests, { { 11 } })
    h.assert_equals(result.preview_reads, { 11 })
    h.assert_equals(result.notification, 'Updated note #11.')
end

--- Test blank update subtitles preserve the stored sentence.
local function test_blank_update_subtitle()
    local result = make_update_test_result()
    local jobs = {}
    local context, subtitle = make_update_test_context { result = result, jobs = jobs }
    subtitle.text = ''
    context.perform_update({ note_ids = { 13 }, overwrite = false, subtitle = subtitle })
    complete_update_test_media_jobs(jobs)
    h.assert_equals(result.fields_by_note[13].SentKanji, 'stored 13')
end

--- Create the mp API for metadata and duration tests.
local function make_update_test_mp_api()
    return {
        --- Return the test media filename.
        get_property = function(name)
            if name == 'filename' then
                return 'episode.mkv'
            elseif name == 'path' then
                return '/videos/episode.mkv'
            end
        end,
        --- Return the test media duration.
        get_property_number = function(name)
            if name == 'duration' then
                return 1
            elseif name == 'time-pos' then
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
        result = result, jobs = {}, config = config, user_altered = true, mp = mp_api,
    }
    h.assert_equals(context.substitute_fmt('source_%n'), 'source_episode')
    h.assert_equals(context.substitute_fmt('%f %t'), '/videos/episode.mkv 01m05s000ms')
    h.assert_equals(context.audio_padding(), 0.5)
    h.assert_equals(altered_context.audio_padding(), 0.0)
end

--- Test tag substitution and audio padding for automatic and altered timings.
local function test_media_metadata()
    assert_update_test_media_metadata(make_update_test_mp_api())
end

--- Run context tests without requiring mpv-backed components.
local function run_tests(context)
    context = context or make_field_merge_test_context()
    test_join_field_content()
    test_collect_subtitle()
    test_update_completion()
    test_update_write_outcomes()
    test_single_note_update_completion()
    test_update_field_read_failures()
    test_update_preflight_field_reads()
    test_update_notification_field_read_failure()
    test_blank_update_subtitle()
    test_media_metadata()
    test_update_media_merge()
    test_join_fields(context)
    test_join_fields_duplicates(context)
    test_html_escaping(context)
    test_make_new_note_data(context)
end

return {
    new = make_note_update_context,
    run_tests = run_tests,
}
