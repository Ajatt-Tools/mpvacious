--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Test helpers.
]]

local h = require('helpers')
local utils = require('mp.utils')

local function make_islice_cases()
    return {
        { input = { 1, 2, 3 }, expected = { 1, 2, 3 } },
        { input = { 1, 2, 3 }, start_pos = 2, expected = { 2, 3 } },
        { input = { 1, 2, 3 }, start_pos = 2, end_pos = 2, expected = { 2 } },
        { input = { 1, 2, 3 }, start_pos = 2, end_pos = 99, expected = { 2, 3 } },
        { input = { 1, 2, 3 }, start_pos = 99, expected = {} },
        { input = { 1, 2, 3 }, start_pos = 1, end_pos = 0, expected = {} },
        { input = { 1, 2, 3 }, start_pos = -2, expected = { 2, 3 } },
        { input = { 1, 2, 3 }, start_pos = -1, expected = { 3 } },
        { input = { 1, 2, 3 }, start_pos = 1, end_pos = -2, expected = { 1, 2 } },
        { input = { 1, 2, 3 }, start_pos = -3, end_pos = -1, expected = { 1, 2, 3 } },
        { input = { 1, 2, 3 }, start_pos = -99, expected = { 1, 2, 3 } },
        { input = { 1, 2, 3 }, start_pos = 1, end_pos = -99, expected = {} },
        { input = { 1, 2, 3 }, start_pos = 1.5, expected = { 2, 3 } },
        { input = { 1, 2, 3 }, start_pos = 1, end_pos = 2.5, expected = { 1, 2 } },
        { input = { 1, 2, 3 }, start_pos = 1.5, end_pos = 2.5, expected = { 2 } },
    }
end

local function test_islice()
    for _, case in ipairs(make_islice_cases()) do
        h.assert_equals(h.itable_slice(case.input, case.start_pos, case.end_pos), case.expected)
    end
end

local function make_list_equal_cases()
    return {
        { { 1, 2, 3 }, { 1, 2, 3 }, true }, -- identical lists
        { { 1, 2 }, { 1, 2, 3 }, false }, -- different lengths
        { { 1, 2, 3 }, { 1, 2 }, false }, -- different lengths, other direction
        { { 1, 2, 3 }, { 1, 9, 3 }, false }, -- same length, different element
        { {}, {}, true }, -- both empty
        { { "a", "b" }, { "a", "b" }, true }, -- string elements
        { { "a" }, { "A" }, false }, -- exact (case-sensitive) match
        { { 1, 2 }, { 2, 1 }, false }, -- order matters
    }
end

local function test_list_equal()
    for _, case in ipairs(make_list_equal_cases()) do
        local first, second, expected = h.unpack(case)
        h.assert_equals(h.list_equal(first, second), expected)
    end
end

local function make_equal_table_values_cases(reordered, note_info)
    local shared = { value = 'same' }
    return {
        { first = note_info, last = reordered, expected = true },
        { first = reordered, last = note_info, expected = true },
        { first = note_info, last = { noteId = 2, fields = { Sentence = { value = 'changed' } } }, expected = false },
        { first = note_info, last = { noteId = 2, fields = note_info.fields, extra = true }, expected = false },
        { first = { 1, 2 }, last = { 2, 1 }, expected = false },
        { first = { false }, last = { {} }, expected = false },
        { first = { a = shared, b = shared }, last = { a = { value = 'same' }, b = { value = 'same' } },
          expected = true },
        { first = false, last = nil, expected = false },
        { first = nil, last = nil, expected = true },
    }
end

--- Verify table equality ignores object-key order but respects values and array order.
local function test_equal_table_values()
    local note_info = { noteId = 2, fields = { Sentence = { value = 'second' }, Audio = { value = '' } } }
    local reordered = { fields = { Audio = { value = '' }, Sentence = { value = 'second' } }, noteId = 2 }
    h.assert_equals(reordered, note_info)
    for _, case in ipairs(make_equal_table_values_cases(reordered, note_info)) do
        h.assert_equals(h.equal(case.first, case.last), case.expected)
    end
end

local function make_is_non_empty_str_cases()
    return {
        { value = '/anki/media', expected = true },
        { value = ' ', expected = true },
        { value = '', expected = false },
        { value = nil, expected = false },
        { value = 42, expected = false },
        { value = false, expected = false },
        { value = {}, expected = false },
    }
end

