--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Note update guard verifies sentence identity and owns confirmation prompts.
]]

local h = require('helpers')

local function normalize_sentence(text)
    text = h.unescape_special_characters((text or ''):lower())
    return h.normalize_subtitle_text(text)
end

local function sentences_are_related(first, second)
    first, second = normalize_sentence(first), normalize_sentence(second)
    return not h.is_empty(first)
            and not h.is_empty(second)
            and (h.is_substr(first, second) or h.is_substr(second, first))
end

local function sentence_field(note_id, field_name, get_note_fields)
    local fields = get_note_fields(note_id) or {}
    return fields[field_name] or ''
end

local function current_subtitle_warning(note_ids, current_sentence, field_name, get_note_fields)
    if h.is_empty(current_sentence) then
        return nil
    end

    local comparable_count = 0
    local related_count = 0
    for _, note_id in ipairs(note_ids) do
        local stored_sentence = sentence_field(note_id, field_name, get_note_fields)
        if not h.is_empty(normalize_sentence(stored_sentence)) then
            comparable_count = comparable_count + 1
            if sentences_are_related(current_sentence, stored_sentence) then
                related_count = related_count + 1
            end
        end
    end

    if comparable_count == 0 or related_count == comparable_count then
        return nil
    elseif #note_ids == 1 then
        return string.format("The target note's %s does not match the current subtitle.", field_name)
    end
    return string.format(
            "Only %i of %i target notes have %s matching the current subtitle.",
            related_count,
            comparable_count,
            field_name
    )
end

