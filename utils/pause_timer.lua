--[[
Copyright: Ren Tatsumoto and contributors
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Pause timer stops playback when reaching a set timing.
]]

local mp = require('mp')
local stop_time = -1
local check_stop

local set_stop_time = function(time)
    stop_time = time
    mp.observe_property("time-pos", "number", check_stop)
end

local stop = function()
    mp.unobserve_property(check_stop)
    stop_time = -1
end

check_stop = function(_, time)
    if time > stop_time then
        stop()
        mp.set_property("pause", "yes")
    end
end

return {
    set_stop_time = set_stop_time,
    check_stop = check_stop,
    stop = stop,
}
