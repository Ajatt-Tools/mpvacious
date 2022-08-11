--[[
Copyright: Ren Tatsumoto and contributors
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Provides additional methods for controlling playback.
]]

local mp = require('mp')
local h = require('helpers')
local pause_timer = require('utils.pause_timer')
local Subtitle = require('subtitles.subtitle')

local current_sub

local function stop_at_the_end(sub)
    pause_timer.set_stop_time(sub['end'] - 0.050)
    h.notify("Playing till the end of the sub...", "info", 3)
end

local function play_till_sub_end()
    local sub = Subtitle:now()
    mp.commandv('seek', sub['start'], 'absolute')
    mp.set_property("pause", "no")
    stop_at_the_end(sub)
end

local function sub_seek(direction, pause)
    mp.commandv("sub_seek", direction == 'backward' and '-1' or '1')
    mp.commandv("seek", "0.015", "relative+exact")
    if pause then
        mp.set_property("pause", "yes")
    end
    pause_timer.stop()
end

local function sub_rewind()
    mp.commandv('seek', Subtitle:now()['start'] + 0.015, 'absolute')
    pause_timer.stop()
end

local function check_sub()
    local sub = Subtitle:now()
    if sub and sub ~= current_sub then
        mp.unobserve_property(check_sub)
        stop_at_the_end(sub)
    end
end

local function play_till_next_sub_end()
    current_sub = Subtitle:now()
    mp.observe_property("sub-text", "string", check_sub)
    mp.set_property("pause", "no")
    h.notify("Waiting till next sub...", "info", 10)
end

return {
    play_till_sub_end = play_till_sub_end,
    play_till_next_sub_end = play_till_next_sub_end,
    sub_seek = sub_seek,
    sub_rewind = sub_rewind,
}
