--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Observer waits for subtitles to appear on the screen and adds them to a list.
]]

local h = require('helpers')
local timings = require('utils.timings')
local sub_list = require('subtitles.sub_list')
local Subtitle = require('subtitles.subtitle')
local mp = require('mp')
local platform = require('platform.init')
local new_autoclip_method_selector = require('subtitles.autoclip_methods')
local custom_subtitle_filter = h.maybe_require('custom_subtitle_filter')

------------------------------------------------------------
--- Private

local function on_external_finish(success, result, error)
    if success ~= true or error ~= nil then
        h.notify("Command failed: " .. table.concat(result))
    end
end

local function external_command_args(cur_lines, autoclip_custom_args)
    local args = {}

    -- Append a trailing space to ensure the last argument is captured by the %s+ pattern.
    local config_str = autoclip_custom_args .. " "

    -- PATTERN EXPLANATION: [=[(["']?)(.-)%1%s+]=]
    -- 1. (["']?)  : Capture group 1. Matches an optional single or double quote.
    -- 2. (.-)     : Capture group 2. Non-greedy match of any character (the actual content).
    -- 3. %1       : Back-reference. Ensures the closing quote matches the opening quote.
    -- 4. %s+      : Matches one or more trailing whitespace characters to delimit arguments.
    local pattern = [=[(["']?)(.-)%1%s+]=]

    for _, arg in config_str:gmatch(pattern) do
        if arg ~= "" then
            if arg == '%MPV_PRIMARY%' then
                arg = cur_lines.primary
            elseif arg == '%MPV_SECONDARY%' then
                arg = cur_lines.secondary
            end

            table.insert(args, arg)
        end
    end

    return args
end

local function make_current_subtitle_lines(dependencies)
    local primary = dependencies.dialogs.get_text()

    if h.is_empty(primary) then
        primary = mp.get_property("sub-text")
    end

    if h.is_empty(primary) then
        return nil
    end

    local secondary = dependencies.secondary_dialogs.get_text()

    if h.is_empty(secondary) then
        secondary = mp.get_property("secondary-sub-text") or ""
    end

    return {
        get_prepared = function()
            return {
                primary = dependencies.clipboard_preparer(primary),
                secondary = secondary
            }
        end,
        raw = {
            primary = primary,
            secondary = secondary
        }
    }
end

------------------------------------------------------------
--- Custom subtitle filter method

local function apply_custom_subtitle_filter(text)
    if custom_subtitle_filter and custom_subtitle_filter.preprocess then
        return custom_subtitle_filter.preprocess(text)
    end
    return text
end

local function apply_custom_trim(text)
    if custom_subtitle_filter and custom_subtitle_filter.trim then
        return custom_subtitle_filter.trim(text)
    end
    return h.trim(text)
end

------------------------------------------------------------
--- Public

local function make_subtitles_observer()
    local public = {}
    local private = {}

    private.dialogs = sub_list.new()
    private.secondary_dialogs = sub_list.new()
    private.all_dialogs = sub_list.new()
    private.all_secondary_dialogs = sub_list.new()
    private.user_timings = timings.new()
    private.autoclip_method = new_autoclip_method_selector.new()
    private.append_dialogue = false
    private.autoclip_enabled = false

    ------------------------------------------------------------
    --- Register handlers

    private.autoclip_method.register_handler('clipboard', function(current_subtitle_lines)
        public.copy_to_clipboard("autocopy action", current_subtitle_lines.raw.primary)
    end)

    private.autoclip_method.register_handler('goldendict', function(current_subtitle_lines)
        h.subprocess_detached {
            args = { 'goldendict', current_subtitle_lines.get_prepared().primary },
            completion_fn = on_external_finish
        }
    end)

    private.autoclip_method.register_handler('custom_command', function(current_subtitle_lines)
        if not h.is_empty(private.config.autoclip_custom_args) then
            h.subprocess {
                args = external_command_args(current_subtitle_lines.get_prepared(), private.config.autoclip_custom_args),
                completion_fn = on_external_finish
            }
        end
    end)

    ------------------------------------------------------------
    --- Private methods

    local function append_primary_sub()
        local current_sub = Subtitle:now()
        private.all_dialogs.insert(current_sub)
        if private.append_dialogue and private.dialogs.insert(current_sub) then
            private.menu:update()
        end
    end

    local function append_secondary_sub()
        local current_secondary = Subtitle:now('secondary')
        private.all_secondary_dialogs.insert(current_secondary)
        if private.append_dialogue and private.secondary_dialogs.insert(Subtitle:now('secondary')) then
            private.menu:update()
        end
    end

    local function start_appending()
        private.append_dialogue = true
        append_primary_sub()
        append_secondary_sub()
    end

    local function handle_secondary_sub()
        append_secondary_sub()
    end

    local function copy_primary_sub()
        if private.autoclip_enabled then
            private.autoclip_method.call(make_current_subtitle_lines {
                dialogs = private.dialogs,
                secondary_dialogs = private.secondary_dialogs,
                clipboard_preparer = public.clipboard_prepare,
            })
        end
    end

    local function handle_primary_sub()
        append_primary_sub()
        copy_primary_sub()
    end

    local function notify_autocopy()
        if private.autoclip_enabled then
            copy_primary_sub()
        end
        h.notify(string.format("Autocopy has been %s.", public.autocopy_status_str()))
    end

    local function copy_subtitle(subtitle_id)
        -- subtitle_id = "secondary-sub-text" or "sub-text"
        public.copy_to_clipboard("copy-on-demand", mp.get_property(subtitle_id))
    end

    ------------------------------------------------------------
    --- Public methods

    function public.copy_to_clipboard(_, text)
        if platform.healthy == false then
            h.notify(platform.clip_util .. " is not installed.", "error", 5)
        end
        if not h.is_empty(text) then
            platform.copy_to_clipboard(public.clipboard_prepare(text))
        end
    end

    function public.clipboard_prepare(text)
        text = apply_custom_subtitle_filter(text)

        if private.config.clipboard_trim_enabled then
            text = apply_custom_trim(text)
        else
            text = h.remove_newlines(text)
        end

        text = public.maybe_remove_all_spaces(text)
        return text
    end

    function public.maybe_remove_all_spaces(str)
        if private.config.nuke_spaces == true and h.contains_non_latin_letters(str) then
            return h.remove_all_spaces(str)
        else
            return str
        end
    end

    function public.copy_current_primary_to_clipboard()
        copy_subtitle("sub-text")
    end

    function public.copy_current_secondary_to_clipboard()
        copy_subtitle("secondary-sub-text")
    end

    function public.user_altered()
        --- Return true if the user manually set at least start or end.
        return private.user_timings.is_set('start') or private.user_timings.is_set('end')
    end

    function public.get_timing(position)
        if private.user_timings.is_set(position) then
            return private.user_timings.get(position)
        elseif not private.dialogs.is_empty() then
            return private.dialogs.get_time(position)
        end
        return -1
    end

    function public.collect_from_all_dialogues(n_lines)
        local current_sub = Subtitle:now()
        local current_secondary_sub = Subtitle:now('secondary')
        private.all_dialogs.insert(current_sub)
        private.all_secondary_dialogs.insert(current_secondary_sub)
        if current_sub == nil then
            return Subtitle:new() -- return a default empty new Subtitle to let consumer handle
        end
        local combined = private.all_dialogs.collect_n_subs(current_sub, n_lines)
        local secondary_text = private.all_secondary_dialogs.get_overlapping_text(combined)
        return Subtitle:new {
            ['text'] = combined["text"],
            ['secondary'] = secondary_text,
            ['start'] = combined['start'],
            ['end'] = combined['end'],
        }
    end

    function public.collect_from_current()
        --- Return all recorded subtitle lines as one subtitle object.
        --- The caller has to call subs_observer.clear() afterwards.
        if private.dialogs.is_empty() then
            private.dialogs.insert(Subtitle:now())
        end
        if private.secondary_dialogs.is_empty() then
            private.secondary_dialogs.insert(Subtitle:now('secondary'))
        end
        local combined = Subtitle:from_text(private.dialogs.get_text(), public.get_timing('start'), public.get_timing('end'))
        return Subtitle:new {
            ['text'] = combined['text'],
            ['secondary'] = private.secondary_dialogs.get_overlapping_text(combined),
            ['start'] = combined['start'],
            ['end'] = combined['end'],
        }
    end

    function public.set_manual_timing(position)
        private.user_timings.set(position, mp.get_property_number('time-pos') - mp.get_property("audio-delay"))
        h.notify(h.capitalize_first_letter(position) .. " time has been set.")
        start_appending()
    end

    function public.set_manual_timing_to_sub(position)
        local sub = Subtitle:now()
        if sub then
            private.user_timings.set(position, sub[position] - mp.get_property("audio-delay"))
            h.notify(h.capitalize_first_letter(position) .. " time has been set.")
            start_appending()
        else
            h.notify("There's no visible subtitle.", "info", 2)
        end
    end

    function public.set_to_current_sub()
        public.clear()
        if Subtitle:now() then
            start_appending()
            h.notify("Timings have been set to the current sub.", "info", 2)
        else
            h.notify("There's no visible subtitle.", "info", 2)
        end
    end

    function public.clear()
        private.append_dialogue = false
        private.dialogs = sub_list.new()
        private.secondary_dialogs = sub_list.new()
        private.user_timings = timings.new()
    end

    function public.clear_all_dialogs()
        private.all_dialogs = sub_list.new()
        private.all_secondary_dialogs = sub_list.new()
    end

    function public.clear_and_notify()
        --- Clear then notify the user.
        --- Called by the OSD menu when the user presses a button to drop recorded subtitles.
        public.clear()
        h.notify("Timings have been reset.", "info", 2)
    end

    function public.is_appending()
        return private.append_dialogue
    end

    function public.all_subs_until_now()
        private.all_dialogs.insert(Subtitle:now())
        private.all_secondary_dialogs.insert(Subtitle:now('secondary'))
        return private.all_dialogs.get_subs_list(), private.all_secondary_dialogs.get_subs_list()
    end

    function public.recorded_subs()
        return private.dialogs.get_subs_list()
    end

    function public.get_selected_primary_text()
        return h.collapse_whitespace(private.dialogs.get_text())
    end

    function public.recorded_secondary_subs()
        return private.secondary_dialogs.get_subs_list()
    end

    function public.autocopy_is_enabled_str()
        return private.autoclip_enabled and 'enabled' or 'disabled'
    end

    function public.autocopy_current_method_str()
        return public.autocopy_current_method():gsub('_', ' ')
    end

    function public.autocopy_status_str()
        return string.format(
                "%s (%s)",
                public.autocopy_is_enabled_str(),
                public.autocopy_current_method_str()
        )
    end

    function public.autocopy_current_method()
        return private.autoclip_method.get()
    end

    function public.toggle_autocopy()
        private.autoclip_enabled = not private.autoclip_enabled
        notify_autocopy()
    end

    function public.next_autoclip_method()
        private.autoclip_method.bump()
        notify_autocopy()
    end

    function public.import_subs(subs_list)
        public.clear()
        if not h.is_empty(subs_list) then
            for _, sub in ipairs(subs_list) do
                if sub.is_secondary then
                    private.secondary_dialogs.insert(sub)
                else
                    private.dialogs.insert(sub)
                end
            end
        end
    end

    function public.has_recorded_dialogs()
        return not private.dialogs.is_empty()
    end

    function public.init(menu, cfg_mgr)
        cfg_mgr.fail_if_not_ready()
        private.menu = menu
        private.config = cfg_mgr.config()

        if custom_subtitle_filter and custom_subtitle_filter.init then
            custom_subtitle_filter.init({
                get_mode = function()
                    return private.config.custom_subtitle_filter_mode
                end
            })
        end

        -- The autoclip state is copied as a local value
        -- to prevent it from being reset when the user reloads the config file.
        private.autoclip_enabled = private.config.autoclip
        private.autoclip_method.set(private.config.autoclip_method)

        mp.observe_property("sub-text", "string", handle_primary_sub)
        mp.observe_property("secondary-sub-text", "string", handle_secondary_sub)
    end

    return public
end

------------------------------------------------------------
--- Tests: executed by both standalone and mpv-backed runners.

local function make_test_primary_sub(text, start_time, end_time)
    return Subtitle:from_text(text, start_time, end_time)
end

local function make_test_secondary_sub(text, start_time, end_time)
    local sub = make_test_primary_sub(text, start_time, end_time)
    sub.is_secondary = true
    return sub
end

local function test_instances_keep_recorded_subs_isolated()
    local first = make_subtitles_observer()
    local second = make_subtitles_observer()
    first.import_subs { make_test_primary_sub("First", 0, 1) }
    second.import_subs { make_test_primary_sub("Second", 1, 2) }
    h.assert_equals(first.get_selected_primary_text(), "First")
    h.assert_equals(second.get_selected_primary_text(), "Second")
end

local function test_import_subs_separates_tracks_and_clear_resets_selection()
    local observer = make_subtitles_observer()
    observer.import_subs {
        make_test_primary_sub("Primary", 0, 1),
        make_test_secondary_sub("Secondary", 0, 1),
    }
    h.assert_equals(observer.get_selected_primary_text(), "Primary")
    h.assert_equals(observer.recorded_secondary_subs()[1]['text'], "Secondary")
    h.assert_equals(observer.get_timing('start'), 0)
    observer.clear()
    h.assert_equals(observer.has_recorded_dialogs(), false)
    h.assert_equals(#observer.recorded_secondary_subs(), 0)
    h.assert_equals(observer.get_timing('start'), -1)
end

local function test_autoclip_method_state_is_isolated()
    local first = make_subtitles_observer()
    local second = make_subtitles_observer()
    first.next_autoclip_method()
    h.assert_equals(first.autocopy_current_method(), 'goldendict')
    h.assert_equals(second.autocopy_current_method(), 'clipboard')
end

local function run_tests()
    test_instances_keep_recorded_subs_isolated()
    test_import_subs_separates_tracks_and_clear_resets_selection()
    test_autoclip_method_state_is_isolated()
end

return {
    new = make_subtitles_observer,
    run_tests = run_tests,
}
