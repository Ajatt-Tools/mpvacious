--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Standalone test runner for mpvacious.
Runs without mpv using the stubs registered by tests/setup.lua.

Usage: luajit tests/run.lua
       (run from the project root directory)
]]

require('tests.setup')

local modules = {
    'helpers',
    'encoder.utils',
    'config.utils',
    'anki.note_exporter',
    'subtitles.subtitle',
    'subtitles.collector',
    'subtitles.sub_list',
}

for _, module_name in ipairs(modules) do
    print(string.format("Running %s tests...", module_name))
    local module = require(module_name)
    module.run_tests()
    print(string.format("%s tests passed.", module_name))
end

------------------------------------------------------------

print("ALL TESTS PASSED")
