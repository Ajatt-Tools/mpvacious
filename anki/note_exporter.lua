--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html
]]

local mp = require('mp')
local h = require('helpers')
local dec_counter = require('utils.dec_counter')

local function make_exporter()
    local self = {}

    local substitute_fmt = (function()
        local function substitute_filename(tag, filename)
            return tag:gsub("%%n", filename)
        end

        local function substitute_episode_number(tag, episode)
            return tag:gsub("%%d", episode)
        end

        local function substitute_time_pos(tag)
            local time_pos = h.human_readable_time(mp.get_property_number('time-pos'))
            return tag:gsub("%%t", time_pos)
        end

        local function substitute_envvar(tag)
            local env_tags = os.getenv('SUBS2SRS_TAGS') or ''
            return tag:gsub("%%e", env_tags)
        end

        local function substitute_fullpath(tag)
            local full_path = mp.get_property("path") or ''
            return tag:gsub("%%f", full_path)
        end

        local function tag_format(filename)
            filename = h.remove_extension(filename)
            filename = h.remove_common_resolutions(filename)

            local s, e, episode_num = h.get_episode_number(filename)

            if self.config.tag_del_episode_num == true and not h.is_empty(s) then
                if self.config.tag_del_after_episode_num == true then
                    -- Removing everything (e.g. episode name) after the episode number including itself.
                    filename = filename:sub(1, s)
                else
                    -- Removing the first found instance of the episode number.
                    filename = filename:sub(1, s) .. filename:sub(e + 1, -1)
                end
            end

            if self.config.tag_nuke_brackets == true then
                filename = h.remove_text_in_brackets(filename)
            end
            if self.config.tag_nuke_parentheses == true then
                filename = h.remove_filename_text_in_parentheses(filename)
            end

            if self.config.tag_filename_lowercase == true then
                filename = filename:lower()
            end

            filename = h.remove_leading_trailing_spaces(filename)
            filename = filename:gsub(" ", "_")
            filename = filename:gsub("_%-_", "_") -- Replaces garbage _-_ substrings with a underscore
            filename = h.remove_leading_trailing_dashes(filename)
            return filename, episode_num or ''
        end

        return function(tag)
            if not h.is_empty(tag) then
                local filename, episode = tag_format(mp.get_property("filename"))
                tag = substitute_filename(tag, filename)
                tag = substitute_episode_number(tag, episode)
                tag = substitute_time_pos(tag)
                tag = substitute_envvar(tag)
                tag = substitute_fullpath(tag)
                tag = h.remove_leading_trailing_spaces(tag)
            end
            return tag
        end
    end)()

    local function audio_padding()
        local video_duration = mp.get_property_number('duration')
        if self.config.audio_padding == 0.0 or not video_duration then
            return 0.0
        end
        if self.subs_observer.user_altered() then
            return 0.0
        end
        return self.config.audio_padding
    end

    local function prepare_for_exporting(sub_text)
        if not h.is_empty(sub_text) then
            sub_text = self.subs_observer.clipboard_prepare(sub_text)
            sub_text = h.escape_special_characters(sub_text)
        end
        return sub_text
    end

    local function construct_note_fields(sub_text, secondary_text, snapshot_filename, audio_filename)
        local ret = {
            [self.config.sentence_field] = prepare_for_exporting(sub_text),
        }
        if not h.is_empty(self.config.secondary_field) then
            ret[self.config.secondary_field] = prepare_for_exporting(secondary_text)
        end
        if not h.is_empty(self.config.image_field) and not h.is_empty(snapshot_filename) then
            ret[self.config.image_field] = string.format(self.config.image_template, snapshot_filename)
        end
        if not h.is_empty(self.config.audio_field) and not h.is_empty(audio_filename) then
            ret[self.config.audio_field] = string.format(self.config.audio_template, audio_filename)
        end
        if self.config.miscinfo_enable == true then
            ret[self.config.miscinfo_field] = substitute_fmt(self.config.miscinfo_format)
        end
        return ret
    end

    local function notify_user_on_finish(note_ids)
        --- Run this callback once all notes are changed.

        -- Construct a search query for the Anki Browser.
        local queries = {}
        for _, note_id in ipairs(note_ids) do
            table.insert(queries, string.format("nid:%s", tostring(note_id)))
        end
        local query = table.concat(queries, " OR ")
        self.ankiconnect.gui_browse(query)

        local first_field = self.ankiconnect.get_first_field(self.config.model_name)

        -- Notify the user.
        if #note_ids > 1 then
            h.notify(string.format("Updated %i notes.", #note_ids))
        else
            local field_data = self.ankiconnect.get_note_fields(note_ids[1])[first_field]
            if not h.is_empty(field_data) then
                local max_len = 20
                if string.len(field_data) > max_len then
                    field_data = field_data:sub(1, max_len) .. "…"
                end
                h.notify(string.format("Updated note: %s.", field_data))
            else
                h.notify(string.format("Updated note #%s.", tostring(note_ids[1])))
            end
        end
    end

    local function update_sentence(new_data, stored_data)
        -- adds support for TSCs
        -- https://tatsumoto-ren.github.io/blog/discussing-various-card-templates.html#targeted-sentence-cards
        -- if the target word was marked by Rikaitan, this function makes sure that the highlighting doesn't get erased.

        if h.is_empty(stored_data[self.config.sentence_field]) then
            -- sentence field is empty. can't continue.
            return new_data
        elseif h.is_empty(new_data[self.config.sentence_field]) then
            -- *new* sentence field is empty, but old one contains data. don't delete the existing sentence.
            new_data[self.config.sentence_field] = stored_data[self.config.sentence_field]
            return new_data
        end

        local _, opentag, target, closetag, _ = stored_data[self.config.sentence_field]:match('^(.-)(<[^>]+>)(.-)(</[^>]+>)(.-)$')
        if target then
            local prefix, _, suffix = new_data[self.config.sentence_field]:match(table.concat { '^(.-)(', target, ')(.-)$' })
            if prefix and suffix then
                new_data[self.config.sentence_field] = table.concat { prefix, opentag, target, closetag, suffix }
            end
        end
        return new_data
    end

    local function join_field_content(new_text, old_text, separator)
        -- By default, join fields with a HTML newline.
        separator = separator or "<br>"

        if h.is_empty(old_text) then
            -- If 'old_text' is empty, there's no need to join content with the separator.
            return new_text
        end

        if h.is_substr(old_text, new_text) then
            -- If 'old_text' (field) already contains new_text (sentence, image, audio, etc.),
            -- there's no need to add 'new_text' to 'old_text'.
            return old_text
        end

        return string.format("%s%s%s", old_text, separator, new_text)
    end

    local function fail_if_not_ready()
        if h.is_empty(self.config) then
            error("config not assigned")
        end
    end

    local function join_fields(new_data, stored_data)
        fail_if_not_ready()
        for _, field in pairs { self.config.audio_field, self.config.image_field, self.config.miscinfo_field, self.config.sentence_field, self.config.secondary_field } do
            if not h.is_empty(field) then
                new_data[field] = join_field_content(h.table_get(new_data, field, ""), h.table_get(stored_data, field, ""))
            end
        end
        return new_data
    end

    local function make_new_note_data(stored_data, new_data, overwrite)
        if stored_data then
            new_data = self.forvo.append(new_data, stored_data)
            new_data = update_sentence(new_data, stored_data)
            if not overwrite then
                if self.config.append_media then
                    new_data = join_fields(new_data, stored_data)
                else
                    new_data = join_fields(stored_data, new_data)
                end
            end
        end
        -- If the text is still empty, put some dummy text to let the user know why
        -- there's no text in the sentence field.
        if h.is_empty(new_data[self.config.sentence_field]) then
            new_data[self.config.sentence_field] = string.format("mpvacious wasn't able to grab subtitles (%s)", os.time())
        end
        return new_data
    end

    local function change_fields(note_ids, new_data, overwrite)
        --- Run this callback once audio and image files are created.
        local change_notes_countdown = dec_counter.new(#note_ids).on_finish(h.as_callback(notify_user_on_finish, note_ids))
        for _, note_id in pairs(note_ids) do
            self.ankiconnect.append_media(
                    note_id,
                    make_new_note_data(self.ankiconnect.get_note_fields(note_id), h.deep_copy(new_data), overwrite),
                    substitute_fmt(self.config.note_tag),
                    change_notes_countdown.decrease
            )
        end
    end

    local function update_notes(note_ids, overwrite)
        local sub
        local n_lines = self.quick_creation_opts:get_lines()
        if n_lines then
            sub = self.subs_observer.collect_from_all_dialogues(n_lines)
        else
            sub = self.subs_observer.collect_from_current()
        end

        if not sub:is_valid() then
            return h.notify("Nothing to export. Have you set the timings?", "warn", 2)
        end

        if h.is_empty(sub['text']) then
            -- In this case, don't modify whatever existing text there is and just
            -- modify the other fields we can. The user might be trying to add
            -- audio to a card which they've manually transcribed (either the video
            -- has no subtitles or it has image subtitles).
            sub['text'] = nil
        end

        local anki_media_dir = self.ankiconnect.get_media_dir_path()
        self.encoder.set_output_dir(anki_media_dir)
        self.forvo.set_output_dir(anki_media_dir)

        local snapshot = self.encoder.snapshot.create_job(sub)
        local audio = self.encoder.audio.create_job(sub, audio_padding())
        local new_data = construct_note_fields(sub['text'], sub['secondary'], snapshot.filename, audio.filename)
        local create_files_countdown = dec_counter.new(2).on_finish(h.as_callback(change_fields, note_ids, new_data, overwrite))

        snapshot.on_finish(create_files_countdown.decrease).run_async()
        audio.on_finish(create_files_countdown.decrease).run_async()

        self.subs_observer.clear()
        self.quick_creation_opts:clear_options()
    end

    local function maybe_reload_config()
        if self.config.reload_config_before_card_creation then
            self.cfg_mgr.reload_from_disk()
        end
    end

    local function export_to_anki(gui)
        maybe_reload_config()
        local sub = self.subs_observer.collect_from_current()

        if not sub:is_valid() then
            return h.notify("Nothing to export.", "warn", 1)
        end

        if not gui and h.is_empty(sub['text']) then
            sub['text'] = string.format("mpvacious wasn't able to grab subtitles (%s)", os.time())
        end

        self.encoder.set_output_dir(self.ankiconnect.get_media_dir_path())
        local snapshot = self.encoder.snapshot.create_job(sub)
        local audio = self.encoder.audio.create_job(sub, audio_padding())

        snapshot.run_async()
        audio.run_async()

        local first_field = self.ankiconnect.get_first_field(self.config.model_name)
        local note_fields = construct_note_fields(sub['text'], sub['secondary'], snapshot.filename, audio.filename)

        if not h.is_empty(first_field) and h.is_empty(note_fields[first_field]) then
            note_fields[first_field] = "[empty]"
        end

        self.ankiconnect.add_note(note_fields, substitute_fmt(self.config.note_tag), gui)
        self.subs_observer.clear()
    end

    local function update_last_note(overwrite)
        local accept_notes_made_within_last_minutes = 10
        maybe_reload_config()

        local n_cards = self.quick_creation_opts:get_cards()
        -- this now returns a table
        local last_note_ids = self.ankiconnect.get_last_note_ids(n_cards)
        n_cards = #last_note_ids

        --first element is the earliest
        if h.is_empty(last_note_ids) or last_note_ids[1] < h.minutes_ago(accept_notes_made_within_last_minutes) then
            return h.notify("Couldn't find the target note.", "warn", 2)
        end

        update_notes(last_note_ids, overwrite)
    end

    local function update_selected_note(overwrite)
        maybe_reload_config()

        local selected_note_ids = self.ankiconnect.get_selected_note_ids()

        if h.is_empty(selected_note_ids) then
            return h.notify("Couldn't find the target note(s). Did you select the notes you want in Anki?", "warn", 3)
        end

        if #selected_note_ids > self.config.card_overwrite_safeguard then
            return h.notify(
                    string.format(
                            "More than %i notes selected\nnot recommended, but you can change the limit in your config",
                            self.config.card_overwrite_safeguard
                    ),
                    "warn",
                    4
            )
        end

        update_notes(selected_note_ids, overwrite)
    end

    local function init(ankiconnect, quick_creation_opts, subs_observer, encoder, forvo, cfg_mgr)
        cfg_mgr.fail_if_not_ready()
        self.config = cfg_mgr.config()
        self.cfg_mgr = cfg_mgr
        self.ankiconnect = ankiconnect
        self.quick_creation_opts = quick_creation_opts
        self.subs_observer = subs_observer
        self.encoder = encoder
        self.forvo = forvo
    end

    return {
        init = init,
        update_notes = update_notes,
        export_to_anki = export_to_anki,
        maybe_reload_config = maybe_reload_config,
        join_fields = join_fields,
        update_last_note = update_last_note,
        update_selected_note = update_selected_note,
    }
end

return {
    new = make_exporter
}
