"""Speak `text` via macOS `say`.

This is macOS-specific and will fail on other OSes.
"""
function say_text(text::String, voice::String = "Tingting")
    # Add short pauses before and after the text
    padded_text = "[[slnc 100]] $(text) [[slnc 100]]" # 100ms pause before and after
    try
        run(`say -v $(voice) $(padded_text)`)
    catch e
        println("Error: voice $(voice) not found. Try a different voice.")
    end
end

"""Speak a word's hanzi via macOS `say`.

Contains a small set of disambiguation workarounds for characters that `say` pronounces
unexpectedly depending on context.
"""
function say_word(word::Word, voice::String = "Tingting")
    text = deepcopy(word.hanzi)
    pinyin = word.pinyin

    if     text == "地" && pinyin == "de"
        text = "的"
    elseif text == "干" && pinyin == "gan4"
        text = "旰"
    elseif text == "倒" && pinyin == "dao4"
        text = "道"
    elseif text == "得" && pinyin == "de2"
        text = "锝"
    elseif text == "长" && pinyin == "zhang3"
        text = "掌"
    elseif text == "背" && pinyin == "bei4"
        text = "被"
    elseif text == "行" && pinyin == "hang2"
        text = "绗"
    elseif text == "调" && pinyin == "tiao2"
        text = "条"
    elseif text == "为" && pinyin == "wei4"
        text = "位"
    elseif text == "纸" && pinyin == "zhi3"
        text = "纸"
    elseif text == "划" && pinyin == "hua2"
        text = "华"
    elseif text == "卷" && pinyin == "juan4"
        text = "锩"
    elseif text == "挑" && pinyin == "tiao3"
        text = "斢"
    elseif text == "落" && pinyin == "la4"
        text = "辣"
    elseif text == "散" && pinyin == "san3"
        text = "伞"
    elseif text == "扇" && pinyin == "shan1"
        text = "山"
    elseif text == "吐" && pinyin == "tu4"
        text = "兔"
    elseif text == "看" && pinyin == "kan1"
        text = "刊"
    elseif text == "露" && pinyin == "lou4"
        text = "漏"
    elseif text == "蒙" && pinyin == "meng1"
        text = text
    end

    # Add short pauses before and after the text
    padded_text = "[[slnc 100]] $(text) [[slnc 100]]" # 100ms pause before and after
    try
        run(`say -v $(voice) $(padded_text)`)
    catch e
        println("Error: voice $(voice) not found. Try a different voice.")
    end
end
