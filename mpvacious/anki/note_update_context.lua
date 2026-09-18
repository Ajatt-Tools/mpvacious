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

    ------------------------------------------------------------
    --- Public

    return pub
end

------------------------------------------------------------
--- Tests: executed by both standalone and mpv-backed runners.

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
