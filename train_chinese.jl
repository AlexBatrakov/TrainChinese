using Dates
using JSON
using Statistics
using Random  # Подключаем модуль для работы с функцией shuffle
using Printf
using PyPlot
using StatsBase

@enum AttributeType begin
    Hanzi         # Иероглиф
    Pinyin        # Пиньинь
    Translation   # Перевод
end

function parse_attribute_type(str::String)::Union{AttributeType, Nothing}
    let insts = instances(AttributeType),
        p = findfirst(==(Symbol(str)) ∘ Symbol, insts)
        return p !== nothing ? insts[p] : nothing
    end
end

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

# Конструктор с ключевыми аргументами
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

mutable struct WordStats
    level::Int                         # Уровень изученности для этого задания
    date_last_reviewed::DateTime       # Время последнего повторения для этого задания
    count_correct::Int                 # Количество правильных ответов для этого задания
    count_hint::Int                    # Количество ответов с подсказкой для этого задания
    count_incorrect::Int               # Количество неправильных ответов для этого задания
    review_history::Vector{RewievInfo} # История повторений
end

WordStats() = WordStats(0, now(), 0, 0, 0, Vector{RewievInfo}())

mutable struct Word
    id::String                          # Уникальный идентификатор слова (например, "hsk1.98", "duo.7" или "hsk3.487.a")
    hanzi::String                       # Иероглифы
    pinyin::String                      # Пиньинь (с цифровыми тонами)
    translation::String                 # Перевод
    context::String                     # Контекст (опционально, для уточнения значения)
    date_added::DateTime                # Время добаления слова
    date_last_reviewed_global::DateTime # Глобальное время с последнего повторения
    level_global::Int64                 # Глобальный уровень
    stats::Dict{Tuple{AttributeType, AttributeType}, WordStats} # Статистика для каждой подзадачи
    correlation_errors::Dict{AttributeType, Dict{String, Int64}}    # Ошибки, связанные с другими словами (ключи: Hanzi, Pinyin, Translation)
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
    t = now() - date_last_reviewed  # Время с последнего повторения
    p = 2^level                # Период полураспада зависит от уровня
    priority = (t / Minute(1)) / p  # Приоритет: время / период полураспада
    return priority
end
    
function calculate_memory_strength(level::Int, date_last_reviewed::DateTime)::Float64
    priority = calculate_priority(level, date_last_reviewed)
    return exp2(-priority)
end

function update_level(word_stats::WordStats, result::Int)
    old_level = word_stats.level
    date_last_reviewed = word_stats.date_last_reviewed

    priority = calculate_priority(old_level, date_last_reviewed)
    memory_strength = calculate_memory_strength(old_level, date_last_reviewed)
    new_level = old_level

    if result == 1  # Успешное воспоминание
        transition_probability = 1 - memory_strength
        while rand() < transition_probability
            new_level += 1
            corrected_memory_strength = calculate_memory_strength(new_level, date_last_reviewed)
            transition_probability = 1 - corrected_memory_strength
        end
    elseif result == -1  # Неудачное воспоминание
        transition_probability = memory_strength
        while rand() < transition_probability && new_level > 1
            new_level -= 1
            corrected_memory_strength = calculate_memory_strength(new_level, date_last_reviewed)
            transition_probability = corrected_memory_strength
        end
    end

    word_stats.level = new_level
    word_stats.date_last_reviewed = now()  # Обновляем время последнего повторения

    return old_level, new_level
end

function update_word_stats(word::Word, task_type::Tuple{AttributeType, AttributeType}, result::Int)
    word_stats = word.stats[task_type]

    # Обновление уровня
    old_level, new_level = update_level(word_stats, result)

    # Рассчет времени с последнего повторения
    time_interval_minutes = (now() - word_stats.date_last_reviewed) / Minute(1)

    # Добавление записи в историю
    push!(word_stats.review_history, RewievInfo(
        date_reviewed = now(),
        time_interval_minutes = time_interval_minutes,
        time_reaction_seconds = 0.0,  # Пока без учета времени реакции
        priority = calculate_priority(new_level, now()),
        memory_strength = calculate_memory_strength(new_level, now()),
        hint_used = (result == 0),
        result = result,
        level_old = old_level,
        level_new = new_level
    ))
end

