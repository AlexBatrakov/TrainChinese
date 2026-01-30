using Dates
using JSON
using Statistics
using Random  # Used for shuffle/random sampling
using Printf
using PyPlot
using StatsBase

"""
Enum describing which attribute of a word is being trained or recalled.

- `Hanzi`: Chinese characters
- `Pinyin`: pinyin with tone numbers
- `Translation`: English translation (plus optional context)
"""
@enum AttributeType begin
    Hanzi         # Hanzi (Chinese characters)
    Pinyin        # Pinyin
    Translation   # Translation
end

"""Parse a string like `"Hanzi"` into an `AttributeType`.

Returns `nothing` if the string does not match any enum value.
"""
function parse_attribute_type(str::String)::Union{AttributeType, Nothing}
    let insts = instances(AttributeType),
        p = findfirst(==(Symbol(str)) ∘ Symbol, insts)
        return p !== nothing ? insts[p] : nothing
    end
end

"""Single review event (one attempt sequence) captured for analytics and scheduling."""
struct RewievInfo
    date_reviewed::DateTime
    time_interval_minutes::Float64
    time_reaction_seconds::Float64
    priority::Float64
    memory_strength::Float64
    hint_used::Bool
    result::Int64
    level_old::Int64
    level_new::Int64
end

# Keyword-argument constructor
function RewievInfo(; date_reviewed=now(),
    time_interval_minutes=0.0,
    time_reaction_seconds=0.0,
    priority=0.0,
    memory_strength=0.0,
    hint_used=false,
    result=0,
    level_old=0,
    level_new=0)
    return RewievInfo(date_reviewed, time_interval_minutes, time_reaction_seconds,
     priority, memory_strength, hint_used, result, level_old, level_new)
end

"""Per-task statistics for a word.

Each word is trained as multiple directed tasks (e.g. `Hanzi -> Pinyin`).
This struct stores the spaced-repetition level and review history for one such task.
"""
mutable struct WordStats
    level::Int                         # Learning level for this task
    date_last_reviewed::DateTime       # Last review time for this task
    count_correct::Int                 # Number of correct answers for this task
    count_hint::Int                    # Number of answers with a hint for this task
    count_incorrect::Int               # Number of incorrect answers for this task
    review_history::Vector{RewievInfo} # Review history
end

WordStats() = WordStats(0, now(), 0, 0, 0, Vector{RewievInfo}())

"""Vocabulary item tracked by the trainer.

Fields include the word itself (`hanzi`, `pinyin`, `translation`, optional `context`),
global spaced-repetition level, and per-task stats for all attribute pairs.

`correlation_errors` is used to capture common confusions (e.g. mixing up similar hanzi).
"""
mutable struct Word
    id::String                          # Unique word ID (e.g. "hsk1.98", "duo.7", or "hsk3.487.a")
    hanzi::String                       # Hanzi
    pinyin::String                      # Pinyin (with tone numbers)
    translation::String                 # Translation
    context::String                     # Optional context for disambiguation
    date_added::DateTime                # Time when the word was added
    date_last_reviewed_global::DateTime # Global time since last review
    level_global::Int64                 # Global level
    stats::Dict{Tuple{AttributeType, AttributeType}, WordStats} # Per-task stats
    correlation_errors::Dict{AttributeType, Dict{String, Int64}}    # Correlation errors with other words (keys: Hanzi, Pinyin, Translation)
end

Word(id, hanzi, pinyin, translation, context) = 
    Word(id,
        hanzi,
        pinyin,
        translation,
        context,
        now(),
        now(),
        0,
        Dict(
            (attribute1, attribute2) => WordStats()
            for attribute1 in instances(AttributeType), attribute2 in instances(AttributeType) if attribute1 != attribute2
        ),
        Dict(attribute => Dict{String, Int64}() for attribute in instances(AttributeType))
    )

function calculate_priority(level::Int, date_last_reviewed::DateTime)::Float64
    t = now() - date_last_reviewed  # Time since last review
    p = 2^level                     # Half-life period depends on level
    priority = (t / Minute(1)) / p  # Priority: time / half-life period
    return priority
end
    
"""Compute memory strength (0..1) from level and last-review time.

Higher value means the item is more likely to be recalled. This is an exponential
decay model based on the derived `priority`.
"""
function calculate_memory_strength(level::Int, date_last_reviewed::DateTime)::Float64
    C = 1.0887147152069994
    priority = calculate_priority(level, date_last_reviewed)
    return exp2(-C * priority)
end

