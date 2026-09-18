--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Prepare and perform one Anki note update request.
]]

local mp = require('mp')
local h = require('helpers')
local dec_counter = require('utils.dec_counter')


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