function update_global_stats(word::Word)
    min_level = minimum(stat.level for stat in values(word.stats))
    word.level_global = min_level
    word.date_last_reviewed_global = now()
end

function update_word(word::Word, task_type::Tuple{AttributeType, AttributeType}, result::Int)
    # Обновляем статистику для конкретного задания
    update_word_stats(word, task_type, result)

    # Обновляем глобальную статистику слова
    update_global_stats(word)
end

struct WordPool
    known_words::Dict{String, Word}   # Слова, которые уже учатся
    new_words::Dict{String, Word}     # Слова, которые еще не изучались
end

WordPool() = WordPool(Dict{String, Word}(), Dict{String, Word}())

struct TrainingParams
    max_ephemeral_words::Int  # Максимальное количество слов в группе "ephemeral"
    max_fleeting_words::Int   # Максимальное количество слов в группах "ephemeral" + "fleeting"
    max_total_words::Int      # Максимальное общее количество слов в пуле для повторения
end

# Добавляем конструктор с ключевыми словами
function TrainingParams(; max_ephemeral_words::Int=5, max_fleeting_words::Int=20, max_total_words::Int=50)
    return TrainingParams(max_ephemeral_words, max_fleeting_words, max_total_words)
end

# Функция для изменения цвета текста
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
    # Финали группы 1: a, ai, an, ang, ao
    "ā" => "a1", "á" => "a2", "ǎ" => "a3", "à" => "a4",
    "āi" => "ai1", "ái" => "ai2", "ǎi" => "ai3", "ài" => "ai4",
    "ān" => "an1", "án" => "an2", "ǎn" => "an3", "àn" => "an4",
    "āng" => "ang1", "áng" => "ang2", "ǎng" => "ang3", "àng" => "ang4",
    "āo" => "ao1", "áo" => "ao2", "ǎo" => "ao3", "ào" => "ao4",
    # Финали группы 2: e, ei, en, eng, er
    "ē" => "e1", "é" => "e2", "ě" => "e3", "è" => "e4",
    "ēi" => "ei1", "éi" => "ei2", "ěi" => "ei3", "èi" => "ei4",
    "ēn" => "en1", "én" => "en2", "ěn" => "en3", "èn" => "en4",
    "ēng" => "eng1", "éng" => "eng2", "ěng" => "eng3", "èng" => "eng4",
    "ēr" => "er1", "ér" => "er2", "ěr" => "er3", "èr" => "er4",
    # Финали группы 3: i, ia, ian, iang, iao, ie, in, ing, iong
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
    # Финали группы 4: o, ong, ou
    "ō" => "o1", "ó" => "o2", "ǒ" => "o3", "ò" => "o4",
    "ōng" => "ong1", "óng" => "ong2", "ǒng" => "ong3", "òng" => "ong4",
    "ōu" => "ou1", "óu" => "ou2", "ǒu" => "ou3", "òu" => "ou4",
    # Финали группы 5: u, ua, uai, uan, uang, ue, ui, un, uo
    "ū" => "u1", "ú" => "u2", "ǔ" => "u3", "ù" => "u4",
    "ūa" => "ua1", "úa" => "ua2", "ǔa" => "ua3", "ùa" => "ua4",
    "ūai" => "uai1", "úai" => "uai2", "ǔai" => "uai3", "ùai" => "uai4",
    "ūan" => "uan1", "úan" => "uan2", "ǔan" => "uan3", "ùan" => "uan4",
    "ūang" => "uang1", "úang" => "uang2", "ǔang" => "uang3", "ùang" => "uang4",
    "ūe" => "ue1", "úe" => "ue2", "ǔe" => "ue3", "ùe" => "ue4",
    "ūi" => "ui1", "úi" => "ui2", "ǔi" => "ui3", "ùi" => "ui4",
    "ūn" => "un1", "ún" => "un2", "ǔn" => "un3", "ùn" => "un4",
    "ūo" => "uo1", "úo" => "uo2", "ǔo" => "uo3", "ùo" => "uo4",
    # Финали группы 6: ü, üe, üan, ün с четырьмя тонами и нейтральным тоном (ü заменено на v)
    "ǖ" => "v1", "ǘ" => "v2", "ǚ" => "v3", "ǜ" => "v4", "ü" => "v",
    "ǖe" => "ve1", "ǘe" => "ve2", "ǚe" => "ve3", "ǜe" => "ve4", "üe" => "ve",
    "ǖan" => "van1", "ǘan" => "van2", "ǚan" => "van3", "ǜan" => "van4", "üan" => "van",
    "ǖn" => "vn1", "ǘn" => "vn2", "ǚn" => "vn3", "ǜn" => "vn4", "ün" => "vn",
    "｜" => "|", "（" => "(", "）" => ")", "·" => ".", "’" => "'"
)