--- Verify only nonempty strings satisfy the media-path boundary check.
local function test_is_non_empty_str()
    for _, case in ipairs(make_is_non_empty_str_cases()) do
        h.assert_equals(h.is_non_empty_str(case.value), case.expected)
    end
end

local function make_normalize_newlines_cases()
    return {
        { "a\r\nb", "a\nb" },
        { "a\rb", "a\nb" },
        { "a\r\nb\rc", "a\nb\nc" },
        { "a\nb", "a\nb" },
    }
end

local function test_normalize_newlines()
    for _, case in ipairs(make_normalize_newlines_cases()) do
        local text, expected = h.unpack(case)
        h.assert_equals(h.normalize_newlines(text), expected)
    end
end

local function make_split_line_cases()
    return {
        { "a\nb", { "a", "b" } },
        { "a\n", { "a", "" } },
        { "", { "" } },
        { "\n", { "", "" } },
    }
end

local function test_split_lines()
    for _, case in ipairs(make_split_line_cases()) do
        local text, expected = h.unpack(case)
        h.assert_equals(h.split_lines(text), expected)
    end
end

local function make_limit_lines_cases()
    return {
        -- {lines, max_lines, expected}
        { { "a", "b" }, 3, { "a", "b" } }, -- under the limit: unchanged
        { { "a", "b" }, 2, { "a", "b" } }, -- exactly at the limit: unchanged
        { { "a", "b", "c" }, 2, { "a", "b…" } }, -- over the limit: capped, ellipsis on the last kept line
        { { "a", "b", "c" }, 1, { "a…" } }, -- limit of one line
        { {}, 2, {} }, -- empty input
    }
end

local function test_limit_lines()
    for _, case in ipairs(make_limit_lines_cases()) do
        local lines, max_lines, expected = h.unpack(case)
        h.assert_equals(h.limit_lines(lines, max_lines), expected)
    end
end

local function make_str_wrap_cases()
    return {
        { text = "short", n_chars = 25, separator = [[\N]], expected = "short" },
        { text = "abcdef", n_chars = 3, separator = [[\N]], expected = [[abc\Ndef]] },
        { text = "one two three", n_chars = 6, separator = [[\N]], expected = [[one\Ntwo\Nthree]] },
        { text = "like them.", n_chars = 9, separator = [[\N]], expected = [[like\Nthem.]] },
        { text = " abc def", n_chars = 4, separator = [[\N]], expected = [[abc\Ndef]] },
        { text = "ab cdefgh", n_chars = 3, separator = [[\N]], expected = [[ab\Ncde\Nfgh]] },
        { text = "一二三四五六", n_chars = 6, separator = [[\N]], expected = [[一二三\N四五六]] },
        { text = "ab一二cd", n_chars = 6, separator = [[\N]], expected = [[ab一二\Ncd]] },
        { text = "一二\n三四", n_chars = 6, separator = [[\N]], expected = [[一二\N三四]] },
        { text = "Привет", n_chars = 3, separator = [[\N]], expected = [[При\Nвет]] },
        { text = "", n_chars = 6, separator = [[\N]], expected = "" },
        { text = "一", n_chars = 1, separator = [[\N]], expected = "一" },
        { text = "a\n\nb", n_chars = 6, separator = [[\N]], expected = [[a\N\Nb]] },
        { text = "a\n", n_chars = 6, separator = [[\N]], expected = [[a\N]] },
        { text = "\na", n_chars = 6, separator = [[\N]], expected = [[\Na]] },
        { text = "abcdef", n_chars = 3, expected = "abc\ndef" },
    }
end

local function test_str_wrap()
    for _, case in ipairs(make_str_wrap_cases()) do
        h.assert_equals(h.str_wrap(case.text, case.n_chars, case.separator), case.expected)
    end
end

local function make_trim_cases()
    return {
        { "  hello  ", "hello" },
        { "　hello　", "hello" },
        { " (note) hello ", "hello" },
        { "a \n b", "a b" },
        { "a  b", "a b" },
    }
end

local function test_trim()
    for _, case in ipairs(make_trim_cases()) do
        local text, expected = h.unpack(case)
        h.assert_equals(h.trim(text), expected)
    end
end

local function make_normalized_subtitle_text_cases()
    return {
        { "<b>現実味</b>", "現実味" },
        { "a　b", "a b" },
        { "a\194\160b", "a b" },
        { "a\226\128\175b", "a b" },
        { "a\226\128\139b", "ab" },
        { "\239\187\191ab", "ab" },
        { "『お』", '"お"' },
        { "「お」", '"お"' },
        { "“お”", '"お"' },
        { "〝お〟", '"お"' },
        { "＂お＂", '"お"' },
        { "  a\t\nb  ", "a b" },
        { "女の子の <b>女性</b>の　『お』から始まる…", "女の子の 女性の \"お\"から始まる…" },
    }
