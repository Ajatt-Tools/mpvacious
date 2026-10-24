--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Pause timer stops playback when reaching a set timing.
]]

local mp = require("mp")

local function make_pause_timer()
    local pub = {}
    local stop_time = -1

    --- Observe playback time until it passes the supplied stop boundary.
    function pub.set_stop_time(time)
        stop_time = time
        mp.observe_property("time-pos", "number", pub.check_stop)
    end

    --- Cancel this timer's playback observer and discard its stop boundary.
    function pub.stop()
        mp.unobserve_property(pub.check_stop)
        stop_time = -1
    end

    --- Pause playback after crossing the stop boundary and unregister this timer.
    function pub.check_stop(_, time)
        if time > stop_time then
            pub.stop()
            mp.set_property("pause", "yes")
        end
    end

    return pub
end

return {
    new = make_pause_timer,
}