function convert_pinyin_string(pinyin_text::String, tone_map::Dict{String, String})::String
    # Сортируем финали по убыванию длины для поиска более длинных финалей в первую очередь
    sorted_finals = sort(collect(keys(tone_map)), by = x -> -length(x))

    result = ""
    current_word = ""

    i = 1
    while i <= lastindex(pinyin_text)
        match_found = false

        # Проверяем финали по списку, начиная с самой длинной
        for final in sorted_finals
            final_length = length(final)
            end_index = i
            valid = true

            # Безопасно продвигаем индекс вперед на длину финали
            for _ in 1:final_length - 1
                if end_index < lastindex(pinyin_text)
                    end_index = nextind(pinyin_text, end_index)
                else
                    valid = false
                    break
                end
            end

            # Проверяем, что подстрока соответствует финали
            if valid && end_index <= lastindex(pinyin_text) &&
               pinyin_text[i:end_index] == final
                match_found = true
                current_word *= tone_map[final]
                i = nextind(pinyin_text, end_index)  # Переходим на следующий индекс после финали
                break
            end
        end

        # Если совпадение не найдено, добавляем текущий символ и идем дальше
        if !match_found
            current_word *= pinyin_text[i]
            if i < lastindex(pinyin_text)
                i = nextind(pinyin_text, i)  # Переходим к следующему символу
            else
                i += 1  # Завершаем обработку строки, не выходя за границы
            end
        end

        # Проверяем, если текущий символ пробел, заканчиваем текущий слог
        if i > lastindex(pinyin_text) || (i <= lastindex(pinyin_text) && pinyin_text[i] == ' ')
            result *= current_word
            if i <= lastindex(pinyin_text)
                result *= " "  # Добавляем пробел, если он есть
            end
            current_word = ""
            if i < lastindex(pinyin_text)
                i = nextind(pinyin_text, i)
            else
                i += 1  # Завершаем обработку строки
            end
        end
    end

    # Добавляем последний оставшийся слог, если он есть
    result *= current_word

    return result
end

duolingo_list = ["水", "咖", "啡", "和", "茶", "米", "饭", "这", "是", "汤", "冰", "你", "的", "粥", "豆", "腐", "热", "英", "国", "美", "中", "人", "我", "好", "意", "大", "利", "呢", "文", "医", "生", "老", "师", "服", "务", "员", "对", "不", "说", "律", "学", "喜", "欢", "日", "本", "汉", "堡", "包", "菜", "音", "乐", "数", "课", "上", "网", "唱", "歌", "跑", "爸", "婆", "很", "高", "兴", "认", "识", "加", "拿", "她", "妈", "公", "旅", "行", "儿", "子", "他", "习", "也", "真", "吗", "女", "馆", "去", "书", "店", "超", "市", "吃", "口", "韩", "常", "亚", "洲", "买", "零", "食", "看", "谢", "杯", "要", "牛", "奶", "两", "绿", "客", "气", "李", "里", "在", "钱", "哪", "洗", "手", "间", "火", "车", "站", "机", "票", "第", "一", "二", "台", "个", "同", "新", "有", "叫", "什", "么", "名", "字", "丽", "节", "四", "今", "天", "都", "历", "史", "们", "打", "篮", "球", "还", "喝", "想", "明", "电", "影", "院", "园", "吧", "图", "书", "馆", "下", "午", "见", "果", "步", "哎", "呀", "房", "厅", "寓", "小", "漂", "亮", "厨", "发", "舒", "床", "空", "调", "没", "视", "月", "会", "北", "京", "飞", "怎", "坐", "场", "远", "出", "租", "地", "铁", "故", "长", "城", "交", "便", "宜", "件", "毛", "衣", "冷", "样", "那", "点", "克", "裤", "条", "短", "百", "贵", "元"]