end

local function test_normalize_subtitle_text()
    for _, case in ipairs(make_normalized_subtitle_text_cases()) do
        local text, expected = h.unpack(case)
        h.assert_equals(h.normalize_subtitle_text(text), expected)
    end
end

local function test_is_substr()
    -- Test is_substr
    h.assert_equals(h.is_substr("abcd", "bc"), true)
    h.assert_equals(h.is_substr("abcd", "xyz"), false)
    h.assert_equals(h.is_substr("abcd", "^.*d.*$"), false)
end

local function test_str_contains()
    -- Test str_contains
    h.assert_equals(h.str_contains("abcd", "^.*d.*$"), true)
    h.assert_equals(h.str_contains("abcd", "^.*z.*$"), false)
end

local function test_collapse_whitespace()
    -- Test collapse_whitespace
    h.assert_equals(h.collapse_whitespace("a  b"), "a b")
    h.assert_equals(h.collapse_whitespace("a\tb"), "a b")
    h.assert_equals(h.collapse_whitespace("a\nb"), "a b")
    h.assert_equals(h.collapse_whitespace("a\r\nb"), "a b")
    h.assert_equals(h.collapse_whitespace("a \t \n b"), "a b")
end

local function test_unescape_special_characters()
    -- Test unescape_special_characters
    h.assert_equals(h.unescape_special_characters("that&apos;s"), "that's")
    h.assert_equals(h.unescape_special_characters("that&#39;s &amp; &quot;ok&quot;"), "that's & \"ok\"")
    h.assert_equals(h.unescape_special_characters("&lt;tag&gt;"), "<tag>")
end

local function test_escape_special_characters()
    -- Test escape_special_characters
    h.assert_equals(h.escape_special_characters("that's"), "that&apos;s")
    h.assert_equals(h.escape_special_characters("that's & \"ok\""), "that&apos;s &amp; &quot;ok&quot;")
    h.assert_equals(h.escape_special_characters("<tag>"), "&lt;tag&gt;")
    h.assert_equals(h.escape_special_characters('&"\'<>'), "&amp;&quot;&apos;&lt;&gt;")
    h.assert_equals(h.escape_special_characters("a<b&c"), "a&lt;b&amp;c")
    h.assert_equals(h.escape_special_characters("&amp;"), "&amp;")
    h.assert_equals(h.escape_special_characters("hello world"), "hello world")
    h.assert_equals(h.escape_special_characters(""), "")
    -- Round-trip: unescape(escape(text)) should return the original text.
    h.assert_equals(h.unescape_special_characters(h.escape_special_characters("that's & \"ok\"")), "that's & \"ok\"")
    -- Idempotency: escaping an already-escaped string should be a no-op.
    h.assert_equals(h.escape_special_characters(h.escape_special_characters("that's & \"ok\"")), "that&apos;s &amp; &quot;ok&quot;")
end

local function make_ep_num_cases()
    return {
        { filename = "A Whisker Away.mkv", expected = nil },
        { filename = "[Placeholder] Gekijouban SHIROBAKO [Ma10p_1080p][x265_flac]", expected = nil },
        { filename = "[Placeholder] Sono Bisque Doll wa Koi wo Suru - 06 [54E495D0]", expected = "06" },
        { filename = "(Hi10)_Kobayashi-san_Chi_no_Maid_Dragon_-_02_(BD_1080p)_(Placeholder)_(12C5D2B4)", expected = "02" },
        { filename = "[Placeholder] Koi to Yobu ni wa Kimochi Warui - 01 (1080p) [D517C9F0]", expected = "01" },
        { filename = "[Placeholder] Tsukimonogatari 01 [BD 1080p x264 10-bit FLAC] [5CD88145]", expected = "01" },
        { filename = "[Placeholder] 86 - Eighty Six - 01 (1080p) [1B13598F]", expected = "01" },
        { filename = "[Placeholder] Fate Stay Night - Unlimited Blade Works - 00 (BD 1080p Hi10 FLAC) [95590B7F]", expected = "00" },
        { filename = "House, M.D. S01E01 Pilot - Everybody Lies (1080p x265 Placeholder)", expected = "01" },
        { filename = "A Generic Episode-165", expected = "165" },
    }
