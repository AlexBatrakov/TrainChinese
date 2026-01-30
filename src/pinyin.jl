tone_map = Dict(
    # Finals group 1: a, ai, an, ang, ao
    "ā" => "a1", "á" => "a2", "ǎ" => "a3", "à" => "a4",
    "āi" => "ai1", "ái" => "ai2", "ǎi" => "ai3", "ài" => "ai4",
    "ān" => "an1", "án" => "an2", "ǎn" => "an3", "àn" => "an4",
    "āng" => "ang1", "áng" => "ang2", "ǎng" => "ang3", "àng" => "ang4",
    "āo" => "ao1", "áo" => "ao2", "ǎo" => "ao3", "ào" => "ao4",
    # Finals group 2: e, ei, en, eng, er
    "ē" => "e1", "é" => "e2", "ě" => "e3", "è" => "e4",
    "ēi" => "ei1", "éi" => "ei2", "ěi" => "ei3", "èi" => "ei4",
    "ēn" => "en1", "én" => "en2", "ěn" => "en3", "èn" => "en4",
    "ēng" => "eng1", "éng" => "eng2", "ěng" => "eng3", "èng" => "eng4",
    "ēr" => "er1", "ér" => "er2", "ěr" => "er3", "èr" => "er4",
    # Finals group 3: i, ia, ian, iang, iao, ie, in, ing, iong
    "ī" => "i1", "í" => "i2", "ǐ" => "i3", "ì" => "i4",
    "iā" => "ia1", "iá" => "ia2", "iǎ" => "ia3", "ià" => "ia4",
    "iān" => "ian1", "ián" => "ian2", "iǎn" => "ian3", "iàn" => "ian4",
    "iāng" => "iang1", "iáng" => "iang2", "iǎng" => "iang3", "iàng" => "iang4",
    "iāo" => "iao1", "iáo" => "iao2", "iǎo" => "iao3", "iào" => "iao4",
    "iū" => "iu1", "iú" => "iu2", "iǔ" => "iu3", "iù" => "iu4",
    "iō" => "io1", "ió" => "io2", "iǒ" => "io3", "iò" => "io4",
    "īe" => "ie1", "íe" => "ie2", "ǐe" => "ie3", "ìe" => "ie4",
    "īn" => "in1", "ín" => "in2", "ǐn" => "in3", "ìn" => "in4",
    "īng" => "ing1", "íng" => "ing2", "ǐng" => "ing3", "ìng" => "ing4",
    "iōng" => "iong1", "ióng" => "iong2", "ǐong" => "iong3", "iòng" => "iong4",
    # Finals group 4: o, ong, ou
    "ō" => "o1", "ó" => "o2", "ǒ" => "o3", "ò" => "o4",
    "ōng" => "ong1", "óng" => "ong2", "ǒng" => "ong3", "òng" => "ong4",
    "ōu" => "ou1", "óu" => "ou2", "ǒu" => "ou3", "òu" => "ou4",
    # Finals group 5: u, ua, uai, uan, uang, ue, ui, un, uo
    "ū" => "u1", "ú" => "u2", "ǔ" => "u3", "ù" => "u4",
    "ūa" => "ua1", "úa" => "ua2", "ǔa" => "ua3", "ùa" => "ua4",
    "ūai" => "uai1", "úai" => "uai2", "ǔai" => "uai3", "ùai" => "uai4",
    "ūan" => "uan1", "úan" => "uan2", "ǔan" => "uan3", "ùan" => "uan4",
    "ūang" => "uang1", "úang" => "uang2", "ǔang" => "uang3", "ùang" => "uang4",
    "ūe" => "ue1", "úe" => "ue2", "ǔe" => "ue3", "ùe" => "ue4",
    "ūi" => "ui1", "úi" => "ui2", "ǔi" => "ui3", "ùi" => "ui4",
    "ūn" => "un1", "ún" => "un2", "ǔn" => "un3", "ùn" => "un4",
    "ūo" => "uo1", "úo" => "uo2", "ǔo" => "uo3", "ùo" => "uo4",
    # Finals group 6: ü, üe, üan, ün (with 4 tones + neutral; ü is represented as v)
    "ǖ" => "v1", "ǘ" => "v2", "ǚ" => "v3", "ǜ" => "v4", "ü" => "v",
    "ǖe" => "ve1", "ǘe" => "ve2", "ǚe" => "ve3", "ǜe" => "ve4", "üe" => "ve",
    "ǖan" => "van1", "ǘan" => "van2", "ǚan" => "van3", "ǜan" => "van4", "üan" => "van",
    "ǖn" => "vn1", "ǘn" => "vn2", "ǚn" => "vn3", "ǜn" => "vn4", "ün" => "vn",
    "｜" => "|", "（" => "(", "）" => ")", "·" => ".", "’" => "'"
)

"""Convert pinyin with diacritics to pinyin with tone numbers.

Example: `"nǐ hǎo"` → `"ni3 hao3"`.

Uses `tone_map` for mapping finals with tone marks to numbered syllables.
"""
function convert_pinyin_string(pinyin_text::String, tone_map::Dict{String, String})::String
    # Sort finals by descending length so longer finals match first
    sorted_finals = sort(collect(keys(tone_map)), by = x -> -length(x))

    result = ""
    current_word = ""

    i = 1
    while i <= lastindex(pinyin_text)
        match_found = false

        # Try to match finals, starting from the longest
        for final in sorted_finals
            final_length = length(final)
            end_index = i
            valid = true

            # Safely advance the index by the final length
            for _ in 1:final_length - 1
                if end_index < lastindex(pinyin_text)
                    end_index = nextind(pinyin_text, end_index)
                else
                    valid = false
                    break
                end
            end

            # Check that the substring matches the final
            if valid && end_index <= lastindex(pinyin_text) &&
               pinyin_text[i:end_index] == final
                match_found = true
                current_word *= tone_map[final]
                i = nextind(pinyin_text, end_index)  # Move to the next index after the final
                break
            end
        end

        # If no match, append the current character and move on
        if !match_found
            current_word *= pinyin_text[i]
            if i < lastindex(pinyin_text)
                i = nextind(pinyin_text, i)  # Move to the next character
            else
                i += 1  # Finish processing without going out of bounds
            end
        end

        # If we hit a space, end the current syllable
        if i > lastindex(pinyin_text) || (i <= lastindex(pinyin_text) && pinyin_text[i] == ' ')
            result *= current_word
            if i <= lastindex(pinyin_text)
                result *= " "  # Preserve the space
            end
            current_word = ""
            if i < lastindex(pinyin_text)
                i = nextind(pinyin_text, i)
            else
                i += 1  # Finish processing
            end
        end
    end

    # Append the last remaining syllable, if any
    result *= current_word

    return result
end

"""Compare pinyin strings while ignoring spaces."""
function compare_pinyin(user_input::String, pinyin::String)
	user_input_no_spaces = replace(user_input, " " => "")
	pinyin_no_spaces     = replace(pinyin, " " => "")
	return user_input_no_spaces == pinyin_no_spaces
end
