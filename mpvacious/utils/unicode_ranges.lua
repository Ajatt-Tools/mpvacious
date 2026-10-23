-- Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
-- License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

-- Script=Latin or Script=Han/Hiragana/Katakana/Hangul intersected with
-- General_Category=L* in Unicode 17.0. Blocks also contain other scripts,
-- punctuation, and unassigned positions, so intentional gaps must be preserved.
-- https://www.unicode.org/Public/17.0.0/ucd/Scripts.txt
-- https://www.unicode.org/Public/17.0.0/ucd/UnicodeData.txt
-- Block names below describe the ranges. The normative block boundaries are at:
-- https://www.unicode.org/Public/17.0.0/ucd/Blocks.txt

local Range = require("utils.range")
local h = require("helpers")

-- Basic Latin uppercase A-Z and lowercase a-z.
-- https://en.wikipedia.org/wiki/Basic_Latin_(Unicode_block)
local basic_latin = {
    -- U+0041-U+005A: Basic Latin uppercase A through Z.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L645
    Range:new { from = 0x0041, to = 0x005A },

    -- U+0061-U+007A: Basic Latin lowercase a through z.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L646
    Range:new { from = 0x0061, to = 0x007A },
}

-- Latin-1 Supplement, excluding multiplication and division signs.
-- https://en.wikipedia.org/wiki/Latin-1_Supplement
local latin_1_supplement_letters = {
    -- U+00AA: the feminine ordinal indicator (ª), classified as a Latin letter.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L647
    Range:new { from = 0x00AA, to = 0x00AA },

    -- U+00BA: the masculine ordinal indicator (º), classified as a Latin letter.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L648
    Range:new { from = 0x00BA, to = 0x00BA },

    -- U+00C0-U+00D6: Latin-1 capitals À through Ö, stopping before multiplication sign U+00D7.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L649
    Range:new { from = 0x00C0, to = 0x00D6 },

    -- U+00D8-U+00F6: Latin-1 letters Ø through ö, stopping before division sign U+00F7.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L650
    Range:new { from = 0x00D8, to = 0x00F6 },
}

-- Remaining Latin-1, Extended-A/B, IPA Extensions, and Spacing Modifier Letters.
-- The first range merges adjacent Latin letters across these block boundaries.
-- https://en.wikipedia.org/wiki/Latin-1_Supplement
-- https://en.wikipedia.org/wiki/Latin_Extended-A
-- https://en.wikipedia.org/wiki/Latin_Extended-B
-- https://en.wikipedia.org/wiki/IPA_Extensions
-- https://en.wikipedia.org/wiki/Spacing_Modifier_Letters
local latin_extended_and_ipa_letters = {
    -- U+00F8-U+02B8: ø through modifier small y, merging eight adjacent Latin-letter records.
    -- Spans Latin-1, Extended-A/B, IPA Extensions, and modifier letters without a gap.
    -- U+02B9 begins Common-script modifier letters, which are not Latin-script letters.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L651-L658
    Range:new { from = 0x00F8, to = 0x02B8 },

    -- U+02E0-U+02E4: Latin modifier letters from small gamma through small reversed glottal stop.
    -- The neighboring characters are Common-script accent/tone symbols.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L659
    Range:new { from = 0x02E0, to = 0x02E4 },
}

-- Phonetic Extensions and Phonetic Extensions Supplement, excluding other scripts.
-- https://en.wikipedia.org/wiki/Phonetic_Extensions
-- https://en.wikipedia.org/wiki/Phonetic_Extensions_Supplement
local latin_phonetic_extensions = {
    -- U+1D00-U+1D25: phonetic Latin letters from small capital A through ain.
    -- U+1D26-U+1D2B belong to Greek and Cyrillic, not Latin.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L660
    Range:new { from = 0x1D00, to = 0x1D25 },

    -- U+1D2C-U+1D5C: Latin modifier letters from capital A through small ain.
    -- Stops before the Greek modifier letters U+1D5D-U+1D61.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L661
    Range:new { from = 0x1D2C, to = 0x1D5C },

    -- U+1D62-U+1D65: Latin subscript small i, r, u, and v.
    -- Stops before Greek subscript letters U+1D66-U+1D6A.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L662
    Range:new { from = 0x1D62, to = 0x1D65 },

    -- U+1D6B-U+1D77: phonetic Latin small letters from ue through turned g.
    -- U+1D78 is a Cyrillic modifier letter and is excluded.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L663
    Range:new { from = 0x1D6B, to = 0x1D77 },

    -- U+1D79-U+1DBE: Latin insular g through modifier small ezh, merging two adjacent letter records.
    -- U+1DBF is Greek modifier small theta and is excluded.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L664-L665
    Range:new { from = 0x1D79, to = 0x1DBE },
}