end

local function test_get_episode_number()
    -- Test get_episode_number
    -- Use records instead of a filename → expected map because Lua table entries
    -- with nil values do not exist. Keeping `expected = nil` inside a record lets
    -- us test filenames where no episode number should be found.
    for _, case in ipairs(make_ep_num_cases()) do
        local _, _, episode_num = h.get_episode_number(case.filename)
        h.assert_equals(episode_num, case.expected)
    end
end

local function test_shallow_copy()
    local t1 = { 1, 2, 3 }
    local t2 = { 3, 4, 5 }
    h.shallow_copy(t1, t2)
    h.assert_equals(t2, t1)
end

local function find_insertion_point_linear(list, new)
    for idx, value in ipairs(list) do
        if new < value then
            return idx
        end
    end
    return #list + 1
end

local function make_insertion_cases()
    return {
        { { 1, 2, 4, 5 }, 3, 3 },
        { { 1, 2, 4, 5 }, 99, 5 },
        { { 1, 2, 4, 5 }, 0, 1 },
        { { 1, 2, 4, 5 }, 2, 3 },
        { { 1, 2, 4, 5 }, 5, 5 },
        { {}, 5, 1 },
        { { 2, 2, 2, 2, 2, 2 }, 5, 7 },
    }
end

local function test_find_insertion_point()
    for _, case in ipairs(make_insertion_cases()) do
        local list, new_value, expected = h.unpack(case)
        local r1 = find_insertion_point_linear(list, new_value)
        local r2 = h.find_insertion_point(list, new_value)
        h.assert_equals(r1, r2)
        h.assert_equals(r2, expected)
    end
end

local function test_adjacent_items()
    local function _items(items)
        local ret = {}
        for _, val in ipairs(items) do
            table.insert(ret, val.item)
        end
        return ret
    end
    h.assert_equals(_items(h.adjacent_items({ 1, 2, 3 }, 2, 1, 1)), { 1, 2, 3 })
    h.assert_equals(_items(h.adjacent_items({ 1, 2, 3 }, 2, 10, 10)), { 1, 2, 3 })
    h.assert_equals(_items(h.adjacent_items({ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 }, 10, 4, 4)), { 2, 3, 4, 5, 6, 7, 8, 9, 10 })
    h.assert_equals(_items(h.adjacent_items({ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 }, 9, 3, 3)), { 4, 5, 6, 7, 8, 9, 10 })
    h.assert_equals(_items(h.adjacent_items({ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 }, 1, 3, 3)), { 1, 2, 3, 4, 5, 6, 7 })
end

local function test_dirs()
    -- GNU only:
    if h.is_gnu() then
        h.assert_equals(h.find_mpv_scripts_dir(), utils.join_path(os.getenv("HOME") or "~", '.config/mpv/scripts'))
        h.assert_equals(h.find_mpv_config_directory(), utils.join_path(os.getenv("HOME") or "~", '.config/mpv'))
    end
end

local function test_str_limit()
    -- Test str limit
    h.assert_equals(h.str_limit("abc", 3), "abc")
    h.assert_equals(h.str_limit("abcd", 3), "abc…")
    h.assert_equals(h.str_limit("報連相", 3), "報連相")
    h.assert_equals(h.str_limit("報連相", 2), "報連…")
    h.assert_equals(h.str_limit("報連相", 1), "報…")
    h.assert_equals(h.str_limit("報連相", 33), "報連相")
    h.assert_equals(h.str_limit("報連a", 2), "報連…") -- one narrow char remains after the cut
end

local function test_str_limit_width()
    -- Test str_limit_width: CJK counts double, narrower chars count once.
    h.assert_equals(h.str_limit_width("abc", 3), "abc")
    h.assert_equals(h.str_limit_width("abcd", 3), "abc…")
    h.assert_equals(h.str_limit_width("報連相", 3), "報…") -- 2 widths each, exceeds 3
    h.assert_equals(h.str_limit_width("報連", 4), "報連")
    h.assert_equals(h.str_limit_width("ab報", 4), "ab報")
    h.assert_equals(h.str_limit_width("ab報c", 4), "ab報…")
    h.assert_equals(h.str_limit_width("", 3), "")
    h.assert_equals(h.str_limit_width("報連相", 6, 3), "報連…") -- wide_char_width=3: two fit, third exceeds
    h.assert_equals(h.str_limit_width("ЯЯЯЯ", 3), "ЯЯЯ…") -- 2-byte chars count as narrow
