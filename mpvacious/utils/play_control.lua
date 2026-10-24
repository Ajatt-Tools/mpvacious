--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Provides additional methods for controlling playback.
]]

local mp = require("mp")
local h = require("helpers")
local make_pause_timer = require("utils.pause_timer")
local subtitle = require("subtitles.subtitle")

--- Create playback controls with independent state and optional mpv and notifier dependencies.
local function make_play_control(components)
    components = components or {}
    local mp_api = components.mp or mp
    local self = {}
    local pub = {}
    self.notify = components.notify or h.notify
    self.pause_timer = make_pause_timer.new { mp = mp_api }
    self.current_sub = nil

    ------------------------------------------------------------
    --- Private

    --- Schedule a pause just before the adjusted subtitle end.
    local function stop_at_the_end(sub)
        self.pause_timer.set_stop_time(sub["end"] - 0.050)
        self.notify("Playing till the end of the sub...", "info", 3)
    end

    --- Stop at the next visible subtitle, ignoring absent and unchanged events.
    local function check_sub()
        local sub = subtitle.make_current { is_secondary = false, mp_api = mp_api, delay = true }
        if sub and sub ~= self.current_sub then
            mp_api.unobserve_property(check_sub)
            stop_at_the_end(sub)
        end
    end

    --- Convert direction string to mpv step value.
    local function get_mpv_step(direction)
        if direction == "backward" then
            return "-1"
        end
        return "1"
    end

    ------------------------------------------------------------
    --- Public

    --- Replay the visible primary subtitle using audio-relative seek and stop timings.
    function pub.play_till_sub_end()
        local sub = subtitle.make_current { is_secondary = false, mp_api = mp_api, delay = true }
        if sub == nil then
            self.notify("No subtitle is currently playing", "error", 5)
            return
        end
        mp_api.commandv("seek", sub["start"], "absolute")
        mp_api.set_property("pause", "no")
        stop_at_the_end(sub)
    end

    --- Watch the primary subtitle track and play until the next subtitle ends.
    function pub.play_till_next_sub_end()
        self.current_sub = subtitle.make_current { is_secondary = false, mp_api = mp_api, delay = true }
        mp_api.observe_property("sub-text", "string", check_sub)
        mp_api.set_property("pause", "no")
        self.notify("Waiting till next sub...", "info", 10)
    end

    --- Seek between subtitle boundaries, optionally pausing and cancelling the stop timer.
    function pub.sub_seek(direction, pause)
        h.assert_in(direction, { "backward", "forward" })
        mp_api.commandv("sub_seek", get_mpv_step(direction))
        mp_api.commandv("seek", "0.015", "relative+exact")
        if pause then
            mp_api.set_property("pause", "yes")
        end
        self.pause_timer.stop()
    end

    --- Rewind slightly inside the visible primary subtitle's adjusted start time.
    function pub.sub_rewind()
        local sub = subtitle.make_current { is_secondary = false, mp_api = mp_api, delay = true }
        if sub == nil then
            self.notify("No subtitle is currently visible", "error", 5)
            return
        end
        mp_api.commandv("seek", sub["start"] + 0.015, "absolute")
        self.pause_timer.stop()
    end

    return pub
end

return {
    new = make_play_control,
}