-- Latin Extended Additional, including Vietnamese letters.
-- https://en.wikipedia.org/wiki/Latin_Extended_Additional
local latin_extended_additional = {
    -- U+1E00-U+1EFF: the complete assigned Latin Extended Additional letter range.
    -- Runs from capital A with ring below through small y with loop, including Vietnamese letters.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L666
    Range:new { from = 0x1E00, to = 0x1EFF },
}

-- Superscripts/Subscripts, Letterlike Symbols, and Latin letters in Number Forms.
-- https://en.wikipedia.org/wiki/Superscripts_and_Subscripts_(Unicode_block)
-- https://en.wikipedia.org/wiki/Letterlike_Symbols
-- https://en.wikipedia.org/wiki/Number_Forms
local latin_superscripts_and_letter_forms = {
    -- U+2071: superscript Latin small i, a letter rather than a superscript digit.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L667
    Range:new { from = 0x2071, to = 0x2071 },

    -- U+207F: superscript Latin small n, separate from the preceding superscript symbols.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L668
    Range:new { from = 0x207F, to = 0x207F },

    -- U+2090-U+209C: the assigned Latin subscript letters from small a through small t.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L669
    Range:new { from = 0x2090, to = 0x209C },

    -- U+212A-U+212B: Kelvin and Angstrom signs, both classified as Latin uppercase letters.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L670
    Range:new { from = 0x212A, to = 0x212B },

    -- U+2132: turned capital F, classified as a Latin uppercase letter.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L671
    Range:new { from = 0x2132, to = 0x2132 },

    -- U+214E: turned small f, classified as a Latin lowercase letter.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L672
    Range:new { from = 0x214E, to = 0x214E },

    -- U+2183-U+2184: reversed C forms, classified as Latin letters despite the Number Forms block.
    -- The neighboring Roman numeral-category records are not included.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L674
    Range:new { from = 0x2183, to = 0x2184 },
}

-- Latin Extended-C.
-- https://en.wikipedia.org/wiki/Latin_Extended-C
local latin_extended_c = {
    -- U+2C60-U+2C7F: Latin Extended-C letters from capital l with double bar through capital z with swash tail.
    -- Merges three adjacent lowercase/uppercase/modifier letter records.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L676-L678
    Range:new { from = 0x2C60, to = 0x2C7F },
}

-- Latin Extended-D letters, excluding symbols and unassigned positions.
-- https://en.wikipedia.org/wiki/Latin_Extended-D
local latin_extended_d = {
    -- U+A722-U+A787: Latin Egyptological alef through small insular t, merging three letter records.
    -- Excludes preceding tone symbols and the following Common-script characters U+A788-U+A78A.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L679-L681
    Range:new { from = 0xA722, to = 0xA787 },

    -- U+A78B-U+A7DC: Latin capital saltillo through capital lambda with stroke.
    -- Merges three letter records and stops before unassigned U+A7DD-U+A7F0.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L682-L684
    Range:new { from = 0xA78B, to = 0xA7DC },

    -- U+A7F1-U+A7FF: assigned Latin modifier and epigraphic letters after the unassigned gap.
    -- Runs from modifier capital s through epigraphic archaic m, merging six letter records.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L685-L690
    Range:new { from = 0xA7F1, to = 0xA7FF },
}

-- Latin Extended-E letters. U+AB65 is Greek, not Latin.
-- https://en.wikipedia.org/wiki/Latin_Extended-E
local latin_extended_e = {
    -- U+AB30-U+AB5A: Latin small barred alpha through small y with short right leg.
    -- Stops before Common-script modifier symbol U+AB5B.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L691
    Range:new { from = 0xAB30, to = 0xAB5A },

    -- U+AB5C-U+AB64: Latin modifier small heng through small inverted alpha, merging two records.
    -- Stops before Greek small capital omega U+AB65.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L692-L693
    Range:new { from = 0xAB5C, to = 0xAB64 },

    -- U+AB66-U+AB69: Latin retroflex-hook dz digraph through modifier small turned w.
    -- Merges two records after Greek U+AB65 and stops before Common-script symbols U+AB6A-U+AB6B.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L694-L695
    Range:new { from = 0xAB66, to = 0xAB69 },
}

