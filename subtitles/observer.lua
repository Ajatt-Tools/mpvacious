--[[
Copyright: Ren Tatsumoto and contributors
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Observer waits for subtitles to appear on the screen and adds them to a list.
]]

local h = require('helpers')
local timings = require('utils.timings')
local sub_list = require('subtitles.sub_list')
local Subtitle = require('subtitles.subtitle')
local mp = require('mp')
local platform = require('platform.init')
local switch = require('utils.switch')
local custom_sub_filter = pcall(h.maybe_require, 'subs2srs_sub_filter')

local self = {}

local dialogs = sub_list.new()
local secondary_dialogs = sub_list.new()
local all_dialogs = sub_list.new()
local all_secondary_dialogs = sub_list.new()
local user_timings = timings.new()

local append_dialogue = false
local autoclip_enabled = false
local autoclip_method = {}


------------------------------------------------------------
-- private

local function copy_primary_sub()
    if autoclip_enabled then
        autoclip_method.call()
    end
end

local function append_primary_sub()
    local current_sub = Subtitle:now()
    all_dialogs.insert(current_sub)
    if append_dialogue and dialogs.insert(current_sub) then
        self.menu:update()
    end
end

local function append_secondary_sub()
    local current_secondary = Subtitle:now('secondary')
    all_secondary_dialogs.insert(current_secondary)
    if append_dialogue and secondary_dialogs.insert(Subtitle:now('secondary')) then
        self.menu:update()
    end
end

local function start_appending()
    append_dialogue = true
    append_primary_sub()
    append_secondary_sub()
end

local function handle_primary_sub()
    append_primary_sub()
    copy_primary_sub()
end

local function handle_secondary_sub()
    append_secondary_sub()
end

local function on_external_finish(success, result, error)
    if success ~= true or error ~= nil then
        h.notify("Command failed: " .. table.concat(result))
    end
end

local function external_command_args(cur_lines)
    local args = {}
    for arg in string.gmatch(self.config.autoclip_custom_args, "%S+") do
        if arg == '%MPV_PRIMARY%' then
            arg = cur_lines.primary
        elseif arg == '%MPV_SECONDARY%' then
            arg = cur_lines.secondary
        end
        table.insert(args, arg)
    end
    return args
end

local function call_external_command(cur_lines)
    if not h.is_empty(self.config.autoclip_custom_args) then
        h.subprocess(external_command_args(cur_lines), on_external_finish)
    end
end

local function current_subtitle_lines()
    local primary = dialogs.get_text()

    if h.is_empty(primary) then
        primary = mp.get_property("sub-text")
    end

    if h.is_empty(primary) then
        return nil
    end

    local secondary = secondary_dialogs.get_text()

    if h.is_empty(secondary) then
        secondary = mp.get_property("secondary-sub-text") or ""
    end

    return { primary = self.clipboard_prepare(primary), secondary = secondary }
end

local function ensure_goldendict_running()
    --- Ensure that goldendict is running and is disowned by mpv.
    --- Avoid goldendict getting killed when mpv exits.
    if autoclip_enabled and self.autocopy_current_method() == "goldendict" then
        os.execute("setsid -f goldendict")
    end
end

------------------------------------------------------------
-- autoclip methods

autoclip_method = (function()
    local methods = { 'clipboard', 'goldendict', 'custom_command', }
    local current_method = switch.new(methods)

    local function call()
        local cur_lines = current_subtitle_lines()
        if h.is_empty(cur_lines) then
            return
        end

        if current_method.get() == 'clipboard' then
            self.copy_to_clipboard("autocopy action", cur_lines.primary)
        elseif current_method.get() == 'goldendict' then
            h.subprocess_detached({ 'goldendict', cur_lines.primary }, on_external_finish)
        elseif current_method.get() == 'custom_command' then
            call_external_command(cur_lines)
        end
    end

    return {
        call = call,
        get = current_method.get,
        bump = current_method.bump,
        set = current_method.set,
    }
end)()

local function copy_subtitle(subtitle_id)
    self.copy_to_clipboard("copy-on-demand", mp.get_property(subtitle_id))
end

------------------------------------------------------------
-- custom sub filter method

local function apply_custom_sub_filter(text)
    if self.config.custom_sub_filter_enabled and custom_sub_filter and custom_sub_filter.preprocess then
		return custom_sub_filter.preprocess(text)
    end
    return text
end

local function apply_custom_trim(text)
    if self.config.use_custom_trim and custom_sub_filter and custom_sub_filter.trim then
		return custom_sub_filter.trim(text)
    end
    return h.trim(text)
end

------------------------------------------------------------
-- public

self.copy_to_clipboard = function(_, text)
    if platform.healthy == false then
        h.notify(platform.clip_util .. " is not installed.", "error", 5)
    end
    if not h.is_empty(text) then
        platform.copy_to_clipboard(self.clipboard_prepare(text))
    end
end

self.clipboard_prepare = function(text)
    text = apply_custom_sub_filter(text)

    if self.config.clipboard_trim_enabled then
        text = apply_custom_trim(text)
    else
        text = h.remove_newlines(text)
    end

    text = self.maybe_remove_all_spaces(text)
    return text