"""Compute a new spaced-repetition level after an attempt.

`result` meanings:
- `1`: correct on first try
- `0`: correct with a hint / second try
- `-1`: incorrect

The update is probabilistic and depends on the current memory strength.
"""
function calculate_new_level(word_stats::WordStats, result::Int)
    level_old = word_stats.level
    date_last_reviewed = word_stats.date_last_reviewed

    # priority = calculate_priority(level_old, date_last_reviewed)
    memory_strength = calculate_memory_strength(level_old, date_last_reviewed)
    level_new = level_old

    if result == 1  # Successful recall
        transition_probability = 1 - memory_strength
        while rand() < transition_probability
            level_new += 1
            corrected_memory_strength = calculate_memory_strength(level_new, date_last_reviewed)
            transition_probability = 1 - corrected_memory_strength
        end
    elseif result == -1  # Failed recall
        transition_probability = memory_strength
        while rand() < transition_probability && level_new > 1
            level_new -= 1
            corrected_memory_strength = calculate_memory_strength(level_new, date_last_reviewed)
            transition_probability = corrected_memory_strength
        end
    end

    return level_new
end

"""Update per-task statistics for a word after an attempt."""
function update_word_stats(word::Word, task_type::Tuple{AttributeType, AttributeType}, result::Int)
    word_stats = word.stats[task_type]

    level_old = word_stats.level
    # Compute new level
    level_new = calculate_new_level(word_stats, result)

    # Compute time since last review
    time_interval_minutes = (now() - word_stats.date_last_reviewed) / Minute(1)

    # Add entry to history
    push!(word_stats.review_history, RewievInfo(
        date_reviewed = now(),
        time_interval_minutes = time_interval_minutes,
        time_reaction_seconds = 0.0,  # Reaction time is not tracked yet
        priority = calculate_priority(level_old, word_stats.date_last_reviewed),
        memory_strength = calculate_memory_strength(level_new, word_stats.date_last_reviewed),
        hint_used = (result == 0),
        result = result,
        level_old = level_old,
        level_new = level_new
    ))

    word_stats.level = level_new # Update level
    word_stats.date_last_reviewed = now()  # Update last review time
end

"""Recompute global word stats.

Currently, the global level is the minimum of all per-task levels.
"""
function update_global_stats(word::Word)
    min_level = minimum(stat.level for stat in values(word.stats))
    word.level_global = min_level
    word.date_last_reviewed_global = now()
end

"""Update a word after completing one task (e.g. `Hanzi -> Pinyin`)."""
function update_word(word::Word, task_type::Tuple{AttributeType, AttributeType}, result::Int)
    # Update per-task stats
    update_word_stats(word, task_type, result)

    # Update global stats
    update_global_stats(word)
end

"""Container holding two word pools.

- `known_words`: words currently being trained (have progress)
- `new_words`: words available to be introduced
"""
struct WordPool
    known_words::Dict{String, Word}   # Words currently being learned
    new_words::Dict{String, Word}     # Words not studied yet
end

WordPool() = WordPool(Dict{String, Word}(), Dict{String, Word}())

struct TrainingParams
    max_ephemeral_words::Int  # Maximum number of words in the "ephemeral" group
    max_fleeting_words::Int   # Maximum number of words in "ephemeral" + "fleeting"
    max_total_words::Int      # Maximum total number of words eligible for review
end

# Keyword-argument constructor
function TrainingParams(; max_ephemeral_words::Int=5, max_fleeting_words::Int=20, max_total_words::Int=50)
    return TrainingParams(max_ephemeral_words, max_fleeting_words, max_total_words)
end

"""Wrap `text` with ANSI escape codes for terminal coloring."""
# Change terminal text color
function colored_text(text::String, color::Symbol)
    colors = Dict(
        :red => "\x1b[31m",
        :green => "\x1b[32m",
        :yellow => "\x1b[33m",
        :blue => "\x1b[34m",
        :reset => "\x1b[0m"
    )
    return "$(colors[color])$text$(colors[:reset])"
end

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