-- Alphabetic Presentation Forms ligatures and fullwidth Latin letters.
-- https://en.wikipedia.org/wiki/Alphabetic_Presentation_Forms
-- https://en.wikipedia.org/wiki/Halfwidth_and_Fullwidth_Forms_(Unicode_block)
local latin_presentation_and_fullwidth_letters = {
    -- U+FB00-U+FB06: the seven Latin presentation ligatures from ff through st.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L696
    Range:new { from = 0xFB00, to = 0xFB06 },

    -- U+FF21-U+FF3A: fullwidth Latin uppercase A through Z, excluding neighboring punctuation.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L697
    Range:new { from = 0xFF21, to = 0xFF3A },

    -- U+FF41-U+FF5A: fullwidth Latin lowercase a through z, excluding neighboring punctuation.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L698
    Range:new { from = 0xFF41, to = 0xFF5A },
}

-- Supplementary Latin Extended-F and G.
-- https://en.wikipedia.org/wiki/Latin_Extended-F
-- https://en.wikipedia.org/wiki/Latin_Extended-G
local supplementary_latin = {
    -- U+10780-U+10785: Latin modifier small capital aa through small b with hook.
    -- Stops before unassigned U+10786, rather than covering the entire Extended-F block.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L699
    Range:new { from = 0x10780, to = 0x10785 },

    -- U+10787-U+107B0: Latin modifier small dz digraph through small v with right hook.
    -- Lies between unassigned U+10786 and U+107B1.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L700
    Range:new { from = 0x10787, to = 0x107B0 },

    -- U+107B2-U+107BA: Latin modifier small capital y through small s with curl.
    -- The remaining Extended-F positions U+107BB-U+107BF are unassigned.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L701
    Range:new { from = 0x107B2, to = 0x107BA },

    -- U+1DF00-U+1DF1E: Latin feng digraph with trill through small s with curl, merging three records.
    -- Stops before unassigned U+1DF1F-U+1DF24.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L702-L704
    Range:new { from = 0x1DF00, to = 0x1DF1E },

    -- U+1DF25-U+1DF2A: six Latin small letters with mid-height left hooks, from d through t.
    -- These are the last assigned letters in Extended-G in Unicode 17.0.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L705
    Range:new { from = 0x1DF25, to = 0x1DF2A },
}

-- Hangul Jamo, Compatibility Jamo, Extended-A/B, and precomposed syllables.
-- Hangul Jamo: https://www.unicode.org/charts/PDF/U1100.pdf
-- Hangul Compatibility Jamo: https://www.unicode.org/charts/PDF/U3130.pdf
-- Hangul Jamo Extended-A: https://www.unicode.org/charts/PDF/UA960.pdf
-- Hangul Syllables: https://www.unicode.org/charts/PDF/UAC00.pdf
-- Hangul Jamo Extended-B: https://www.unicode.org/charts/PDF/UD7B0.pdf
local hangul_jamo_and_syllables = {
    -- U+1100-U+11FF: Hangul Jamo letters from choseong kiyeok through jongseong ssangnieun.
    -- Every position in this block is an assigned Hangul letter.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L1406
    Range:new { from = 0x1100, to = 0x11FF },

    -- U+3131-U+318E: assigned Hangul compatibility letters from kiyeok through araeae.
    -- Excludes unassigned positions at either end of the surrounding block.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L1408
    Range:new { from = 0x3131, to = 0x318E },

    -- U+A960-U+A97C: assigned Hangul Jamo Extended-A initial consonants.
    -- Runs from choseong tikeut-mieum through ssangyeorinhieuh, before the block's unassigned tail.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L1411
    Range:new { from = 0xA960, to = 0xA97C },

    -- U+AC00-U+D7A3: all 11,172 assigned precomposed Hangul syllables.
    -- Stops at the last assigned syllable, not the block boundary U+D7AF.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L1412
    Range:new { from = 0xAC00, to = 0xD7A3 },

    -- U+D7B0-U+D7C6: Hangul Jamo Extended-B vowels from jungseong o-yeo through araea-e.
    -- Stops before the unassigned gap U+D7C7-U+D7CA.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L1413
    Range:new { from = 0xD7B0, to = 0xD7C6 },

    -- U+D7CB-U+D7FB: Hangul Jamo Extended-B final consonants after the unassigned gap.
    -- Runs from jongseong nieun-rieul through phieuph-thieuth, before the block's unassigned tail.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L1414
    Range:new { from = 0xD7CB, to = 0xD7FB },
}

