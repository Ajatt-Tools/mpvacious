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

local TEST_CONFIG = {
    sentence_field = "SentKanji",
    secondary_field = "SentEng",
    audio_field = "SentAudio",
    audio_template = "[sound:%s]",
    image_field = "Image",
    image_template = '<img alt="snapshot" src="%s">',
    miscinfo_field = 'Notes',
    append_media = true,
    audio_padding = 0,
    miscinfo_enable = false,
}

--- Test nested sentence fields retain the more complete normalized value.
local function test_join_field_content()
    h.assert_equals(join_field_content("ヤツらの声に現実味が…", "あの遠さはヤツらの声に現実味が…"), "あの遠さはヤツらの声に現実味が…")
    h.assert_equals(join_field_content("あの遠さはヤツらの声に現実味が…", "ヤツらの声に現実味が…"), "あの遠さはヤツらの声に現実味が…")
    h.assert_equals(join_field_content('new', 'old'), 'old<br>new')
end

--- Run context tests without requiring mpv-backed components.
local function run_tests()
    local context = make_test_context()
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