duolingo_list = ["水", "咖", "啡", "和", "茶", "米", "饭", "这", "是", "汤", "冰", "你", "的", "粥", "豆", "腐", "热", "英", "国", "美", "中", "人", "我", "好", "意", "大", "利", "呢", "文", "医", "生", "老", "师", "服", "务", "员", "对", "不", "说", "律", "学", "喜", "欢", "日", "本", "汉", "堡", "包", "菜", "音", "乐", "数", "课", "上", "网", "唱", "歌", "跑", "爸", "婆", "很", "高", "兴", "认", "识", "加", "拿", "她", "妈", "公", "旅", "行", "儿", "子", "他", "习", "也", "真", "吗", "女", "馆", "去", "书", "店", "超", "市", "吃", "口", "韩", "常", "亚", "洲", "买", "零", "食", "看", "谢", "杯", "要", "牛", "奶", "两", "绿", "客", "气", "李", "里", "在", "钱", "哪", "洗", "手", "间", "火", "车", "站", "机", "票", "第", "一", "二", "台", "个", "同", "新", "有", "叫", "什", "么", "名", "字", "丽", "节", "四", "今", "天", "都", "历", "史", "们", "打", "篮", "球", "还", "喝", "想", "明", "电", "影", "院", "园", "吧", "图", "书", "馆", "下", "午", "见", "果", "步", "哎", "呀", "房", "厅", "寓", "小", "漂", "亮", "厨", "发", "舒", "床", "空", "调", "没", "视", "月", "会", "北", "京", "飞", "怎", "坐", "场", "远", "出", "租", "地", "铁", "故", "长", "城", "交", "便", "宜", "件", "毛", "衣", "冷", "样", "那", "点", "克", "裤", "条", "短", "百", "贵", "元"]

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

Contains a small set of disambiguation hacks for characters that `say` pronounces
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
        text == "斢"
    elseif text == "落" && pinyin == "la4"
        text == "辣"
    elseif text == "散" && pinyin == "san3"
        text == "伞"
    elseif text == "扇" && pinyin == "shan1"
        text == "山"
    elseif text == "吐" && pinyin == "tu4"
        text == "兔"
    elseif text == "看" && pinyin == "kan1"
        text == "刊"
    elseif text == "露" && pinyin == "lou4"
        text == "漏"
    elseif text == "蒙" && pinyin == "meng1"
        text == text
    end
    # Add short pauses before and after the text
    padded_text = "[[slnc 100]] $(text) [[slnc 100]]" # 100ms pause before and after
    try
        run(`say -v $(voice) $(padded_text)`)
    catch e
        println("Error: voice $(voice) not found. Try a different voice.")
    end
end

function cut_hanzi(hanzi::String)
    hanzi_parts = collect(hanzi)
    index = findfirst(w -> w == '（', collect(hanzi_parts))
    if isnothing(index) || any(w -> occursin(w, hanzi), ["（一）", "（不）"])
        return hanzi, ""
    elseif any(w -> w in hanzi_parts[1:index-1], hanzi_parts[index:end])
        return hanzi, ""
    else 
        return join(hanzi_parts[1:index-1], ""), join(hanzi_parts[index:end], "")
    end
end

"""Load vocabulary entries from a text file into `pool`.

Input file format (line-based):
`id | hanzi | pinyin | translation | optional context`

Notes:
- Lines starting with `#` are comments.
- The file supports a `SKIP` toggle region and an early `STOP` marker.
- `pinyin` is normalized via `convert_pinyin_string`.
"""
function update_word_pool_from_file!(pool::WordPool, filename::String)
    # duolingo_mode1 = false
    # duolingo_mode2 = false
    # duolingo_mask = ones(Bool, length(duolingo_list))
    skip_key = false
    # Open the file and read line by line
    count_repeate_translation = 0
    open(filename, "r") do file
        for line in eachline(file)
            if line[1:4] == "STOP"
                break
            elseif line[1] == '#'
                continue
            elseif line[1:4] == "SKIP"
                skip_key = skip_key ? false : true
                continue
            elseif skip_key == true
                continue
            end

            # Split the line into hanzi, pinyin, translation (and optional context)
            parts = split(line, " | ")
            if (length(parts) == 4 || length(parts) == 5)
                context = ""
                id, hanzi, pinyin, translation = parts[1:4]
                if length(parts) == 5
                    context = parts[5]
                end

                # if duolingo_mode1 == true
                #     hanzi_parts = collect(hanzi)
                #     index = findfirst(w -> w == '（' || w == '｜', hanzi_parts)
                #     if !isnothing(index)
                #         hanzi_parts = hanzi_parts[1:index-1]
                #     end
                #     if all(string(hanzi_part) in duolingo_list for hanzi_part in hanzi_parts)
                #         println(line)
                #     end
                #     continue
                # end

                # if duolingo_mode2 == true
                #     for (i, w) in enumerate(duolingo_list)
                #         if occursin(w, hanzi)
                #             duolingo_mask[i] = false
                #         end
                #     end
                # end

                hanzi_main, hanzi_context = cut_hanzi(String(hanzi))

                hanzi = hanzi_main
                context = (context == "") ? (hanzi_context) : (hanzi_context == "" ? context : hanzi_context * " " * context)
                pinyin = convert_pinyin_string(String(pinyin), tone_map)

                # Check whether the word already exists in the known pool
                is_known_word = haskey(pool.known_words, id)

                if is_known_word == false
                    # New word: add it to the new-words pool
                    new_word = Word(id, hanzi, pinyin, translation, context)
                    pool.new_words[id] = new_word
                else
                    # println("Duplicate word: ", hanzi)
                    # Existing word: update metadata if needed
                    existing_word = pool.known_words[id]
                    if existing_word.context != context
                        println("Updated context for word $hanzi: ", context)
                        pool.known_words[id].context = context
                    end
                end
            else
                println("Invalid line format: ", line)
            end
        end
    end
    # println("Words with duplicate translation: ", count_repeate_translation)
    # if duolingo_mode2 == true
    #     println(duolingo_list[duolingo_mask])
    # end
    println(colored_text("Word pool updated from file $filename", :blue))