-- Halfwidth Hangul letters, excluding unassigned gaps.
-- Halfwidth and Fullwidth Forms: https://www.unicode.org/charts/PDF/UFF00.pdf
local halfwidth_hangul = {
    -- U+FFA0-U+FFBE: halfwidth Hangul filler and consonants, ending at letter hieuh.
    -- Stops before unassigned U+FFBF-U+FFC1.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L1415
    Range:new { from = 0xFFA0, to = 0xFFBE },

    -- U+FFC2-U+FFC7: assigned halfwidth Hangul vowels from a through e.
    -- Stops before unassigned U+FFC8-U+FFC9.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L1416
    Range:new { from = 0xFFC2, to = 0xFFC7 },

    -- U+FFCA-U+FFCF: assigned halfwidth Hangul vowels from yeo through oe.
    -- Stops before unassigned U+FFD0-U+FFD1.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L1417
    Range:new { from = 0xFFCA, to = 0xFFCF },

    -- U+FFD2-U+FFD7: assigned halfwidth Hangul vowels from yo through yu.
    -- Stops before unassigned U+FFD8-U+FFD9.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L1418
    Range:new { from = 0xFFD2, to = 0xFFD7 },

    -- U+FFDA-U+FFDC: the final three halfwidth Hangul vowels eu, yi, and i.
    -- U+FFDD-U+FFDF are unassigned, and the following assigned characters are symbols.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L1419
    Range:new { from = 0xFFDA, to = 0xFFDC },
}

-- Hiragana and supplementary Kana Supplement/Extended-A/Small Kana Extension.
-- Hiragana: https://www.unicode.org/charts/PDF/U3040.pdf
-- Kana Supplement: https://www.unicode.org/charts/PDF/U1B000.pdf
-- Kana Extended-A: https://www.unicode.org/charts/PDF/U1B100.pdf
-- Small Kana Extension: https://www.unicode.org/charts/PDF/U1B130.pdf
local hiragana = {
    -- U+3041-U+3096: Hiragana letters from small a through small ke.
    -- Excludes unassigned U+3097-U+3098 and the following combining/symbol sound marks.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L1550
    Range:new { from = 0x3041, to = 0x3096 },

    -- U+309D-U+309F: Hiragana iteration mark, voiced iteration mark, and digraph yori.
    -- Merges adjacent modifier-letter and other-letter records after the sound marks.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L1551-L1552
    Range:new { from = 0x309D, to = 0x309F },

    -- U+1B001-U+1B11F: historical Hiragana and hentaigana from archaic ye through archaic wu.
    -- This continuous letter record spans Kana Supplement and Kana Extended-A.
    -- U+1B000 is Katakana, and U+1B120 starts the next Katakana range.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L1553
    Range:new { from = 0x1B001, to = 0x1B11F },

    -- U+1B132: Hiragana small ko, an isolated assigned letter in Small Kana Extension.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L1554
    Range:new { from = 0x1B132, to = 0x1B132 },

    -- U+1B150-U+1B152: Hiragana small wi, we, and wo, between unassigned gaps.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L1555
    Range:new { from = 0x1B150, to = 0x1B152 },
}

-- Katakana, Phonetic Extensions, and halfwidth Katakana.
-- Katakana: https://www.unicode.org/charts/PDF/U30A0.pdf
-- Katakana Phonetic Extensions: https://www.unicode.org/charts/PDF/U31F0.pdf
-- Halfwidth and Fullwidth Forms: https://www.unicode.org/charts/PDF/UFF00.pdf
local katakana = {
    -- U+30A1-U+30FA: Katakana letters from small a through vo.
    -- Excludes preceding punctuation and the following middle dot/prolonged sound mark.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L1562
    Range:new { from = 0x30A1, to = 0x30FA },

    -- U+30FD-U+30FF: Katakana iteration mark, voiced iteration mark, and digraph koto.
    -- Merges two letter records after Common-script U+30FB-U+30FC.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L1563-L1564
    Range:new { from = 0x30FD, to = 0x30FF },

    -- U+31F0-U+31FF: the complete assigned Katakana Phonetic Extensions range, small ku through small ro.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L1565
    Range:new { from = 0x31F0, to = 0x31FF },

    -- U+FF66-U+FF6F: halfwidth Katakana wo and small letters through small tu.
    -- Stops before Common-script prolonged sound mark U+FF70.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L1568
    Range:new { from = 0xFF66, to = 0xFF6F },

    -- U+FF71-U+FF9D: halfwidth Katakana a through n.
    -- Excludes the preceding prolonged sound mark and following Common-script voiced sound marks.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L1569
    Range:new { from = 0xFF71, to = 0xFF9D },
}

