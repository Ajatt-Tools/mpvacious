--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Subtitle class provides methods for storing and comparing subtitle lines.
]]

local mp = require("mp")
local h = require("helpers")

local SAME_EVENT_TIME_TOLERANCE_SECONDS = 0.05

local Subtitle = {
    ["text"] = "",
    ["secondary"] = "",
    ["start"] = -1,
    ["end"] = -1,
    ["is_secondary"] = false,
}

function Subtitle:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

--- Return a shallow copy preserving subtitle fields and class methods.
function Subtitle:clone()
    return Subtitle:new(h.shallow_copy(self))
end

function Subtitle:from_text(text, start_time, end_time)
    return self:new { ["text"] = text, ["start"] = start_time, ["end"] = end_time }
end

--- Return the selected subtitle track's delay relative to the audio track.
--- mp_api defaults to mp; tests may provide an mp-compatible stub.
local function subtitle_delay(is_secondary, mp_api)
    mp_api = mp_api or mp
    local delay_property = is_secondary and "secondary-sub-delay" or "sub-delay"
    return mp_api.get_property_native(delay_property) - mp_api.get_property_native("audio-delay")
end

--- Create a subtitle from its text and start/end timestamps.
local function make_subtitle(text, start_time, end_time)
    return Subtitle:from_text(text, start_time, end_time)
end

--- Collect the visible subtitle with audio-relative delays applied.
--- mp_api defaults to mp; callers may supply an mp-compatible API.
local function make_current(is_secondary, mp_api)
    return Subtitle:now(is_secondary, mp_api)
end

--- Return the currently displayed primary or secondary subtitle with mpv delays applied.
function Subtitle:now(is_secondary, mp_api)
    mp_api = mp_api or mp
    local prefix = is_secondary and "secondary-" or ""
    local this = self:new {
        ["text"] = mp_api.get_property(prefix .. "sub-text"),
        ["start"] = mp_api.get_property_number(prefix .. "sub-start"),
        ["end"] = mp_api.get_property_number(prefix .. "sub-end"),
        ["is_secondary"] = (is_secondary and true or false),
    }
    if this:is_valid() then
        return this:delay(subtitle_delay(is_secondary, mp_api))
    else
        return nil
    end
end

function Subtitle:delay(delay)
    self["start"] = self["start"] + delay
    self["end"] = self["end"] + delay
    return self
end

function Subtitle:is_valid()
    return self["start"] and self["end"] and self["start"] >= 0 and self["end"] > self["start"]
end

local function is_near(first, second)
    return math.abs(first - second) <= SAME_EVENT_TIME_TOLERANCE_SECONDS
end

function Subtitle:is_same_event(other)
    return self["text"] == other["text"]
        and is_near(self["start"], other["start"])
        and is_near(self["end"], other["end"])
end

--- Return this subtitle's duration in seconds.
function Subtitle:duration()
    return self["end"] - self["start"]
end

--- Return the non-negative overlap duration with another subtitle, in seconds.
function Subtitle:overlap_duration(other)
    return math.max(0, math.min(self["end"], other["end"]) - math.max(self["start"], other["start"]))
end

--- Return true if this sub and other intersect in time. Touching boundaries do not count.
function Subtitle:overlaps_in_time(other)
    return self:overlap_duration(other) > 0
end

--- Return true if this sub and other intersect or merely touch in time.
function Subtitle:overlaps_or_touches_in_time(other)
    return self["start"] <= other["end"] and self["end"] >= other["start"]
end

-- Same text and overlapping (or touching) in time. Strict: a real gap is a real gap.
-- Forward-only: other must not start before self, so expanding never
-- decreases start and the recorded list stays sorted.
function Subtitle:can_expand_with(other)
    return self["text"] == other["text"] and other["start"] >= self["start"] and other["start"] <= self["end"]
end

-- Expand this event's end time to cover other. Start is unchanged (forward expansion).
function Subtitle:expand_end_time(other)
    self["end"] = math.max(self["end"], other["end"])
    return self
end

--- Replace both timing boundaries and return this subtitle for chaining.
function Subtitle:set_timings(start_time, end_time)
    self["start"] = start_time
    self["end"] = end_time
    return self
end

Subtitle.__eq = function(lhs, rhs)
    return lhs:is_same_event(rhs)
end

Subtitle.__lt = function(lhs, rhs)
    if lhs["start"] == rhs["start"] then
        return lhs["end"] < rhs["end"]
    else
        return lhs["start"] < rhs["start"]
    end
end

return {
    Subtitle = Subtitle,
    subtitle_delay = subtitle_delay,
    make_subtitle = make_subtitle,
    make_current = make_current,
}