end

"""Convert a task string like `"Hanzi -> Pinyin"` to a tuple."""
function string_to_task_tuple(task_str::String)::Tuple{AttributeType, AttributeType}
    parts = split(task_str, " -> ")
    if length(parts) == 2
        attr1 = parse_attribute_type(String(parts[1]))
        attr2 = parse_attribute_type(String(parts[2]))
        if attr1 !== nothing && attr2 !== nothing
            return (attr1, attr2)
        end
    end
    error("Invalid task string format: $task_str")
end

"""Convert a task tuple like `(Hanzi, Pinyin)` to string form `"Hanzi -> Pinyin"`."""
function task_tuple_to_string(task::Tuple{AttributeType, AttributeType})::String
    return string(task[1]) * " -> " * string(task[2])
end

"""Persist known words (including stats) to a JSON file."""
function save_words_to_file(words::Dict{String, Word}, filename::String)
    data = [
        Dict(
            "id" => w.id,
            "hanzi" => w.hanzi,
            "pinyin" => w.pinyin,
            "translation" => w.translation,
            "context" => w.context,
            "date_added" => string(w.date_added),
            "date_last_reviewed_global" => string(w.date_last_reviewed_global),
            "level_global" => w.level_global,
            "stats" => Dict(
                task_tuple_to_string(task) => Dict(
                    "level" => stats.level,
                    "date_last_reviewed" => string(stats.date_last_reviewed),
                    "count_correct" => stats.count_correct,
                    "count_hint" => stats.count_hint,
                    "count_incorrect" => stats.count_incorrect,
                    "review_history" => [
                        Dict(
                            "date_reviewed" => string(review.date_reviewed),
                            "time_interval_minutes" => review.time_interval_minutes,
                            "time_reaction_seconds" => review.time_reaction_seconds,
                            "priority" => review.priority,
                            "memory_strength" => review.memory_strength,
                            "hint_used" => review.hint_used,
                            "result" => review.result,
                            "level_old" => review.level_old,
                            "level_new" => review.level_new
                        ) for review in stats.review_history
                    ]
                ) for (task, stats) in w.stats
            ),
            "correlation_errors" => Dict(
                string(attribute) => errors for (attribute, errors) in w.correlation_errors
            )
        ) for w in values(words)
    ]

    # Generate pretty JSON
    pretty_json = JSON.json(data, 4)

    # Write to file
    open(filename, "w") do file
        write(file, pretty_json)
    end

    println("Data saved successfully to file $filename")
end

"""Load known words (including stats) from a JSON file.

Returns an empty dictionary on errors.
"""
function load_words_from_file(filename::String)::Dict{String, Word}
    try
        # Load data from JSON
        data = JSON.parsefile(filename)

        # Convert data into Dict{String, Word}
        words = Dict{String, Word}()
        for d in data
            # Build Word from a dictionary
            word = Word(
                d["id"],
                d["hanzi"],
                d["pinyin"],
                d["translation"],
                get(d, "context", ""),  # Context can be empty
                DateTime(d["date_added"]),
                DateTime(d["date_last_reviewed_global"]),
                d["level_global"],
                Dict(
                    string_to_task_tuple(task) => WordStats(
                        stat["level"],
                        DateTime(stat["date_last_reviewed"]),
                        stat["count_correct"],
                        stat["count_hint"],
                        stat["count_incorrect"],
                        [
                            RewievInfo(
                                DateTime(review["date_reviewed"]),
                                review["time_interval_minutes"],
                                review["time_reaction_seconds"],
                                review["priority"],
                                review["memory_strength"],
                                review["hint_used"],
                                review["result"],
                                review["level_old"],
                                review["level_new"]
                            ) for review in stat["review_history"]
                        ]
                    ) for (task, stat) in d["stats"]
                ),
                Dict(
                    parse_attribute_type(attr) => Dict{String, Int64}(errors) for (attr, errors) in d["correlation_errors"]
                )
            )
            # Add word to dictionary
            words[word.id] = word
        end
        return words
    catch e
        println("Error loading file: ", e)
        return Dict{String, Word}()  # Return empty dictionary on error
    end
