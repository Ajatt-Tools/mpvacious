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

local self = {}

local dialogs = sub_list.new()
local secondary_dialogs = sub_list.new()
local user_timings = timings.new()
local is_observing = false

local function append_primary()
    if dialogs.insert(Subtitle:now()) then
        self.menu:update()
    end
end

local function append_secondary()
    if secondary_dialogs.insert(Subtitle:now('secondary')) then
        self.menu:update()
    end
end

local function observe()
    if not is_observing then
        mp.observe_property("sub-text", "string", append_primary)
        mp.observe_property("secondary-sub-text", "string", append_secondary)
        is_observing = true
    end
end

local function unobserve()
    if is_observing then
        mp.unobserve_property(append_primary)
        mp.unobserve_property(append_secondary)
        is_observing = false
    end
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

self.collect = function()
    --- Return all recorded subtitle lines as one subtitle object.
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
    user_timings.set(position, mp.get_property_number('time-pos'))
    h.notify(h.capitalize_first_letter(position) .. " time has been set.")
    observe()
end

self.set_manual_timing_to_sub = function(position)
    local sub = Subtitle:now()
    if sub then
        user_timings.set(position, sub[position])
        h.notify(h.capitalize_first_letter(position) .. " time has been set.")
        observe()
    else
        h.notify("There's no visible subtitle.", "info", 2)
    end
end

self.begin_observing = function()
    self.clear()
    if Subtitle:now() then
        observe()
        h.notify("Timings have been set to the current sub.", "info", 2)
    else
        h.notify("There's no visible subtitle.", "info", 2)
    end
end

self.clear = function()
    unobserve()
    dialogs = sub_list.new()
    secondary_dialogs = sub_list.new()
    user_timings = timings.new()
end

self.clear_and_notify = function()
    self.clear()
    h.notify("Timings have been reset.", "info", 2)
end

self.is_observing = function()
    return is_observing
end

self.recorded_subs = function()
    return dialogs.get_subs_list()
end

self.init = function(menu)
    self.menu = menu
end

return self
