--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Prepare and perform one Anki note update request.
]]

local mp = require('mp')
local h = require('helpers')
local dec_counter = require('utils.dec_counter')

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
local function make_substitute_fmt(cfg_mgr)
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
        local time_pos = h.human_readable_time(mp.get_property_number('time-pos'))
        return tag:gsub("%%t", time_pos)
    end

    --- Replace the environment-tag placeholder in a tag.
    local function substitute_envvar(tag)
        local env_tags = os.getenv('SUBS2SRS_TAGS') or ''
        return tag:gsub("%%e", env_tags)
    end

    --- Replace the full-path placeholder in a tag.
    local function substitute_fullpath(tag)
        local full_path = mp.get_property("path") or ''
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
            local filename, episode_num = tag_format(mp.get_property("filename"))
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
    local self = {
        ankiconnect = components.ankiconnect,
        quick_creation_opts = components.quick_creation_opts,
        subs_observer = components.subs_observer,
        encoder = components.encoder,
        forvo = components.forvo,
        cfg_mgr = components.cfg_mgr,
        notify = components.notify or h.notify,
        substitute_fmt = make_substitute_fmt(components.cfg_mgr)
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
        local field_data = self.ankiconnect.get_note_fields(note_id)[first_field]
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

    --- Write generated fields after media creation completes.
    local function change_fields(request, new_data)
        --- Run this callback once audio and image files are created.
        local change_notes_countdown = dec_counter.new(#request.note_ids).on_finish(
                h.as_callback(notify_user_on_finish, request.note_ids)
        )
        for _, note_id in pairs(request.note_ids) do
            self.ankiconnect.append_media(
                    note_id,
                    pub.make_new_note_data(
                            self.ankiconnect.get_note_fields(note_id),
                            h.deep_copy(new_data),
                            { overwrite = request.overwrite }
                    ),
                    self.substitute_fmt(config().note_tag),
                    change_notes_countdown.decrease
            )
        end
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
        local video_duration = mp.get_property_number('duration')
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
    return {
        sentence_field = "SentKanji",
        secondary_field = "SentEng",
        audio_field = "SentAudio",
        audio_template = "[sound:%s]",
        image_field = "Image",
        image_template = '<img alt="snapshot" src="%s">',
        miscinfo_field = 'Notes',
        append_media = append_media,
        miscinfo_enable = false,
        audio_padding = 0,
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
        forvo = {
            --- Preserve generated fields in field-merge tests.
            append = function(new_data)
                return new_data
            end,
        },
        cfg_mgr = {
            --- Return the fixed field-merge test configuration.
            config = function()
                return make_update_test_config(true)
            end,
        },
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

--- Create a deferred media job that records its completion callback.
local function make_update_test_pending_media_job(filename, jobs)
    local job = { filename = filename, run_async = h.noop }
    --- Register the media-job completion callback.
    function job.on_finish(callback)
        job.callback = callback
        return job
    end
    table.insert(jobs, job)
    return job
end

--- Create an encoder test double that records media jobs.
local function make_update_test_encoder(jobs)
    return {
        set_output_dir = h.noop,
        snapshot = {
            --- Create a deferred snapshot job.
            create_job = function()
                return make_update_test_pending_media_job('snapshot.avif', jobs)
            end,
        },
        audio = {
            --- Create a deferred audio job.
            create_job = function()
                return make_update_test_pending_media_job('audio.ogg', jobs)
            end,
        },
    }
end

--- Create a subtitle observer test double for context updates.
local function make_update_test_observer(result, subtitle)
    return {
        --- Return the configured current subtitle.
        collect_from_current = function()
            result.current_collections = result.current_collections + 1
            return subtitle
        end,
        --- Record requested subtitle lines and return the fixture.
        collect_from_all_dialogues = function(lines)
            result.collected_lines = lines
            return subtitle
        end,
        --- Preserve subtitle text during test export preparation.
        clipboard_prepare = function(text)
            return text
        end,
        --- Record clearing the subtitle selection.
        clear = function()
            result.clear_count = result.clear_count + 1
        end,
        --- Report that test timings were not manually altered.
        user_altered = function()
            return false
        end,
    }
end

--- Create an AnkiConnect test double for context updates.
local function make_update_test_ankiconnect(result)
    return {
        --- Return the test media directory.
        get_media_dir_path = function()
            return '/tmp'
        end,
        --- Return stored fields for the supplied note.
        get_note_fields = function(note_id)
            return { SentKanji = 'stored ' .. tostring(note_id) }
        end,
        --- Return the first field used in notifications.
        get_first_field = function()
            return 'SentKanji'
        end,
        --- Record fields and immediately complete the simulated write.
        append_media = function(note_id, fields, _, on_finish)
            table.insert(result.appended_note_ids, note_id)
            result.fields_by_note[note_id] = fields
            on_finish()
        end,
        --- Record the Anki Browser query.
        gui_browse = function(query)
            result.browse_query = query
        end,
    }
end

--- Create quick-creation options for update-flow tests.
local function make_update_test_quick_creation_opts(n_lines)
    return {
        --- Return the configured quick-creation line count.
        get_lines = function()
            return n_lines
        end,
        clear_options = h.noop,
    }
end

--- Create a Forvo test double that preserves generated fields.
local function make_update_test_forvo()
    return {
        set_output_dir = h.noop,
        --- Preserve generated fields without pronunciation media.
        append = function(new_data)
            return new_data
        end,
    }
end

--- Create a configuration manager for update-flow tests.
local function make_update_test_config_manager(test_config)
    return {
        --- Return the supplied or default update-test configuration.
        config = function()
            return test_config or make_update_test_config(true)
        end,
    }
end

--- Create a notification callback that records its message.
local function make_update_test_notifier(result)
    --- Record the update notification.
    return function(message)
        result.notification = message
    end
end

--- Create a context and subtitle fixture for update-flow tests.
local function make_update_test_context(result, jobs, n_lines, test_config)
    local subtitle = { text = 'new sentence', secondary = '' }
    result.fields_by_note = {}
    return make_note_update_context {
        ankiconnect = make_update_test_ankiconnect(result),
        quick_creation_opts = make_update_test_quick_creation_opts(n_lines),
        subs_observer = make_update_test_observer(result, subtitle),
        encoder = make_update_test_encoder(jobs),
        forvo = make_update_test_forvo(),
        cfg_mgr = make_update_test_config_manager(test_config),
        notify = make_update_test_notifier(result),
    }, subtitle
end

--- Test both configured media merge orders.
local function test_update_media_merge()
    for _, scenario in ipairs {
        { append_media = true, expected = 'stored 13<br>new sentence' },
        { append_media = false, expected = 'new sentence<br>stored 13' },
    } do
        local result = { current_collections = 0, clear_count = 0, appended_note_ids = {} }
        local jobs = {}
        local context, subtitle = make_update_test_context(result, jobs, nil, make_update_test_config(scenario.append_media))
        context.perform_update({ note_ids = { 13 }, overwrite = false, subtitle = subtitle })
        jobs[1].callback()
        jobs[2].callback()
        h.assert_equals(result.fields_by_note[13].SentKanji, scenario.expected)
    end
end

--- Test collection from current and configured multi-line subtitles.
local function test_collect_subtitle()
    local current_result = { current_collections = 0, clear_count = 0, appended_note_ids = {} }
    local current_context, current_subtitle = make_update_test_context(current_result, {}, nil)
    h.assert_equals(current_context.collect_subtitle(), current_subtitle)
    h.assert_equals(current_result.current_collections, 1)

    local multi_result = { current_collections = 0, clear_count = 0, appended_note_ids = {} }
    local multi_context, multi_subtitle = make_update_test_context(multi_result, {}, 3)
    h.assert_equals(multi_context.collect_subtitle(), multi_subtitle)
    h.assert_equals(multi_result.collected_lines, 3)
end

--- Test media completion writes each note and notifies the user.
local function test_update_completion()
    local result = { current_collections = 0, clear_count = 0, appended_note_ids = {} }
    local jobs = {}
    local context, subtitle = make_update_test_context(result, jobs, nil)
    context.perform_update({ note_ids = { 11, 12 }, overwrite = true, subtitle = subtitle })
    h.assert_equals(#jobs, 2)
    jobs[1].callback()
    h.assert_equals(result.appended_note_ids, {})
    jobs[2].callback()
    h.assert_equals(result.appended_note_ids, { 11, 12 })
    h.assert_equals(result.browse_query, 'nid:11 OR nid:12')
    h.assert_equals(result.notification, 'Updated 2 notes.')
    h.assert_equals(result.clear_count, 1)
end

--- Run context tests without requiring mpv-backed components.
local function run_tests(context)
    context = context or make_field_merge_test_context()
    test_join_field_content()
    test_collect_subtitle()
    test_update_completion()
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
