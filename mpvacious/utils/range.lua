-- Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
-- License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

local h = require("helpers")

--- An inclusive numeric interval with named lower and upper boundaries.
local Range = {
    from = nil, -- Inclusive lower boundary, required at construction.
    to = nil, -- Inclusive upper boundary, required at construction.
}

--- Turn the supplied table into a range, preserving its identity and additional fields.
function Range:new(o)
    h.assert_type(o, "table")
    -- Inherited boundaries would disappear when the supplied metatable is replaced.
    h.assert_type(rawget(o, "from"), "number")
    h.assert_type(rawget(o, "to"), "number")
    assert(o.from <= o.to, "expected range.from <= range.to")
    setmetatable(o, self)
    self.__index = self
    return o
end

--- Return whether the numeric value falls within this inclusive range.
function Range:contains(value)
    h.assert_type(value, "number")
    return value >= self.from and value <= self.to
end

return Range