# Функция для произношения текста на macOS с использованием голоса Tingting
function say_text(text::String, voice::String = "Tingting")
    # Добавляем паузы перед и после текста
    padded_text = "[[slnc 100]] $(text) [[slnc 100]]" # 100 мс пауза перед и после текста
    try
        run(`say -v $(voice) $(padded_text)`)
    catch e
        println("Ошибка: голос $(voice) не найден. Попробуй другой голос.")
    end
end

# Функция для произношения текста на macOS с использованием голоса Tingting
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
    # Добавляем паузы перед и после текста
    padded_text = "[[slnc 100]] $(text) [[slnc 100]]" # 100 мс пауза перед и после текста
    try
        run(`say -v $(voice) $(padded_text)`)
    catch e
        println("Ошибка: голос $(voice) не найден. Попробуй другой голос.")
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

function update_word_pool_from_file!(pool::WordPool, filename::String)
    # duolingo_mode1 = false
    # duolingo_mode2 = false
    # duolingo_mask = ones(Bool, length(duolingo_list))
    skip_key = false
    # Открытие файла и чтение построчно
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

            # Разделение строки на ханци, пиньинь и перевод
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

                # Проверяем, существует ли уже это слово в пуле известных слов
                is_known_word = haskey(pool.known_words, id)

                if is_known_word == false
                    # Если слово новое, добавляем его в пул новых слов
                    new_word = Word(id, hanzi, pinyin, translation, context)
                    pool.new_words[id] = new_word
                else
                    # println("Повторяющееся слово: ", hanzi)
                    # Обновляем информацию об уже известном слове 
                    existing_word = pool.known_words[id]
                    if existing_word.context != context
                        println("Обновленный контекст для слова $hanzi: ", context)
                        pool.known_words[id].context = context
                    end
                end
            else
                println("Неправильный формат строки: ", line)
            end
        end
    end
    # println("Слов с повторяющимся переводом: ", count_repeate_translation)
    # if duolingo_mode2 == true
    #     println(duolingo_list[duolingo_mask])
    # end
    println(colored_text("Пул слов обновлен из файла $filename", :blue))
end

# Преобразование строки в Tuple{AttributeType, AttributeType}
function string_to_task_tuple(task_str::String)::Tuple{AttributeType, AttributeType}
    parts = split(task_str, " -> ")
    if length(parts) == 2
        attr1 = parse_attribute_type(String(parts[1]))
        attr2 = parse_attribute_type(String(parts[2]))
        if attr1 !== nothing && attr2 !== nothing
            return (attr1, attr2)
        end
    end
    error("Некорректный формат строки задачи: $task_str")
end

# Преобразование Tuple{AttributeType, AttributeType} в строку
function task_tuple_to_string(task::Tuple{AttributeType, AttributeType})::String
    return string(task[1]) * " -> " * string(task[2])
end

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

    # Генерация форматированного JSON текста
    pretty_json = JSON.json(data, 4)

    # Запись в файл
    open(filename, "w") do file
        write(file, pretty_json)
    end

    println("Данные успешно сохранены в файл $filename")
end