end

"""Write a tabular stats summary file for quick inspection.

The output contains per-task levels, plus mean and min level per word.
"""
function save_stats_to_file(known_words::Dict{String, Word}, filename::String)
    # Open file for writing
    open(filename, "w") do file
        # Add column headers
        header = @sprintf("%-10s %-20s %-50s %-4s\t %-4s\t %-4s\t %-4s\t %-4s\t %-4s\t%-4s\t%-4s\t",
                          "Hanzi", "Pinyin", "Translation", "h->p", "h->t", "p->h", "p->t", "t->h", "t->p", "mean", "min")
        write(file, header * "\n")

        words = collect(values(known_words))
        sorted_words = sort(words, by = w -> w.date_added)

        for word in sorted_words
            # Format a line with word info
            line = @sprintf("%-10s %-20s %-50s", word.hanzi, word.pinyin, word.translation)

            # Extract per-task levels
            levels = [word.stats[(attribute2, attribute1)].level 
                      for attribute1 in instances(AttributeType), 
                          attribute2 in instances(AttributeType) 
                          if attribute1 != attribute2]

            # Compute mean and minimum levels
            mean_level = mean(levels)
            min_level = minimum(levels)

            # Render levels as a tab-separated string
            level_str = join([@sprintf("%4d", l) for l in levels], "\t")
            mean_level_str = @sprintf("%4.1f", mean_level)
            min_level_str = @sprintf("%4d", min_level)

            # Build the full line
            line *= level_str * "\t" * mean_level_str * "\t" * min_level_str

            # Write line to file
            write(file, line * "\n")
        end
    end

    println(colored_text("Data saved successfully to file $filename", :blue))
end

"""Return `true` if `keyword` appears as a whole word within `text` (case-insensitive)."""
function contains_exact_word(keyword::String, text::String)::Bool
    words = split(text, r"\W+")  # Split into words (taking punctuation into account)
    return lowercase(keyword) in lowercase.(words)
end

"""Find known words by translation/context keyword query.

`keywords` format: `translation_kw1+translation_kw2;context_kw1+context_kw2`.
Context part after `;` is optional.
"""
function find_words_by_keywords(keywords::String, pool::WordPool; max_results::Int = 10)::Vector{Tuple{String, Word}}
    parts = split(keywords, ";", limit=2)
    translation_keywords = parts[1] != "" ? split(parts[1], "+") : []
    context_keywords = length(parts) > 1 && parts[2] != "" ? split(parts[2], "+") : []

    matching_words = Vector{Tuple{String, Word}}()

    # Search matches in translation and context
    for word in values(pool.known_words)
        translation_match = all(kw -> contains_exact_word(String(kw), word.translation), translation_keywords)
        context_match = all(kw -> contains_exact_word(String(kw), word.context), context_keywords)
        
        if translation_match && context_match
            push!(matching_words, (word.translation, word))
        end
    end

    # Sort by translation length
    sort!(matching_words, by = x -> length(x[1]))

    # for i in 1:length(matching_words)
    #     println(matching_words[i][1])
    # end

    # Return first max_results
    return matching_words[1:min(max_results, length(matching_words))]
end

"""Record a confusion/correlation error for later analysis.

- For `Translation`, `input` is the wrong word ID the user selected.
- For `Hanzi`/`Pinyin`, `input` is the entered value, which is matched against known words.
"""
function record_correlation_error(word::Word, attribute_type::AttributeType, input::String, pool::WordPool)
    if attribute_type == Translation
        # For Translation, `input` is the wrong word ID
        if !haskey(word.correlation_errors[attribute_type], input)
            word.correlation_errors[attribute_type][input] = 0
        end
        word.correlation_errors[attribute_type][input] += 1
        println("Correlation error (Translation): recorded match with ID $input for attribute $attribute_type.")
    else
        # For Hanzi and Pinyin, `input` is a string (hanzi or pinyin)
        for candidate_word in values(pool.known_words)
            if candidate_word.id != word.id  # Exclude the current word
                if (attribute_type == Hanzi && candidate_word.hanzi == input) || (attribute_type == Pinyin && compare_pinyin(input, candidate_word.pinyin))
                    # Update correlation
                    if !haskey(word.correlation_errors[attribute_type], candidate_word.id)
                        word.correlation_errors[attribute_type][candidate_word.id] = 0
                    end
                    word.correlation_errors[attribute_type][candidate_word.id] += 1
                    println("Correlation error (Hanzi/Pinyin): recorded match with ID $(candidate_word.id) for attribute $(attribute_type).")
                    return  # Assume one `input` value can match at most one word
                end
            end
        end
        # println("Correlation error: no matches found for value '$input'.")
    end