end

self.maybe_remove_all_spaces = function(str)
    if self.config.nuke_spaces == true and h.contains_non_latin_letters(str) then
        return h.remove_all_spaces(str)
    else
        return str
    end
end

self.copy_current_primary_to_clipboard = function()
    copy_subtitle("sub-text")
end

self.copy_current_secondary_to_clipboard = function()
    copy_subtitle("secondary-sub-text")
end

self.user_altered = function()
    --- Return true if the user manually set at least start or end.
    return user_timings.is_set('start') or user_timings.is_set('end')
end

self.get_timing = function(position)
    if user_timings.is_set(position) then
        return user_timings.get(position)
    elseif not dialogs.is_empty() then
        return dialogs.get_time(position)
    end
    return -1
end

self.collect_from_all_dialogues = function(n_lines)
    local current_sub = Subtitle:now()
    local current_secondary_sub = Subtitle:now('secondary')
    all_dialogs.insert(current_sub)
    all_secondary_dialogs.insert(current_secondary_sub)
    if current_sub == nil then
        return Subtitle:new() -- return a default empty new Subtitle to let consumer handle
    end
    local text, end_sub = all_dialogs.get_n_text(current_sub, n_lines)
    local secondary_text, _
    if current_secondary_sub == nil then
        secondary_text = ''
    else
        secondary_text, _ = all_secondary_dialogs.get_n_text(current_secondary_sub, n_lines) -- we'll use main sub's timing
    end
    return Subtitle:new {
        ['text'] = text,
        ['secondary'] = secondary_text,
        ['start'] = current_sub['start'],
        ['end'] = end_sub['end'],
    }
end

self.collect_from_current = function()
    --- Return all recorded subtitle lines as one subtitle object.
    --- The caller has to call subs_observer.clear() afterwards.
    if dialogs.is_empty() then
        dialogs.insert(Subtitle:now())
    end
    if secondary_dialogs.is_empty() then
        secondary_dialogs.insert(Subtitle:now('secondary'))
    end
    return Subtitle:new {
        ['text'] = dialogs.get_text(),
        ['secondary'] = secondary_dialogs.get_text(),
        ['start'] = self.get_timing('start'),
        ['end'] = self.get_timing('end'),
    }
end

self.set_manual_timing = function(position)
    user_timings.set(position, mp.get_property_number('time-pos') - mp.get_property("audio-delay"))
    h.notify(h.capitalize_first_letter(position) .. " time has been set.")
    start_appending()
end

self.set_manual_timing_to_sub = function(position)
    local sub = Subtitle:now()
    if sub then
        user_timings.set(position, sub[position] - mp.get_property("audio-delay"))
        h.notify(h.capitalize_first_letter(position) .. " time has been set.")
        start_appending()
    else
        h.notify("There's no visible subtitle.", "info", 2)
    end
end

self.set_to_current_sub = function()
    self.clear()
    if Subtitle:now() then
        start_appending()
        h.notify("Timings have been set to the current sub.", "info", 2)
    else
        h.notify("There's no visible subtitle.", "info", 2)
    end
end

self.clear = function()
    append_dialogue = false
    dialogs = sub_list.new()
    secondary_dialogs = sub_list.new()
    user_timings = timings.new()
end

self.clear_all_dialogs = function()
    all_dialogs = sub_list.new()
    all_secondary_dialogs = sub_list.new()
end

self.clear_and_notify = function()
    --- Clear then notify the user.
    --- Called by the OSD menu when the user presses a button to drop recorded subtitles.
    self.clear()
    h.notify("Timings have been reset.", "info", 2)
end

self.is_appending = function()
    return append_dialogue
end

self.recorded_subs = function()
    return dialogs.get_subs_list()
end

self.recorded_secondary_subs = function()
    return secondary_dialogs.get_subs_list()
end

self.autocopy_status_str = function()
    return string.format(
            "%s (%s)",
            (autoclip_enabled and 'enabled' or 'disabled'),
            autoclip_method.get():gsub('_', ' ')
    )
end

self.autocopy_current_method = function()
    return autoclip_method.get()
end

local function notify_autocopy()
    if autoclip_enabled then
        copy_primary_sub()
    end
    h.notify(string.format("Clipboard autocopy has been %s.", self.autocopy_status_str()))
end

self.toggle_autocopy = function()
    autoclip_enabled = not autoclip_enabled
    notify_autocopy()
end

self.next_autoclip_method = function()
    autoclip_method.bump()
    notify_autocopy()
end

self.init = function(menu, config)
    self.menu = menu
    self.config = config

    -- The autoclip state is copied as a local value
    -- to prevent it from being reset when the user reloads the config file.
    autoclip_enabled = self.config.autoclip
    autoclip_method.set(self.config.autoclip_method)

    mp.observe_property("sub-text", "string", handle_primary_sub)
    mp.observe_property("secondary-sub-text", "string", handle_secondary_sub)
end

return self