-- Kana Extended-B, Supplement, Extended-A, and Small Kana Extension.
-- Kana Extended-B: https://www.unicode.org/charts/PDF/U1AFF0.pdf
-- Kana Supplement: https://www.unicode.org/charts/PDF/U1B000.pdf
-- Kana Extended-A: https://www.unicode.org/charts/PDF/U1B100.pdf
-- Small Kana Extension: https://www.unicode.org/charts/PDF/U1B130.pdf
local supplementary_katakana = {
    -- U+1AFF0-U+1AFF3: Katakana Minnan tone letters 2 through 5.
    -- Stops before unassigned U+1AFF4.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L1570
    Range:new { from = 0x1AFF0, to = 0x1AFF3 },

    -- U+1AFF5-U+1AFFB: Katakana Minnan tone-7 through nasalized tone-5 letters.
    -- Lies between unassigned U+1AFF4 and U+1AFFC.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L1571
    Range:new { from = 0x1AFF5, to = 0x1AFFB },

    -- U+1AFFD-U+1AFFE: Katakana Minnan nasalized tone-7 and tone-8 letters.
    -- These two letters lie between unassigned U+1AFFC and U+1AFFF.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L1572
    Range:new { from = 0x1AFFD, to = 0x1AFFE },

    -- U+1B000: Katakana archaic e, immediately before the historical Hiragana range.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L1573
    Range:new { from = 0x1B000, to = 0x1B000 },

    -- U+1B120-U+1B122: Katakana archaic yi, ye, and wu, after the historical Hiragana range.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L1574
    Range:new { from = 0x1B120, to = 0x1B122 },

    -- U+1B155: Katakana small ko, an isolated assigned letter in Small Kana Extension.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L1575
    Range:new { from = 0x1B155, to = 0x1B155 },

    -- U+1B164-U+1B167: Katakana small wi, we, wo, and n, between unassigned gaps.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L1576
    Range:new { from = 0x1B164, to = 0x1B167 },
}

-- Han iteration marks, unified ideographs/Extension-A, and compatibility ideographs.
-- CJK Symbols and Punctuation: https://www.unicode.org/charts/PDF/U3000.pdf
-- CJK Unified Ideographs Extension A: https://www.unicode.org/charts/PDF/U3400.pdf
-- CJK Unified Ideographs: https://www.unicode.org/charts/PDF/U4E00.pdf
-- CJK Compatibility Ideographs: https://www.unicode.org/charts/PDF/UF900.pdf
local han_ideographs_and_iteration_marks = {
    -- U+3005: the ideographic iteration mark, classified as a Han modifier letter.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L1593
    Range:new { from = 0x3005, to = 0x3005 },

    -- U+303B: the vertical ideographic iteration mark, classified as a Han modifier letter.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L1597
    Range:new { from = 0x303B, to = 0x303B },

    -- U+3400-U+4DBF: all assigned CJK Unified Ideographs Extension-A letters.
    -- Both endpoints match the assigned ideograph record, not neighboring symbols or gaps.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L1598
    Range:new { from = 0x3400, to = 0x4DBF },

    -- U+4E00-U+9FFF: the complete assigned CJK Unified Ideographs range.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L1599
    Range:new { from = 0x4E00, to = 0x9FFF },

    -- U+F900-U+FA6D: the first assigned CJK Compatibility Ideographs range.
    -- Stops before unassigned U+FA6E-U+FA6F.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L1600
    Range:new { from = 0xF900, to = 0xFA6D },

    -- U+FA70-U+FAD9: the second assigned CJK Compatibility Ideographs range.
    -- Stops at the last assigned character, before unassigned U+FADA-U+FAFF.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L1601
    Range:new { from = 0xFA70, to = 0xFAD9 },
}