end

"""Hanzi input task.

Prompts the user to enter the correct character.
Returns `1`/`0`/`-1` depending on attempt quality.

Note: triggers a macOS keyboard-layout hotkey via `osascript`.
"""
function task_hanzi(word::Word, pool::WordPool)
    println("\nTask: Write the character. Enter it using a Chinese keyboard.")
    
    # Attempt counter
    attempts = 0
    
    while attempts < 3
        attempts += 1
        println("Enter hanzi:")

        if attempts == 3
            println("Hint: $(word.hanzi)")
        end

        run(`osascript -e 'tell application "System Events" to key code 49 using {shift down, control down}'`)
        user_input = readline()
        run(`osascript -e 'tell application "System Events" to key code 49 using {shift down, control down}'`)

        if user_input == word.hanzi
            if attempts == 1
                println(colored_text("Correct on the first try!", :green))
                return 1
            elseif attempts == 2
                println(colored_text("Correct on the second try!", :yellow))
                return 0
            else
                println(colored_text("Correct on the third try!", :yellow))
                return -1
            end
        else
            if attempts < 2
                println(colored_text("Incorrect. Try again.", :red))
            end
            # Store correlation for an incorrect answer
            record_correlation_error(word, Hanzi, user_input, pool)
        end
    end

    # If the answer is still wrong after the attempts
    println(colored_text("Incorrect.", :yellow))
    println(colored_text("Correct hanzi: $(word.hanzi)", :green))
    return -1
end

"""Compare pinyin strings while ignoring spaces."""
function compare_pinyin(user_input::String, pinyin::String)
	user_input_no_spaces = replace(user_input, " " => "")
	pinyin_no_spaces     = replace(pinyin, " " => "")
	return user_input_no_spaces == pinyin_no_spaces
end

"""Pinyin input task.

If `sound=true`, plays TTS for the word before asking.
Returns `1`/`0`/`-1` depending on attempt quality.
"""
function task_pinyin(word::Word, pool::WordPool; sound=false)
    println("\nTask: Enter pinyin with tones (e.g. ni3 hao3).")
    
    # Attempt counter
    attempts = 0
    
    while attempts < 3
        attempts += 1

        if attempts == 3
            sound = true
        end

        if sound
            say_text(word.hanzi)
        end

        println("Enter pinyin:")
        user_input = readline()

        if compare_pinyin(user_input, word.pinyin)
            if attempts == 1
                println(colored_text("Correct on the first try!", :green))
                return 1
            elseif attempts == 2
                println(colored_text("Correct on the second try!", :yellow))
                return 0
            else
                println(colored_text("Correct on the third try!", :yellow))
                return -1
            end
        else
            if attempts < 2
                println(colored_text("Incorrect. Try again.", :red))
            end
            # Store correlation for an incorrect answer
            record_correlation_error(word, Pinyin, user_input, pool)
        end
    end

    # If the answer is still wrong after the attempts
    println(colored_text("Incorrect.", :yellow))
    println(colored_text("Correct pinyin: $(word.pinyin)", :green))
    return -1
end

"""Translation task.

User enters keywords, then selects the intended translation from a shortlist.
Returns `1`/`0`/`-1` depending on attempt quality.
"""
function task_translation(word::Word, pool::WordPool)
    println("Task: Enter translation keywords (e.g. 'have+not;context').")

    # Attempt counter
    attempts = 0

    while attempts < 2
        attempts += 1
        user_input = readline()

        # Find candidate words by keywords
        matching_words = find_words_by_keywords(user_input, pool)

        if isempty(matching_words)
            println(colored_text("No words match the entered keywords.", :red))
            if attempts < 2
                println("Try entering the keywords again.")
                continue
            else
                println(colored_text("Incorrect.", :yellow))
                println(colored_text("Correct translation: $(word.translation)", :green))
                if !isempty(word.context)
                    println(colored_text("Context: $(word.context)", :yellow))
                end
                return -1
            end
        end

        # If we have matches, show the list
        println("\nChoose the correct translation from the options below:")
        for (i, (_, matched_word)) in enumerate(matching_words)
            # Add translation and context (if any)
            context_str = isempty(matched_word.context) ? "" : " (context: $(matched_word.context))"
            println("[$i] $(matched_word.translation)$context_str")
        end

        # Read user selection
        selected_index = try
            parse(Int, readline())
        catch
            println(colored_text("Please enter a number from the list.", :yellow))
            attempts -= 1  # Don't count invalid input as an attempt
            continue
        end

        # Validate selection
        if selected_index > 0 && selected_index <= length(matching_words)
            selected_word = matching_words[selected_index][2]
            if selected_word.id == word.id
                if attempts == 1
                    println(colored_text("Correct on the first try!", :green))
                    return 1
                else
                    println(colored_text("Correct on the second try!", :yellow))
                    return 0
                end
            else
                println(colored_text("Incorrect. Try again.", :red))
                # Store correlation (wrong translation ID)
                record_correlation_error(word, Translation, selected_word.id, pool)
                if attempts == 2
                    println(colored_text("Incorrect.", :yellow))
                    println(colored_text("Correct translation: $(word.translation)", :green))
                    if !isempty(word.context)
                        println(colored_text("Context: $(word.context)", :yellow))
                    end
                    return -1
                end
            end
        else
            println(colored_text("Invalid choice. Try again.", :yellow))
            attempts -= 1  # Don't count invalid choice as an attempt
        end
    end

    return -1
