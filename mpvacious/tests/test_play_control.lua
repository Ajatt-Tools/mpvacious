--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Playback-control construction tests.
]]

local h = require("helpers")
local play_control = require("utils.play_control")

--- Each construction returns its own command table without invoking playback operations.
local function test_instances_own_command_tables()
    local first, second = play_control.new(), play_control.new()
    h.assert_equals(rawequal(first, second), false)
    for _, name in ipairs { "play_till_sub_end", "play_till_next_sub_end", "sub_seek", "sub_rewind" } do
        h.assert_equals(type(first[name]), "function")
        h.assert_equals(type(second[name]), "function")
    end
    local rewind = second.sub_rewind
    first.sub_rewind = h.noop
    h.assert_equals(rawequal(second.sub_rewind, rewind), true)
    h.assert_equals(rawequal(second.sub_rewind, h.noop), false)
end

--- Run playback-control instance regressions in both test environments.
local function run_tests()
    test_instances_own_command_tables()
end

return { run_tests = run_tests }