function load_words_from_file(filename::String)::Dict{String, Word}
    try
        # Загружаем данные из JSON файла
        data = JSON.parsefile(filename)

        # Преобразуем данные в словарь {String, Word}
        words = Dict{String, Word}()
        for d in data
            # Создаём объект Word из словаря
            word = Word(
                d["id"],
                d["hanzi"],
                d["pinyin"],
                d["translation"],
                get(d, "context", ""),  # Контекст может быть пустым
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
            # Добавляем слово в словарь
            words[word.id] = word
        end
        return words
    catch e
        println("Ошибка при загрузке файла: ", e)
        return Dict{String, Word}()  # Возвращаем пустой словарь при ошибке
    end
end

function save_stats_to_file(known_words::Dict{String, Word}, filename::String)
    # Открытие файла для записи
    open(filename, "w") do file
        # Добавляем заголовки столбцов
        header = @sprintf("%-10s %-20s %-50s %-4s\t %-4s\t %-4s\t %-4s\t %-4s\t %-4s\t%-4s\t%-4s\t",
                          "Hanzi", "Pinyin", "Translation", "h->p", "h->t", "p->h", "p->t", "t->h", "t->p", "mean", "min")
        write(file, header * "\n")

        for word in values(known_words)
            # Формируем строку с информацией о слове
            line = @sprintf("%-10s %-20s %-50s", word.hanzi, word.pinyin, word.translation)

            # Извлекаем уровни для подзадач
            levels = [word.stats[(attribute2, attribute1)].level 
                      for attribute1 in instances(AttributeType), 
                          attribute2 in instances(AttributeType) 
                          if attribute1 != attribute2]

            # Рассчитываем средний и минимальный уровни
            mean_level = mean(levels)
            min_level = minimum(levels)

            # Форматируем уровни в одну строку, добавляя разделитель табуляции для выравнивания
            level_str = join([@sprintf("%4d", l) for l in levels], "\t")
            mean_level_str = @sprintf("%4.1f", mean_level)
            min_level_str = @sprintf("%4d", min_level)

            # Формируем полную строку
            line *= level_str * "\t" * mean_level_str * "\t" * min_level_str

            # Записываем строку в файл
            write(file, line * "\n")
        end
    end

    println(colored_text("Данные успешно сохранены в файл $filename", :blue))
end

# Функция для точного поиска слова
function contains_exact_word(keyword::String, text::String)::Bool
    words = split(text, r"\W+")  # Разделяем текст на слова (учитывая знаки препинания)
    return lowercase(keyword) in lowercase.(words)
end

function find_words_by_keywords(keywords::String, pool::WordPool; max_results::Int = 10)::Vector{Tuple{String, Word}}
    parts = split(keywords, ";", limit=2)
    translation_keywords = parts[1] != "" ? split(parts[1], "+") : []
    context_keywords = length(parts) > 1 && parts[2] != "" ? split(parts[2], "+") : []

    matching_words = Vector{Tuple{String, Word}}()

    # Поиск совпадений в переводе и контексте
    for word in values(pool.known_words)
        translation_match = all(kw -> contains_exact_word(String(kw), word.translation), translation_keywords)
        context_match = all(kw -> contains_exact_word(String(kw), word.context), context_keywords)
        
        if translation_match && context_match
            push!(matching_words, (word.translation, word))
        end
    end

    # Сортировка по длине перевода
    sort!(matching_words, by = x -> length(x[1]))

    # for i in 1:length(matching_words)
    #     println(matching_words[i][1])
    # end

    # Возвращаем первые max_results
    return matching_words[1:min(max_results, length(matching_words))]
end

function record_correlation_error(word::Word, attribute_type::AttributeType, input::String, pool::WordPool)
    if attribute_type == Translation
        # Для Translation `input` — это ID неверного слова
        if !haskey(word.correlation_errors[attribute_type], input)
            word.correlation_errors[attribute_type][input] = 0
        end
        word.correlation_errors[attribute_type][input] += 1
        println("Ошибка корреляции (Translation): добавлено совпадение с ID $input для атрибута $attribute_type.")
    else
        # Для Hanzi и Pinyin `input` — строка (иероглиф или пиньинь)
        for candidate_word in values(pool.known_words)
            if candidate_word.id != word.id  # Исключаем текущее слово
                if (attribute_type == Hanzi && candidate_word.hanzi == input) || (attribute_type == Pinyin && compare_pinyin(input, candidate_word.pinyin))
                    # Обновляем корреляцию
                    if !haskey(word.correlation_errors[attribute_type], candidate_word.id)
                        word.correlation_errors[attribute_type][candidate_word.id] = 0
                    end
                    word.correlation_errors[attribute_type][candidate_word.id] += 1
                    println("Ошибка корреляции (Hanzi/Pinyin): добавлено совпадение с ID $(candidate_word.id) для атрибута $(attribute_type).")
                    return  # Предполагаем, что одно значение `input` может совпадать только с одним словом
                end
            end
        end
        # println("Ошибка корреляции: соответствий для значения '$input' не найдено.")
    end
end

function task_hanzi(word::Word, pool::WordPool)
    println("\nЗадание: Нарисуйте иероглиф. Введите его с помощью китайской клавиатуры.")
    
    # Переменная для хранения попыток
    attempts = 0
    
    while attempts < 2
        attempts += 1
        println("Введите иероглиф:")
        run(`osascript -e 'tell application "System Events" to key code 49 using {shift down, control down}'`)
        user_input = readline()
        run(`osascript -e 'tell application "System Events" to key code 49 using {shift down, control down}'`)

        if user_input == word.hanzi
            if attempts == 1
                println(colored_text("Правильно с первой попытки!", :green))
                return 1
            else
                println(colored_text("Правильно со второй попытки!", :yellow))
                return 0
            end
        else
            println(colored_text("Неправильно. Попробуйте ещё раз.", :red))
            # Сохранение корреляции для неправильного ответа
            record_correlation_error(word, Hanzi, user_input, pool)
        end
    end

    # Если после двух попыток ответ неверный
    println(colored_text("Ответ неверный.", :yellow))
    println(colored_text("Правильный иероглиф: $(word.hanzi)", :green))
    return -1
end

function compare_pinyin(user_input::String, pinyin::String)
	user_input_no_spaces = replace(user_input, " " => "")
	pinyin_no_spaces     = replace(pinyin, " " => "")
	return user_input_no_spaces == pinyin_no_spaces
end

function task_pinyin(word::Word, pool::WordPool; sound=false)
    println("\nЗадание: Введите пиньинь с тонами (например, ni3 hao3).")
    
    # Переменная для хранения попыток
    attempts = 0
    
    while attempts < 2
        attempts += 1
        if sound
            say_text(word.hanzi)
        end
        println("Введите пиньинь:")
        user_input = readline()

        if compare_pinyin(user_input, word.pinyin)
            if attempts == 1
                println(colored_text("Правильно с первой попытки!", :green))
                return 1
            else
                println(colored_text("Правильно со второй попытки!", :yellow))
                return 0
            end
        else
            println(colored_text("Неправильно. Попробуйте ещё раз.", :red))
            # Сохранение корреляции для неправильного ответа
            record_correlation_error(word, Pinyin, user_input, pool)
        end
    end

    # Если после двух попыток ответ неверный
    println(colored_text("Ответ неверный.", :yellow))
    println(colored_text("Правильный пиньинь: $(word.pinyin)", :green))
    return -1
end

function task_translation(word::Word, pool::WordPool)
    println("Задание: Введите ключевые слова для перевода (например, 'have+not;context').")

    # Переменная для хранения попыток
    attempts = 0

    while attempts < 2
        attempts += 1
        user_input = readline()

        # Ищем подходящие слова по ключевым словам
        matching_words = find_words_by_keywords(user_input, pool)

        if isempty(matching_words)
            println(colored_text("Ни одно слово не соответствует введённым ключевым словам.", :red))
            if attempts < 2
                println("Попробуйте ввести ключевые слова ещё раз.")
                continue
            else
                println(colored_text("Ответ неверный", :yellow))
                println(colored_text("Правильный перевод: $(word.translation)", :green))
                if !isempty(word.context)
                    println(colored_text("Контекст: $(word.context)", :yellow))
                end
                return -1
            end
        end

        # Если есть совпадения, выводим список
        println("\nВыберите правильный перевод из предложенных вариантов:")
        for (i, (_, matched_word)) in enumerate(matching_words)
            # Добавляем перевод и контекст, если он есть
            context_str = isempty(matched_word.context) ? "" : " (контекст: $(matched_word.context))"
            println("[$i] $(matched_word.translation)$context_str")
        end

        # Получаем выбор пользователя
        selected_index = try
            parse(Int, readline())
        catch
            println(colored_text("Пожалуйста, введите номер из предложенного списка.", :yellow))
            attempts -= 1  # Не считать некорректный ввод за попытку
            continue
        end

        # Проверяем выбор
        if selected_index > 0 && selected_index <= length(matching_words)
            selected_word = matching_words[selected_index][2]
            if selected_word.id == word.id
                if attempts == 1
                    println(colored_text("Правильно с первой попытки!", :green))
                    return 1
                else
                    println(colored_text("Правильно со второй попытки!", :yellow))
                    return 0
                end
            else
                println(colored_text("Неправильно. Попробуйте ещё раз.", :red))
                # Сохранение корреляции (ID неверного перевода)
                record_correlation_error(word, Translation, selected_word.id, pool)
                if attempts == 2
                    println(colored_text("Ответ неверный", :yellow))
                    println(colored_text("Правильный перевод: $(word.translation)", :green))
                    if !isempty(word.context)
                        println(colored_text("Контекст: $(word.context)", :yellow))
                    end
                    return -1
                end
            end
        else
            println(colored_text("Неправильный выбор. Попробуйте ещё раз.", :yellow))
            attempts -= 1  # Некорректный выбор не засчитываем как попытку
        end
    end

    return -1
end

function train_from_hanzi(word::Word, pool::WordPool)
    println("Иероглиф слова: ", word.hanzi)

    # 1. Нарисовать иероглиф (квазитренировка, статистика не учитывается)
    task_hanzi(word, pool)

    # 2. Ввести пиньинь
    result_pinyin = task_pinyin(word, pool)
    update_word(word, (Hanzi, Pinyin), result_pinyin)

    # 3. Ввести перевод
    result_translation = task_translation(word, pool)
    update_word(word, (Hanzi, Translation), result_translation)
end

function train_from_pinyin(word::Word, pool::WordPool)
    # println("Пиньинь слова: ", word.pinyin)

    # 1. Ввести пиньинь (квазитренировка, статистика не учитывается)
    task_pinyin(word, pool, sound=true)

    # 2. Указать иероглиф
    result_hanzi = task_hanzi(word, pool)
    update_word(word, (Pinyin, Hanzi), result_hanzi)

    # 3. Указать перевод
    result_translation = task_translation(word, pool)
    update_word(word, (Pinyin, Translation), result_translation)
end

function train_from_translation(word::Word, pool::WordPool)
    println("Перевод слова: ", word.translation)
    if !isempty(word.context)
        println("Контекст: $(colored_text(word.context, :yellow))")
    end

    # 1. Найти перевод (квазитренировка, статистика не учитывается)
    # task_translation(word, pool)

    # 2. Указать иероглиф
    result_hanzi = task_hanzi(word, pool)
    update_word(word, (Translation, Hanzi), result_hanzi)

    # 3. Ввести пиньинь
    result_pinyin = task_pinyin(word, pool)
    update_word(word, (Translation, Pinyin), result_pinyin)
end

function train_word(word::Word, pool::WordPool)
    run(`clear`)
    if isempty(word.stats)
        println("Нет статистики для слова: ", word.id)
        return
    end

    # Выбор атрибута с минимальным уровнем
    attibute_to_train_from = argmin(x -> x[2].level, word.stats)[1][1]
    # attibute_to_train_from = findmin([(key, stats.level) for (key, stats) in word.stats])
    println("Тренируем атрибут: ", attibute_to_train_from)

    if attibute_to_train_from == Hanzi
        train_from_hanzi(word, pool)
    elseif attibute_to_train_from == Pinyin
        train_from_pinyin(word, pool)
    elseif attibute_to_train_from == Translation
        train_from_translation(word, pool)
    else
        println("Неизвестный атрибут для тренировки: ", attibute_to_train_from)
    end

    say_text(word.hanzi)
end

# Функция для создания словаря градаций на основе глобального уровня
function calculate_gradations(pool::WordPool)::Dict{String, Int}
    # Инициализация градаций
    gradations = Dict("ephemeral" => 0, "fleeting" => 0, "short-term" => 0, "transition" => 0, "long-term" => 0, "permanent" => 0)

    # Распределяем слова по градациям на основе их глобального уровня
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

function should_add_new_word(pool::WordPool, params::TrainingParams)::Bool
    # Считаем градации слов
    gradations = calculate_gradations(pool)

    # Считаем количество слов с высоким глобальным приоритетом
    high_priority_count = 0
    for word in values(pool.known_words)
        global_priority = calculate_priority(word.level_global, word.date_last_reviewed_global)
        if global_priority >= 1
            high_priority_count += 1
        end
    end

    # Если нет слов с высоким приоритетом
    if high_priority_count == 0
        println("Нет слов с высоким приоритетом для повторения. Хотите добавить новое слово? (y/n)")
        while true
            user_input = readline()
            if user_input == "y"
                return true
            elseif user_input == "n"
                return false
            else
                println("Пожалуйста, введите 'y' или 'n'.")
            end
        end
    end

    # Проверяем ограничения по градациям
    if gradations["ephemeral"] < params.max_ephemeral_words
        return true  # Добавляем новое слово, чтобы поддерживать активную фазу обучения
    elseif gradations["ephemeral"] + gradations["fleeting"] >= params.max_fleeting_words
        return false  # Не добавляем, если активных слов слишком много
    elseif high_priority_count >= params.max_total_words
        return false  # Не добавляем, если слишком много слов для повторения
    else
        return false  # Во всех других случаях новое слово не добавляется
    end
end

function select_random_word!(pool::WordPool)::Union{Word, Nothing}
    if isempty(pool.new_words)
        println("Пул новых слов пуст.")
        return nothing
    end

    # Выбираем случайный ключ из словаря новых слов
    random_key = rand(collect(keys(pool.new_words)))
    selected_word = pool.new_words[random_key]

    # Удаляем слово из новых слов и добавляем в известные
    delete!(pool.new_words, random_key)
    pool.known_words[random_key] = selected_word

    println("Добавлено новое слово для изучения: ", selected_word.hanzi)
    return selected_word
end

function introduce_new_word(word::Word, pool::WordPool)
    run(`clear`)
    println(colored_text("Новое слово для изучения:", :blue))
    println("Иероглиф: $(colored_text(word.hanzi, :green))")
    println("Пиньинь: $(colored_text(word.pinyin, :green))")
    println("Перевод: $(colored_text(word.translation, :green))")
    if !isempty(word.context)
        println("Контекст: $(colored_text(word.context, :yellow))")
    end

    println("\nПопробуй запомнить это слово, а затем мы приступим к тренировке.")
    println("Нажми Enter, чтобы продолжить.")
    readline()

    # 1. Нарисовать иероглиф
    task_hanzi(word, pool)

    # 2. Ввести пиньинь
    task_pinyin(word, pool, sound=true)
 
    # 3. Ввести перевод
    task_translation(word, pool)
end

function start_training_session(pool::WordPool, params::TrainingParams)
    while true
        # 1. Проверяем, нужно ли добавить новое слово
        if should_add_new_word(pool, params)
            new_word = select_random_word!(pool)
            if new_word !== nothing
                # Добавляем новое слово в известные слова
                pool.known_words[new_word.id] = new_word
                # Удаляем слово из новых слов
                delete!(pool.new_words, new_word.id)
                # Знакомим пользователя с новым словом
                introduce_new_word(new_word, pool)
            end
        end

        # 2. Формируем пул слов для тренировки
        training_words = []
        for word in values(pool.known_words)
            global_priority = calculate_priority(word.level_global, word.date_last_reviewed_global)

            # Добавляем слова с приоритетом > 1 или с уровнем 0
            if global_priority > 1 || word.level_global == 0
                push!(training_words, word)
            end
        end

        # Если нет слов для тренировки, завершаем сессию
        if isempty(training_words)
            println("Нет слов для тренировки. Вы можете добавить новые слова или вернуться позже.")
            break
        end

        # Выбираем случайные слова для тренировки (например, 5 слов)
        training_batch = sample(training_words, min(5, length(training_words)), replace=false)

        # 3. Проводим тренировку для каждого слова
        for word in training_batch
            println("")
            train_word(word, pool)  # Используем функцию тренировки для слова
        end

        # 4. Сохраняем результаты после каждого круга тренировок
        save_words_to_file(pool.known_words, "ChineseSave.json")
        save_stats_to_file(pool.known_words, "ChineseStats.txt")

        # Спрашиваем пользователя, хочет ли он продолжить тренировку
        println("\nХотите продолжить тренировку? (нажмите Enter для продолжения или введите 'exit' для выхода)")
        user_input = readline()
        if user_input == "exit"
            println("Тренировка завершена.")
            break
        end
    end
end

function main()
    pool = WordPool()
    pool = WordPool(load_words_from_file("ChineseSave.json"), Dict{String, Word}())
    params = TrainingParams()
    
    # Обновляем пул слов из файла vocabulary.txt
    update_word_pool_from_file!(pool, "ChineseVocabulary.txt")
    
    # erase_history(pool)

    # display_statistics(pool)
    start_training_session(pool, params)
    # save_words_to_file(pool.known_words, "ChineseSave.json")
    # save_stats_to_file(pool.known_words, "ChineseStats.txt")

end

main()
