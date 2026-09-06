--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Secondary scanner discovers subtitle cues outside the currently visible event.
]]

local h = require('helpers')
local sub_list = require('subtitles.sub_list')
local Subtitle = require('subtitles.subtitle')

local BACKWARD = -1
local FORWARD = 1

local function new(mp_api, logger)
    mp_api = mp_api or require('mp')
    logger = logger or require('mp.msg')
    local scanning = false

    local function scan(observed, window, initial_delay, normalized_delay, direction)
        local previous_delay = initial_delay
        scanning = true
        local ok, scan_error = pcall(function()
            while true do
                mp_api.commandv('no-osd', 'sub-step', direction, 'secondary')
                local next_delay = mp_api.get_property_number('secondary-sub-delay', 0)
                local progressed = direction == FORWARD and next_delay < previous_delay
                        or direction == BACKWARD and next_delay > previous_delay
                if not progressed then
                    break
                end
                previous_delay = next_delay
                local next_sub = Subtitle:from_current('secondary', mp_api, normalized_delay)
                observed.insert(next_sub)
                if next_sub and (direction == FORWARD and next_sub['start'] >= window['end']
                        or direction == BACKWARD and next_sub['end'] <= window['start']) then
                    break
                end
            end
        end)
        local restored, restore_error = pcall(
                mp_api.set_property_number,
                'secondary-sub-delay',
                initial_delay
        )
        scanning = false
        if not ok then
            logger.error(scan_error)
        end
        if not restored then
            logger.error(restore_error)
        end
    end

    local function select_secondary(observed, primary)
        local initial_delay = mp_api.get_property_number('secondary-sub-delay', 0)
        local audio_delay = mp_api.get_property_number('audio-delay', 0)
        local normalized_delay = initial_delay - audio_delay

        observed.insert(Subtitle:from_current('secondary', mp_api, normalized_delay))
        local playback_position = mp_api.get_property_number('time-pos', 0) - audio_delay
        if primary:is_valid() and primary['start'] < playback_position then
            scan(observed, primary, initial_delay, normalized_delay, BACKWARD)
        end
        if primary:is_valid() and primary['end'] > playback_position then
            scan(observed, primary, initial_delay, normalized_delay, FORWARD)
        end
        return observed.select_overlapping(primary:timing_windows())
    end

    return {
        is_scanning = function()
            return scanning
        end,
        select = select_secondary,
    }
end

local function run_scan_case(case)
    local state = {
        cue_index = case.cue_index or 0,
        delay = case.delay or 0,
        directions = {},
        errors = {},
        restores = {},
    }
    local initial_index = state.cue_index
    local cues = case.cues or {}
    local function current_cue()
        return cues[state.cue_index]
    end
    local mp_stub = {
        get_property = function(name)
            local cue = current_cue()
            return name == 'secondary-sub-text' and cue and cue.text or nil
        end,
        get_property_native = function(name)
            return ({ ['secondary-sub-delay'] = state.delay, ['audio-delay'] = case.audio_delay or 0 })[name]
        end,
        get_property_number = function(name, default)
            local cue = current_cue()
            local values = {
                ['secondary-sub-delay'] = state.delay,
                ['audio-delay'] = case.audio_delay or 0,
                ['time-pos'] = case.playback_position,
                ['secondary-sub-start'] = cue and cue['start'],
                ['secondary-sub-end'] = cue and cue['end'],
            }
            return values[name] == nil and default or values[name]
        end,
        commandv = function(no_osd, command, direction, track)
            h.assert_equals({ no_osd, command, track }, { 'no-osd', 'sub-step', 'secondary' })
            state.directions[#state.directions + 1] = direction
            if case.command_error then
                error(case.command_error)
            end
            state.cue_index = state.cue_index + direction
            state.delay = (case.step_delays or {})[#state.directions] or state.delay
        end,
        set_property_number = function(name, value)
            h.assert_equals(name, 'secondary-sub-delay')
            state.restores[#state.restores + 1] = value
            state.delay = value
            state.cue_index = initial_index
        end,
    }
    local logger = {
        error = function(value)
            state.errors[#state.errors + 1] = value
        end,
    }
    local scanner = new(mp_stub, logger)
    state.selection = scanner.select(sub_list.new(), case.primary)
    state.scanning = scanner.is_scanning()
    return state
end

local function test_collects_cues_in_both_directions()
    local cases = {
        {
            cues = {
                { text = 'Relevant', start = 10, ['end'] = 13 },
                { text = 'Also relevant', start = 13, ['end'] = 15 },
                { text = 'Past the window', start = 20, ['end'] = 22 },
            },
            delay = 2,
            step_delays = { 0, -3, -10 },
            audio_delay = 0.5,
            playback_position = 10,
            primary = Subtitle:from_text('', 11.5, 16),
            text = 'Relevant Also relevant',
            directions = { FORWARD, FORWARD, FORWARD },
        },
        {
            cues = {
                { text = 'Before the window', start = 7, ['end'] = 9 },
                { text = 'Relevant previous', start = 11, ['end'] = 14 },
                { text = 'Current', start = 14, ['end'] = 16 },
            },
            cue_index = 3,
            step_delays = { 3, 7 },
            playback_position = 18,
            primary = Subtitle:from_text('', 10, 16),
            text = 'Relevant previous Current',
            directions = { BACKWARD, BACKWARD },
        },
    }
    for _, case in ipairs(cases) do
        local state = run_scan_case(case)
        h.assert_equals(state.selection.text, case.text)
        h.assert_equals(state.directions, case.directions)
        h.assert_equals(state.restores, { case.delay or 0 })
        h.assert_equals(state.errors, {})
        h.assert_equals(state.scanning, false)
    end
end

local function test_terminates_when_delay_does_not_progress()
    local cases = {
        { playback_position = 18, primary = Subtitle:from_text('', 10, 20), directions = { -1, 1 }, restores = 2 },
        { playback_position = 0, primary = Subtitle:from_text('', 0, 5), directions = { 1 }, restores = 1 },
        { playback_position = 5, primary = Subtitle:from_text('', 0, 5), directions = { -1 }, restores = 1 },
    }
    for _, case in ipairs(cases) do
        local state = run_scan_case(case)
        h.assert_equals(state.directions, case.directions)
        h.assert_equals(#state.restores, case.restores)
        h.assert_equals(state.scanning, false)
    end
end

local function test_reports_errors_after_restoring_delay()
    for _, case in ipairs {
        { playback_position = 10, primary = Subtitle:from_text('', 10, 20) },
        { playback_position = 20, primary = Subtitle:from_text('', 10, 20) },
    } do
        case.command_error = 'simulated sub-step failure'
        local state = run_scan_case(case)
        h.assert_equals(#state.directions, 1)
        h.assert_equals(#state.restores, 1)
        h.assert_equals(#state.errors, 1)
        h.assert_equals(state.scanning, false)
    end
end

local function run_tests()
    test_collects_cues_in_both_directions()
    test_terminates_when_delay_does_not_progress()
    test_reports_errors_after_restoring_delay()
end

return {
    new = new,
    run_tests = run_tests,
}
