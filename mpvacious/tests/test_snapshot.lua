--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Transaction-local configuration snapshot tests.
]]

local h = require('helpers')
local fixtures = require('tests.fixtures')
local snapshot = require('config.snapshot')

--- Verify configuration and profile metadata detach from subsequent live changes.
local function test_snapshot_captures_nested_settings()
    for _, accessor in ipairs { 'config', 'profiles' } do
        local source = { value = 'original', nested = { value = 'original' } }
        local manager = fixtures.make_config_manager(source, source)
        local first = snapshot.new(manager)
        source.value, source.nested.value = 'changed', 'changed'
        local second = snapshot.new(manager)
        h.assert_equals(first[accessor](), { value = 'original', nested = { value = 'original' } })
        h.assert_equals(second[accessor](), source)
        h.assert_equals(first.fail_if_not_ready(), true)
    end
end

--- Transaction-local mutations persist locally without leaking to the source or another snapshot.
local function test_snapshot_local_mutations()
    for _, accessor in ipairs { 'config', 'profiles' } do
        local source = { value = 'original', nested = { value = 'original' } }
        local manager = fixtures.make_config_manager(source, source)
        local first, second = snapshot.new(manager), snapshot.new(manager)
        local captured = first[accessor]()
        captured.value, captured.nested.value = 'local', 'local'
        h.assert_equals(first[accessor](), { value = 'local', nested = { value = 'local' } })
        h.assert_equals(second[accessor](), { value = 'original', nested = { value = 'original' } })
        h.assert_equals(source, { value = 'original', nested = { value = 'original' } })
        h.assert_equals(first[accessor]() == captured, true)
    end
end

--- Reject snapshot capture until the source manager is ready.
local function test_snapshot_requires_ready_manager()
    local manager = fixtures.make_config_manager({ value = 'original' })
    manager.fail_if_not_ready = h.as_callback(error, 'config not loaded')
    local success, error = pcall(snapshot.new, manager)
    h.assert_equals(success, false)
    h.assert_equals(h.is_substr(error, 'config not loaded'), true)
end

--- Run snapshot ownership and readiness regressions.
local function run_tests()
    test_snapshot_captures_nested_settings()
    test_snapshot_local_mutations()
    test_snapshot_requires_ready_manager()
end

return {
    run_tests = run_tests,
}