local function recent_notes_warning(note_ids, field_name, get_note_fields)
    if #note_ids < 2 then
        return nil
    end

    local newest = normalize_sentence(sentence_field(note_ids[#note_ids], field_name, get_note_fields))
    if h.is_empty(newest) then
        return nil, string.format(
                "Couldn't verify related notes: newest note has an empty %s field.",
                field_name
        )
    end

    local related_count = 1
    for i = #note_ids - 1, 1, -1 do
        if normalize_sentence(sentence_field(note_ids[i], field_name, get_note_fields)) ~= newest then
            break
        end
        related_count = related_count + 1
    end
    if related_count < #note_ids then
        return string.format(
                "Only the newest %i of %i notes share %s.",
                related_count,
                #note_ids,
                field_name
        )
    end
    return nil
end

local function new(dependencies)
    dependencies = dependencies or {
        input = require('mp.input'),
        logger = require('mp.msg'),
        mp = require('mp'),
    }
    local active

    local function close()
        if not active then
            return
        end
        if active.timer then
            active.timer:kill()
        end
        active = nil
        dependencies.input.terminate()
    end

    local function confirm(options)
        close()
        local confirmation = {}
        active = confirmation

        local function finish(confirmed)
            if active ~= confirmation then
                return
            end
            close()
            if confirmed then
                options.accepted()
            else
                options.cancelled()
            end
        end

        local question = options.note_count == 1
                and "Update this note anyway?"
                or string.format("Update all %i notes anyway?", options.note_count)
        confirmation.timer = dependencies.mp.add_timeout(10, function()
            finish(false)
        end)
        dependencies.input.select({
            prompt = string.format("Warning: %s mismatch. %s", options.field_name, question),
            items = { "Yes", "No" },
            default_item = 2,
            submit = function(index)
                finish(index == 1)
            end,
            closed = function()
                finish(false)
            end,
        })
        dependencies.logger.warn(string.format("%s %s", options.warning, question))
    end

    return {
        close = close,
        confirm = confirm,
    }
end

local function note_fields(sentences)
    return function(note_id)
        return { SentKanji = sentences[note_id] }
    end
end

local function test_sentence_relationship()
    local sentence = "それは うまくすれば 鉛から黄金を生み出すことも 可能になる"
    h.assert_equals(sentences_are_related(sentence, "鉛から<b>黄金</b>を生み出すことも"), true)
    h.assert_equals(sentences_are_related(sentence, "まあ 無理やり手伝った というのが正しい"), false)
    h.assert_equals(sentences_are_related('', sentence), false)
end

local function test_current_subtitle_warning()
    local sentence = 'それは うまくすれば 鉛から黄金を生み出すことも 可能になる'
    local unrelated = 'まあ 無理やり手伝った というのが正しいけれど それで稼いだお金よ'
    local cases = {
        { ids = { 1 }, stored = { [1] = '鉛から<b>黄金</b>を生み出すことも' }, expected = nil },
        {
            ids = { 1 },
            stored = { [1] = unrelated },
            expected = "The target note's SentKanji does not match the current subtitle.",
        },
        {
            ids = { 1, 2 },
            stored = { [1] = sentence, [2] = unrelated },
            expected = 'Only 1 of 2 target notes have SentKanji matching the current subtitle.',
        },
    }
    for _, case in ipairs(cases) do
        h.assert_equals(
                current_subtitle_warning(case.ids, sentence, 'SentKanji', note_fields(case.stored)),
                case.expected
        )
    end
end

local function test_recent_notes_warning()
    local ids = { 1, 2, 3, 4, 5 }
    local warning = recent_notes_warning(
            ids,
            'SentKanji',
            note_fields({ 'unrelated one', 'unrelated two', 'target', '<b>target</b>', 'target' })
    )
    h.assert_equals(warning, 'Only the newest 3 of 5 notes share SentKanji.')
    h.assert_equals(recent_notes_warning(ids, 'SentKanji', note_fields({ 'target', 'target', 'target', 'target', 'target' })), nil)
    local _, err = recent_notes_warning(ids, 'SentKanji', note_fields({ 'target', 'target', 'target', 'target', '' }))
    h.assert_equals(err, "Couldn't verify related notes: newest note has an empty SentKanji field.")
end

local function confirmation_fixture()
    local state = { accepted = 0, cancelled = 0, terminated = 0, timer_kills = 0 }
    local dependencies = {
        input = {
            select = function(options)
                state.options = options
            end,
            terminate = function()
                state.terminated = state.terminated + 1
            end,
        },
        logger = {
            warn = function(message)
                state.warning = message
            end,
        },
        mp = {
            add_timeout = function(_, callback)
                state.timeout = callback
                return { kill = function() state.timer_kills = state.timer_kills + 1 end }
            end,
        },
    }
    local confirmation = new(dependencies)
    confirmation.confirm({
        note_count = 1,
        field_name = 'SentKanji',
        warning = 'Different sentence.',
        accepted = function()
            state.accepted = state.accepted + 1
        end,
        cancelled = function()
            state.cancelled = state.cancelled + 1
        end,
    })
    return state
end

local function test_confirmation_lifecycle()
    local accepted = confirmation_fixture()
    h.assert_equals(accepted.options.items, { 'Yes', 'No' })
    h.assert_equals(accepted.options.default_item, 2)
    h.assert_equals(accepted.options.prompt, 'Warning: SentKanji mismatch. Update this note anyway?')
    accepted.options.submit(1)
    accepted.options.closed()
    h.assert_equals({ accepted.accepted, accepted.cancelled }, { 1, 0 })
    h.assert_equals({ accepted.terminated, accepted.timer_kills }, { 1, 1 })

    local cancelled = confirmation_fixture()
    cancelled.timeout()
    h.assert_equals({ cancelled.accepted, cancelled.cancelled }, { 0, 1 })
    h.assert_equals({ cancelled.terminated, cancelled.timer_kills }, { 1, 1 })
end

local function run_tests()
    test_sentence_relationship()
    test_current_subtitle_warning()
    test_recent_notes_warning()
    test_confirmation_lifecycle()
end

return {
    current_subtitle_warning = current_subtitle_warning,
    new = new,
    recent_notes_warning = recent_notes_warning,
    run_tests = run_tests,
    sentences_are_related = sentences_are_related,
}
