duolingo_list = ["水", "咖", "啡", "和", "茶", "米", "饭", "这", "是", "汤", "冰", "你", "的", "粥", "豆", "腐", "热", "英", "国", "美", "中", "人", "我", "好", "意", "大", "利", "呢", "文", "医", "生", "老", "师", "服", "务", "员", "对", "不", "说", "律", "学", "喜", "欢", "日", "本", "汉", "堡", "包", "菜", "音", "乐", "数", "课", "上", "网", "唱", "歌", "跑", "爸", "婆", "很", "高", "兴", "认", "识", "加", "拿", "她", "妈", "公", "旅", "行", "儿", "子", "他", "习", "也", "真", "吗", "女", "馆", "去", "书", "店", "超", "市", "吃", "口", "韩", "常", "亚", "洲", "买", "零", "食", "看", "谢", "杯", "要", "牛", "奶", "两", "绿", "客", "气", "李", "里", "在", "钱", "哪", "洗", "手", "间", "火", "车", "站", "机", "票", "第", "一", "二", "台", "个", "同", "新", "有", "叫", "什", "么", "名", "字", "丽", "节", "四", "今", "天", "都", "历", "史", "们", "打", "篮", "球", "还", "喝", "想", "明", "电", "影", "院", "园", "吧", "图", "书", "馆", "下", "午", "见", "果", "步", "哎", "呀", "房", "厅", "寓", "小", "漂", "亮", "厨", "发", "舒", "床", "空", "调", "没", "视", "月", "会", "北", "京", "飞", "怎", "坐", "场", "远", "出", "租", "地", "铁", "故", "长", "城", "交", "便", "宜", "件", "毛", "衣", "冷", "样", "那", "点", "克", "裤", "条", "短", "百", "贵", "元"]

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

    println(colored_text("Word pool updated from file $filename", :blue))
end