end

"""Train a word starting from hanzi (Hanzi → Pinyin → Translation)."""
function train_from_hanzi(word::Word, pool::WordPool)
    println("Word hanzi: ", word.hanzi)

    # 1. Write hanzi (warm-up; does not affect stats)
    task_hanzi(word, pool)

    # 2. Enter pinyin
    result_pinyin = task_pinyin(word, pool)
    update_word(word, (Hanzi, Pinyin), result_pinyin)

    # 3. Enter translation
    result_translation = task_translation(word, pool)
    update_word(word, (Hanzi, Translation), result_translation)
end

"""Train a word starting from pinyin (Pinyin → Hanzi → Translation)."""
function train_from_pinyin(word::Word, pool::WordPool)
    # println("Word pinyin: ", word.pinyin)

    # 1. Enter pinyin (warm-up; does not affect stats)
    task_pinyin(word, pool, sound=true)

    # 2. Enter hanzi
    result_hanzi = task_hanzi(word, pool)
    update_word(word, (Pinyin, Hanzi), result_hanzi)

    # 3. Enter translation
    result_translation = task_translation(word, pool)
    update_word(word, (Pinyin, Translation), result_translation)
end

"""Train a word starting from translation (Translation → Hanzi → Pinyin)."""
function train_from_translation(word::Word, pool::WordPool)
    println("Word translation: ", word.translation)
    if !isempty(word.context)
        println("Context: $(colored_text(word.context, :yellow))")
    end

    # 1. Find translation (warm-up; does not affect stats)
    # task_translation(word, pool)

    # 2. Enter hanzi
    result_hanzi = task_hanzi(word, pool)
    update_word(word, (Translation, Hanzi), result_hanzi)

    # 3. Enter pinyin
    result_pinyin = task_pinyin(word, pool)
    update_word(word, (Translation, Pinyin), result_pinyin)
end

"""Train a single word by choosing the weakest attribute as the starting point.

The starting attribute is selected as the argmin of per-task levels.
"""
function train_word(word::Word, pool::WordPool)
    run(`clear`)
    if isempty(word.stats)
        println("No stats for word: ", word.id)
        return
    end

    # Choose the attribute with the minimum level
    attibute_to_train_from = argmin(x -> x[2].level, word.stats)[1][1]
    # attibute_to_train_from = findmin([(key, stats.level) for (key, stats) in word.stats])
    println("Training attribute: ", attibute_to_train_from)

    if attibute_to_train_from == Hanzi
        train_from_hanzi(word, pool)
    elseif attibute_to_train_from == Pinyin
        train_from_pinyin(word, pool)
    elseif attibute_to_train_from == Translation
        train_from_translation(word, pool)
    else
        println("Unknown attribute to train: ", attibute_to_train_from)
    end

    say_text(word.hanzi)
end

"""Bucket words into coarse learning phases based on `level_global`."""
function calculate_gradations(pool::WordPool)::Dict{String, Int}
    # Initialize gradations
    gradations = Dict("ephemeral" => 0, "fleeting" => 0, "short-term" => 0, "transition" => 0, "long-term" => 0, "permanent" => 0)

    # Distribute words into gradations based on global level
    for word in values(pool.known_words)
        global_level = word.level_global

        if global_level < 4
            gradations["ephemeral"] += 1
        elseif global_level < 8
            gradations["fleeting"] += 1
        elseif global_level < 12
            gradations["short-term"] += 1
        elseif global_level < 16
            gradations["transition"] += 1
        elseif global_level < 20
            gradations["long-term"] += 1
        else
            gradations["permanent"] += 1
        end
    end

    return gradations
end

