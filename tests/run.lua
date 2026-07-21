--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Standalone test runner for mpvacious.
Runs without mpv using the stubs registered by tests/setup.lua.

Usage: luajit tests/run.lua
       (run from the project root directory)
]]

require('tests.setup')

------------------------------------------------------------
-- Run helpers tests
------------------------------------------------------------

print("Running helpers tests...")
local h = require('helpers')
h.run_tests()
print("helpers tests passed.")

------------------------------------------------------------
-- Run encoder utility tests
------------------------------------------------------------

print("Running encoder utility tests...")
local eutils = require('encoder.utils')
eutils.run_tests()
print("encoder utility tests passed.")

------------------------------------------------------------
-- Run note_exporter tests
------------------------------------------------------------

print("Running note_exporter tests...")
local note_exporter = require('anki.note_exporter')
note_exporter.run_tests()
print("note_exporter tests passed.")

------------------------------------------------------------

print("ALL TESTS PASSED")