end

local function test_clamp()
    -- Test clamp
    h.assert_equals(h.clamp(5, 1, 10), 5)
    h.assert_equals(h.clamp(0, 1, 10), 1)
    h.assert_equals(h.clamp(-100, 1, 10), 1)
    h.assert_equals(h.clamp(11, 1, 10), 10)
    h.assert_equals(h.clamp(1, 1, 10), 1)
    h.assert_equals(h.clamp(10, 1, 10), 10)
end

local function test_version_needs_update()
    -- Test version comparison
    h.assert_equals(h.version_needs_update("v1.0.0", "v1.0.0"), nil)
    h.assert_equals(h.version_needs_update("v1.0.0", "v1.0.1"), false)
    h.assert_equals(h.version_needs_update("v1.0.1", "v1.0.0"), true)
    h.assert_equals(h.version_needs_update("v1.10.0", "v1.9.0"), true)
    h.assert_equals(h.version_needs_update("v2.0.0", "v1.99.99"), true)
    h.assert_equals(h.version_needs_update("v1.0", "v1.0.0"), nil)
    h.assert_equals(h.version_needs_update("v1", "v1.0.0"), nil)
    h.assert_equals(h.version_needs_update("v26.1.30.0", "v26.1.30.1"), false)
end

local function test_join_two_sorted_lists()
    -- Test join_two_sorted_lists
    h.assert_equals(h.join_two_sorted_lists({ 1, 3, 5 }, { 2, 4, 6 }), { 1, 2, 3, 4, 5, 6 })
    h.assert_equals(h.join_two_sorted_lists({ 1, 2, 3 }, { 4, 5, 6 }), { 1, 2, 3, 4, 5, 6 })
    h.assert_equals(h.join_two_sorted_lists({ 4, 5, 6 }, { 1, 2, 3 }), { 1, 2, 3, 4, 5, 6 })
    h.assert_equals(h.join_two_sorted_lists({ 1, 3, 5 }, {}), { 1, 3, 5 })
    h.assert_equals(h.join_two_sorted_lists({}, { 2, 4, 6 }), { 2, 4, 6 })
    h.assert_equals(h.join_two_sorted_lists({}, {}), {})
    h.assert_equals(h.join_two_sorted_lists({ 1 }, { 2 }), { 1, 2 })
    h.assert_equals(h.join_two_sorted_lists({ 1, 1, 2 }, { 1, 3, 3 }), { 1, 1, 1, 2, 3, 3 })
end

local function test_remove_html_tags()
    -- Test h.remove_html_tags(str)
    h.assert_equals(h.remove_html_tags("ヤツらの声に<b>現実味</b>が…"), "ヤツらの声に現実味が…")
    h.assert_equals(h.remove_html_tags("ヤツらの声に<span>現実味</span>が…"), "ヤツらの声に現実味が…")
    h.assert_equals(h.remove_html_tags("<b><b><b><b>"), "")
    h.assert_equals(h.remove_html_tags("<a href=\"test\">test</a>"), "test")
end

local function test_str_replace()
    -- Test str_replace
    h.assert_equals(h.str_replace("a.b.a", ".", "-"), "a-b-a")
    h.assert_equals(h.str_replace("ababab", "ab", "x", 2), "xxab")
    h.assert_equals(h.str_replace("%w%w%w", "%w", "_"), "___")
    h.assert_equals(h.str_replace("abcdef", "%w", "_"), "abcdef")
    h.assert_equals(h.str_replace("メイド喫茶", "メイド", "冥土"), "冥土喫茶")
end

local function run_tests()
    test_is_substr()
    test_str_contains()
    test_collapse_whitespace()
    test_trim()
    test_normalize_subtitle_text()
    test_unescape_special_characters()
    test_escape_special_characters()
    test_get_episode_number()
    h.assert_equals(h.join_lists({ 1, 2 }, { 3 }, {}, { 4, 5 }), { 1, 2, 3, 4, 5 })
    test_list_equal()
    test_equal_table_values()
    test_is_non_empty_str()
    test_shallow_copy()
    test_find_insertion_point()
    test_adjacent_items()
    test_islice()
    test_dirs()
    test_str_limit()
    test_str_limit_width()
    test_normalize_newlines()
    test_split_lines()
    test_limit_lines()
    test_str_wrap()
    test_clamp()
    test_version_needs_update()
    test_join_two_sorted_lists()
    test_remove_html_tags()
    test_str_replace()
end

return {
    run_tests = run_tests,
}