"""Decide whether a new word should be introduced given current pool composition."""
function should_add_new_word(pool::WordPool, params::TrainingParams)::Bool
    # Count word gradations
    gradations = calculate_gradations(pool)

    # Count the number of words with high global priority
    high_priority_count = 0
    for word in values(pool.known_words)
        global_priority = calculate_priority(word.level_global, word.date_last_reviewed_global)
        if global_priority >= 1
            high_priority_count += 1
        end
    end

    # If there are no high-priority words
    if high_priority_count == 0
        println("No high-priority words to review. Add a new word? (y/n)")
        while true
            user_input = readline()
            if user_input == "y"
                return true
            elseif user_input == "n"
                return false
            else
                println("Please enter 'y' or 'n'.")
            end
        end
    end

    # Check gradation constraints
    if gradations["ephemeral"] < params.max_ephemeral_words
        return true  # Add a new word to keep the active learning phase going
    elseif gradations["ephemeral"] + gradations["fleeting"] >= params.max_fleeting_words
        return false  # Don't add if there are too many active words
    elseif high_priority_count >= params.max_total_words
        return false  # Don't add if there are too many words to review
    else
        return false  # Otherwise, don't add a new word
    end
end

"""Move a random word from `new_words` into `known_words` and return it."""
function select_random_word!(pool::WordPool)::Union{Word, Nothing}
    if isempty(pool.new_words)
        println("New word pool is empty.")
        return nothing
    end

    # Pick a random key from the new-words dictionary
    random_key = rand(collect(keys(pool.new_words)))
    selected_word = pool.new_words[random_key]

    # Move the word from new -> known
    delete!(pool.new_words, random_key)
    pool.known_words[random_key] = selected_word

    println("Added a new word to learn: ", selected_word.hanzi)
    return selected_word
end

"""Introduce a new word to the user (display + warm-up tasks)."""
function introduce_new_word(word::Word, pool::WordPool)
    run(`clear`)
    println(colored_text("New word to learn:", :blue))
    println("Hanzi: $(colored_text(word.hanzi, :green))")
    println("Pinyin: $(colored_text(word.pinyin, :green))")
    println("Translation: $(colored_text(word.translation, :green))")
    if !isempty(word.context)
        println("Context: $(colored_text(word.context, :yellow))")
    end

    println("\nTry to remember this word, then we'll start training.")
    println("Press Enter to continue.")
    readline()

    # 1. Write hanzi
    task_hanzi(word, pool)

    # 2. Enter pinyin
    task_pinyin(word, pool, sound=true)
 
    # 3. Enter translation
    task_translation(word, pool)
end

"""Run an interactive training session.

Each loop iteration:
1) optionally introduces a new word
2) samples a small batch of due words
3) trains them
4) saves progress to disk
"""
function start_training_session(pool::WordPool, params::TrainingParams)
    while true
        # 1. Decide whether to add a new word
        if should_add_new_word(pool, params)
            new_word = select_random_word!(pool)
            if new_word !== nothing
                # Add the new word to known words
                pool.known_words[new_word.id] = new_word
                # Remove the word from new words
                delete!(pool.new_words, new_word.id)
                # Introduce the word to the user
                introduce_new_word(new_word, pool)
            end
        end

        # 2. Build the pool of words to train
        training_words = []
        for word in values(pool.known_words)
            global_priority = calculate_priority(word.level_global, word.date_last_reviewed_global)

            # Include words with priority > 1 or level 0
            if global_priority > 1 || word.level_global == 0
                push!(training_words, word)
            end
        end

        # If there are no words to train, end the session
        if isempty(training_words)
            println("No words to train. You can add new words or come back later.")
            break
        end

        # Pick a random batch to train (e.g., 5 words)
        training_batch = sample(training_words, min(5, length(training_words)), replace=false)

        # 3. Train each word
        for word in training_batch
            println("")
            train_word(word, pool)  # Use the per-word training function
        end

        # 4. Save results after each training round
        save_words_to_file(pool.known_words, "ChineseSave.json")
        save_stats_to_file(pool.known_words, "ChineseStats.txt")

        # Ask whether to continue
        println("\nContinue training? (press Enter to continue, or type 'exit' to quit)")
        user_input = readline()
        if user_input == "exit"
            println("Training finished.")
            break
        end
    end
end

"""Program entry point."""
function main()
    pool = WordPool()
    pool = WordPool(load_words_from_file("ChineseSave.json"), Dict{String, Word}())
    params = TrainingParams()
    
    # Update the word pool from the vocabulary file
    update_word_pool_from_file!(pool, "ChineseVocabulary.txt")
    
    # erase_history(pool)

    # display_statistics(pool)
    start_training_session(pool, params)
    # save_words_to_file(pool.known_words, "ChineseSave.json")
    # save_stats_to_file(pool.known_words, "ChineseStats.txt")

end

# Only auto-run when executed as a script, not when included as a package/module.
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
