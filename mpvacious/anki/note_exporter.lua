--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html
]]

local mp = require('mp')
local h = require('helpers')
local dec_counter = require('utils.dec_counter')



local function make_exporter()
    local self = {}
    local pub = {}

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
                    field_data = h.str_limit(field_data, max_len)
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



    function pub.join_fields(new_data, stored_data)
        fail_if_not_ready()
        for _, field in pairs { self.config.audio_field, self.config.image_field, self.config.miscinfo_field } do
            if not h.is_empty(field) then
                new_data[field] = join_field_content(h.table_get(new_data, field, ""), h.table_get(stored_data, field, ""))
            end
        end

        for _, field in pairs { self.config.sentence_field, self.config.secondary_field } do
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
                if self.config.append_media then
                    new_data = pub.join_fields(new_data, stored_data)
                else
                    new_data = pub.join_fields(stored_data, new_data)
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
                    pub.make_new_note_data(self.ankiconnect.get_note_fields(note_id), h.deep_copy(new_data), { overwrite = overwrite }),
                    substitute_fmt(self.config.note_tag),
                    change_notes_countdown.decrease
            )
        end
    end

    function pub.update_notes(note_ids, overwrite)
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
        return pub
    end

    function pub.maybe_reload_config()
        if self.config.reload_config_before_card_creation then
            self.cfg_mgr.reload_from_disk()
        end
        return pub
    end

    function pub.export_to_anki(gui)
        pub.maybe_reload_config()
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
        return pub
    end

    function pub.update_last_note(overwrite)
        local accept_notes_made_within_last_minutes = 10
        pub.maybe_reload_config()

        local n_cards = self.quick_creation_opts:get_cards()
        -- this now returns a table
        local last_note_ids = self.ankiconnect.get_last_note_ids(n_cards)
        n_cards = #last_note_ids

        --first element is the earliest
        if h.is_empty(last_note_ids) or last_note_ids[1] < h.minutes_ago(accept_notes_made_within_last_minutes) then
            return h.notify("Couldn't find the target note.", "warn", 2)
        end

        pub.update_notes(last_note_ids, overwrite)
        return pub
    end

    function pub.update_selected_note(overwrite)
        pub.maybe_reload_config()

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

        pub.update_notes(selected_note_ids, overwrite)
        return pub
    end

    function pub.init(ankiconnect, quick_creation_opts, subs_observer, encoder, forvo, cfg_mgr)
        cfg_mgr.fail_if_not_ready()
        self.config = cfg_mgr.config()
        self.cfg_mgr = cfg_mgr
        self.ankiconnect = ankiconnect
        self.quick_creation_opts = quick_creation_opts
        self.subs_observer = subs_observer
        self.encoder = encoder
        self.forvo = forvo
        return pub
    end

    return pub
end

local function test_join_fields(test_exporter)
    -- Test join_fields
    local new_note = {
        SentKanji = "それは…分からんよ",
        SentAudio = "[sound:s01e13_02m25s010ms_02m27s640ms.ogg]",
        SentEng = "Well...",
        Image = '<img alt="snapshot" src="s01e13_02m25s561ms.avif">'
    }
    local old_note = {
        SentAudio = "[sound:s01e13_02m21s340ms_02m24s140ms.ogg]",
        Image = '<img alt="snapshot" src="s01e13_02m22s225ms.avif">',
        VocabAudio = "",
        Notes = "",
        VocabDef = "",
        SentKanji = "勝ちって何に？",
        SentEng = "What would we win, exactly?",
    }
    local expected = {
        SentKanji = "勝ちって何に？<br>それは…分からんよ",
        SentAudio = "[sound:s01e13_02m21s340ms_02m24s140ms.ogg]<br>[sound:s01e13_02m25s010ms_02m27s640ms.ogg]",
        SentEng = "What would we win, exactly?<br>Well...",
        Image = '<img alt="snapshot" src="s01e13_02m22s225ms.avif"><br><img alt="snapshot" src="s01e13_02m25s561ms.avif">',
        Notes = "",
    }
    h.assert_equals(test_exporter.join_fields(new_note, old_note), expected)
end

local function test_html_escaping(test_exporter)
    -- HTML escaping
    local old_note = {
        SentKanji = "Well, that's the knighthood in the bag.",
    }
    local new_note = {
        SentKanji = "Well, that&apos;s the knighthood in the bag.",
    }
    h.assert_equals(test_exporter.join_fields(new_note, old_note).SentKanji, old_note.SentKanji)
    local new_note = {
        SentKanji = "Well, that&#39;s the knighthood in the bag.",
    }
    h.assert_equals(test_exporter.join_fields(new_note, old_note).SentKanji, old_note.SentKanji)
end

