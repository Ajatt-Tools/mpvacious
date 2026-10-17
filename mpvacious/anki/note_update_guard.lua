--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Note update guard verifies sentence identity before updating Anki notes.
]]

local h = require("helpers")

--- Create pure sentence-matching policy for guarded note updates.
local function make_note_update_guard()
    local private = {}
    local public = {}

    --- Return the configured sentence from one supplied note field table.
    function private.sentence_field(note_fields, field_name)
        return note_fields[field_name] or ""
    end

    --- Count note field tables related to the original current sentence.
    function private.count_matching_notes(note_fields, current_sentence, field_name)
        return h.reduce(note_fields, function(matching_count, fields)
            if public.sentences_are_related(current_sentence, private.sentence_field(fields, field_name)) then
                return matching_count + 1
            end
            return matching_count
        end)
    end

    --- Return whether two nonempty sentence fields share normalized sentence content.
    function public.sentences_are_related(first_sentence, second_sentence)
        first_sentence = h.normalize_html_text(first_sentence)
        second_sentence = h.normalize_html_text(second_sentence)
        return not h.is_empty(first_sentence)
            and not h.is_empty(second_sentence)
            and (h.is_substr(first_sentence, second_sentence) or h.is_substr(second_sentence, first_sentence))
    end

    --- Return a warning unless every supplied note matches the current sentence.
    function public.current_subtitle_warning(note_fields, current_sentence, field_name)
        -- Keep the original input for comparisons so decoded literal tags are never stripped again.
        if h.is_empty(h.normalize_html_text(current_sentence)) then
            return string.format("Couldn't verify the current subtitle against target notes' %s field.", field_name)
        end
        local matching_count = private.count_matching_notes(note_fields, current_sentence, field_name)
        if matching_count == #note_fields then
            return nil
        end
        if #note_fields == 1 then
            return string.format("The target note's %s does not match the current subtitle.", field_name)
        end
        return string.format(
            "Only %i of %i target notes have %s matching the current subtitle.",
            matching_count,
            #note_fields,
            field_name
        )
    end

    return public
end

return { new = make_note_update_guard }