-- Ideographic Symbols and Punctuation letters, Extensions B through J,
-- and Compatibility Ideographs Supplement. Adjacent assigned ranges are merged.
-- Ideographic Symbols and Punctuation: https://www.unicode.org/charts/PDF/U16FE0.pdf
-- CJK Unified Ideographs Extension B: https://www.unicode.org/charts/PDF/U20000.pdf
-- CJK Unified Ideographs Extension C: https://www.unicode.org/charts/PDF/U2A700.pdf
-- CJK Unified Ideographs Extension D: https://www.unicode.org/charts/PDF/U2B740.pdf
-- CJK Unified Ideographs Extension E: https://www.unicode.org/charts/PDF/U2B820.pdf
-- CJK Unified Ideographs Extension F: https://www.unicode.org/charts/PDF/U2CEB0.pdf
-- CJK Unified Ideographs Extension I: https://www.unicode.org/charts/PDF/U2EBF0.pdf
-- CJK Compatibility Ideographs Supplement: https://www.unicode.org/charts/PDF/U2F800.pdf
-- CJK Unified Ideographs Extension G: https://www.unicode.org/charts/PDF/U30000.pdf
-- CJK Unified Ideographs Extension H: https://www.unicode.org/charts/PDF/U31350.pdf
-- CJK Unified Ideographs Extension J: https://www.unicode.org/charts/PDF/U323B0.pdf
local supplementary_han = {
    -- U+16FE3: the Old Chinese iteration mark, classified as a Han modifier letter.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L1603
    Range:new { from = 0x16FE3, to = 0x16FE3 },

    -- U+16FF2-U+16FF3: Chinese small simplified er and small traditional er.
    -- The following Han-script musical numerals have a number category, not a letter category.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L1605
    Range:new { from = 0x16FF2, to = 0x16FF3 },

    -- U+20000-U+2A6DF: the complete assigned CJK Unified Ideographs Extension-B range.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L1607
    Range:new { from = 0x20000, to = 0x2A6DF },

    -- U+2A700-U+2B81D: assigned Extension-C and Extension-D ideographs in one continuous record.
    -- Stops at the last assigned Extension-D character, before unassigned U+2B81E-U+2B81F.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L1608
    Range:new { from = 0x2A700, to = 0x2B81D },

    -- U+2B820-U+2CEAD: assigned CJK Unified Ideographs Extension-E letters.
    -- Excludes the block's unassigned final positions U+2CEAE-U+2CEAF.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L1609
    Range:new { from = 0x2B820, to = 0x2CEAD },

    -- U+2CEB0-U+2EBE0: assigned CJK Unified Ideographs Extension-F letters.
    -- Stops before the block's unassigned tail U+2EBE1-U+2EBEF.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L1610
    Range:new { from = 0x2CEB0, to = 0x2EBE0 },

    -- U+2EBF0-U+2EE5D: assigned CJK Unified Ideographs Extension-I letters.
    -- Excludes the block's unassigned final positions U+2EE5E-U+2EE5F.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L1611
    Range:new { from = 0x2EBF0, to = 0x2EE5D },

    -- U+2F800-U+2FA1D: assigned CJK Compatibility Ideographs Supplement letters.
    -- Stops at the last assigned character, before unassigned U+2FA1E-U+2FA1F.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L1612
    Range:new { from = 0x2F800, to = 0x2FA1D },

    -- U+30000-U+3134A: assigned CJK Unified Ideographs Extension-G letters.
    -- Stops before the block's unassigned tail U+3134B-U+3134F.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L1613
    Range:new { from = 0x30000, to = 0x3134A },

    -- U+31350-U+33479: assigned Extension-H and Extension-J ideographs in one continuous record.
    -- Stops at the last assigned Extension-J character, before unassigned U+3347A-U+3347F.
    -- https://github.com/unicode-org/unicodetools/blob/48afe632bf194a20bcd27c3488b49dc23274b684/unicodetools/data/ucd/17.0.0/Scripts.txt#L1614
    Range:new { from = 0x31350, to = 0x33479 },
}

-- Assemble the public lists in their original order without exposing the individual groups.
local latin = h.join_lists(
    basic_latin,
    latin_1_supplement_letters,
    latin_extended_and_ipa_letters,
    latin_phonetic_extensions,
    latin_extended_additional,
    latin_superscripts_and_letter_forms,
    latin_extended_c,
    latin_extended_d,
    latin_extended_e,
    latin_presentation_and_fullwidth_letters,
    supplementary_latin
)

local cjk = h.join_lists(
    hangul_jamo_and_syllables,
    halfwidth_hangul,
    hiragana,
    katakana,
    supplementary_katakana,
    han_ideographs_and_iteration_marks,
    supplementary_han
)

return { latin = latin, cjk = cjk }