local function test_join_fields_duplicates(test_exporter)
    -- Equivalent subtitle punctuation must not duplicate a dictionary sentence.
    local old_note = {
        SentKanji = "女の子の <b>女性</b>の　『お』から始まる…",
    }
    local new_note = {
        SentKanji = "女の子の <b>女性</b>の “お”から始まる…",
    }
    h.assert_equals(test_exporter.join_fields(new_note, old_note).SentKanji, old_note.SentKanji)
    for _, equivalent in ipairs {
        "女の子の <b>女性</b>の\194\160〝お〟から始まる…\226\128\139",
        "\239\187\191女の子の <b>女性</b>の\226\128\175＂お＂から始まる…",
    } do
        new_note.SentKanji = equivalent
        h.assert_equals(test_exporter.join_fields(new_note, old_note).SentKanji, old_note.SentKanji)
    end

    -- Distinct punctuation must still be appended, not treated as duplicates.
    old_note = { SentKanji = "それは…分からんよ" }
    new_note = { SentKanji = "それは！分からんよ" }
    h.assert_equals(test_exporter.join_fields(new_note, old_note).SentKanji, "それは…分からんよ<br>それは！分からんよ")

    -- Quote variants normalize, but differing surrounding text must still be appended.
    old_note = { SentKanji = "『お』から始まる" }
    new_note = { SentKanji = "“お”から終わる" }
    h.assert_equals(test_exporter.join_fields(new_note, old_note).SentKanji, "『お』から始まる<br>“お”から終わる")

end

local function test_make_new_note_data(test_exporter)
    -- Test make_new_note_data
    local old_note = {
        SentKanji = "ヤツらの声に<b>現実味</b>が…",
    }
    local new_note = {
        SentKanji = "あの遠さはヤツらの声に現実味が…",
    }
    local expected = {
        SentKanji = "あの遠さはヤツらの声に<b>現実味</b>が…",
    }
    h.assert_equals(test_exporter.make_new_note_data(old_note, new_note, { overwrite = false, disable_forvo = true }).SentKanji, expected.SentKanji)
end

local function valid_update_subtitle()
    return {
        text = "new sentence",
        secondary = "",
        is_valid = function()
            return true
        end,
    }
end

local function make_pending_media_job(filename, jobs)
    local job = { filename = filename, run_async = h.noop }
    function job.on_finish(callback)
        job.callback = callback
        return job
    end
    table.insert(jobs, job)
    return job
end

local function make_media_job_factory(filename, jobs)
    return function()
        return make_pending_media_job(filename, jobs)
    end
end

local function make_update_test_encoder(jobs)
    return {
        set_output_dir = h.noop,
        snapshot = { create_job = make_media_job_factory("snapshot.avif", jobs) },
        audio = { create_job = make_media_job_factory("audio.ogg", jobs) },
    }
end

local UPDATE_TEST_CONFIG = {
    sentence_field = "SentKanji",
    audio_field = "SentAudio",
    audio_template = "[sound:%s]",
    image_field = "Image",
    image_template = '<img alt="snapshot" src="%s">',
    audio_padding = 0,
    miscinfo_enable = false,
}

local function make_update_test_exporter(result, jobs)
    local function append_media(note_id, fields)
        result.append_count = result.append_count + 1
        result.note_id = note_id
        result.fields = fields
    end
    local ankiconnect = {
        get_media_dir_path = function()
            return "/tmp"
        end,
        get_note_fields = function()
            return { SentKanji = "old sentence" }
        end,
        append_media = append_media,
    }
    local quick_options = {
        get_lines = h.noop,
        clear_options = h.noop
    }
    local observer = {
        collect_from_current = valid_update_subtitle,
        clipboard_prepare = function(text)
            return text
        end,
        clear = h.noop,
    }
    local forvo = {
        set_output_dir = h.noop,
        append = function(new_data)
            return new_data
        end
    }
    local config_manager = {
        fail_if_not_ready = h.noop,
        config = function()
            return UPDATE_TEST_CONFIG
        end
    }
    return make_exporter().init(
            ankiconnect,
            quick_options,
            observer,
            make_update_test_encoder(jobs),
            forvo,
            config_manager
    )
end

local function test_update_notes_after_media_created()
    local result = { append_count = 0 }
    local jobs = {}
    make_update_test_exporter(result, jobs).update_notes({ 1 }, true)
    h.assert_equals(#jobs, 2)
    jobs[1].callback()
    h.assert_equals(result.append_count, 0)
    jobs[2].callback()
    h.assert_equals(result.append_count, 1)
    h.assert_equals(result.note_id, 1)
    h.assert_equals(result.fields.SentKanji, "new sentence")
    h.assert_equals(result.fields.SentAudio, "[sound:audio.ogg]")
    h.assert_equals(result.fields.Image, '<img alt="snapshot" src="snapshot.avif">')
end

local function make_test_exporter()
    local test_cfg_mgr = {
        fail_if_not_ready = h.noop,
        config = function()
            return {
                sentence_field = "SentKanji",
                secondary_field = "SentEng",
                audio_field = "SentAudio",
                image_field = "Image",
                miscinfo_field = "Notes",
                append_media = true,
            }
        end,
    }
    return make_exporter().init(
            nil, -- ankiconnect
            nil, -- quick_creation_opts
            nil, -- subs_observer
            nil, -- encoder
            nil, -- forvo
            test_cfg_mgr
    )
end

local function test_join_field_content()
    h.assert_equals(join_field_content("ヤツらの声に現実味が…", "あの遠さはヤツらの声に現実味が…"), "あの遠さはヤツらの声に現実味が…")
    h.assert_equals(join_field_content("あの遠さはヤツらの声に現実味が…", "ヤツらの声に現実味が…"), "あの遠さはヤツらの声に現実味が…")
end

local function run_tests(test_exporter)
    test_exporter = test_exporter or make_test_exporter()
    test_join_field_content()
    test_join_fields(test_exporter)
    test_html_escaping(test_exporter)
    test_join_fields_duplicates(test_exporter)
    test_make_new_note_data(test_exporter)
    test_update_notes_after_media_created()
end

return {
    new = make_exporter,
    run_tests = run_tests,
}
