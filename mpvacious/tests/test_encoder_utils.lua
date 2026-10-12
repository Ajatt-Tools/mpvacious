--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Encoder utilities tests.
]]

local h = require("helpers")
local eutils = require("encoder.utils")
local defaults = require("config.defaults")

--- Run encoder timing and format utility regressions.
local function run_tests()
    h.assert_equals(
        eutils.static_scale_filter({
            snapshot_width = defaults.preserve_aspect_ratio,
            snapshot_height = 350,
        }),
        "scale='trunc(min(350,ih)*dar/2+0.5)*2':'min(350,ih)':flags=sinc+accurate_rnd,setsar=1"
    )
    h.assert_equals(
        eutils.static_scale_filter({
            snapshot_width = 640,
            snapshot_height = defaults.preserve_aspect_ratio,
        }),
        "scale='trunc(min(640,iw*sar)/2+0.5)*2':'trunc(min(640,iw*sar)/dar/2+0.5)*2':flags=sinc+accurate_rnd,setsar=1"
    )
    h.assert_equals(
        eutils.static_scale_filter({ snapshot_width = 640, snapshot_height = 350 }),
        "scale='min(640,iw)':'min(350,ih)':flags=sinc+accurate_rnd"
    )
    h.assert_equals(
        eutils.animated_scale_filter({
            animated_snapshot_width = defaults.preserve_aspect_ratio,
            animated_snapshot_height = 350,
        }),
        "scale='trunc(min(350,ih)*dar/2+0.5)*2':'min(350,ih)':flags=lanczos+accurate_rnd,setsar=1"
    )
end

return {
    run_tests = run_tests,
}
