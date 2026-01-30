using Test
using Dates
using Random

using TrainChinese

@testset "TrainChinese basics" begin
    @test TrainChinese.parse_attribute_type("Hanzi") == TrainChinese.Hanzi
    @test TrainChinese.parse_attribute_type("Pinyin") == TrainChinese.Pinyin
    @test TrainChinese.parse_attribute_type("Translation") == TrainChinese.Translation
    @test TrainChinese.parse_attribute_type("Nope") === nothing

    # Priority increases with elapsed time and decreases with level.
    now_dt = DateTime(2026, 1, 30, 12, 0, 0)
    earlier_dt = now_dt - Minute(60)
    later_dt = now_dt - Minute(10)

    # compute using the same formula with fixed datetimes
    p1 = (now_dt - earlier_dt) / Minute(1) / (2^0)
    p2 = (now_dt - later_dt) / Minute(1) / (2^0)
    @test p1 > p2

    p_low_level = (now_dt - earlier_dt) / Minute(1) / (2^1)
    @test p_low_level < p1

    # Pinyin conversion sanity check
    @test TrainChinese.convert_pinyin_string("nǐ hǎo", TrainChinese.tone_map) == "ni3 hao3"
    @test TrainChinese.compare_pinyin("ni3hao3", "ni3 hao3")
    @test TrainChinese.compare_pinyin("ni3 hao3", "ni3hao3")
    @test TrainChinese.convert_pinyin_string("lǜ sè", TrainChinese.tone_map) == "lv4 se4"

    # Statistics function should be callable (no throw)
    pool = TrainChinese.WordPool()
    w = TrainChinese.Word("test.1", "你好", "ni3 hao3", "hello", "")
    pool.known_words[w.id] = w

    @test TrainChinese.display_statistics(pool) === nothing

    # Plotting helpers exist (but are intentionally not executed in tests/CI,
    # because PyPlot/PyCall can segfault on headless runners).
    @test !isempty(methods(TrainChinese.plot_word_review_history))
    @test !isempty(methods(TrainChinese.plot_review_history))
end

@testset "Scheduling math" begin
    older = now() - Minute(120)
    recent = now() - Minute(10)

    # Priority grows with elapsed time.
    @test TrainChinese.calculate_priority(0, older) > TrainChinese.calculate_priority(0, recent)

    # Priority decreases with level (higher half-life).
    @test TrainChinese.calculate_priority(4, older) < TrainChinese.calculate_priority(0, older)

    # Memory strength is a probability-like value (0..1) that decays with priority.
    ms_older = TrainChinese.calculate_memory_strength(0, older)
    ms_recent = TrainChinese.calculate_memory_strength(0, recent)
    @test 0.0 <= ms_older <= 1.0
    @test 0.0 <= ms_recent <= 1.0
    @test ms_older < ms_recent
end

@testset "Level updates and stats" begin
    # calculate_new_level(): result=0 is a no-op.
    ws = TrainChinese.WordStats(3, now() - Minute(30), 0, 0, 0, TrainChinese.RewievInfo[])
    Random.seed!(1234)
    @test TrainChinese.calculate_new_level(ws, 0) == 3

    # Successful recall should never decrease the level.
    Random.seed!(1234)
    @test TrainChinese.calculate_new_level(ws, 1) >= 3

    # Failed recall should never increase the level; it bottoms out at 1.
    Random.seed!(1234)
    lvl_fail = TrainChinese.calculate_new_level(ws, -1)
    @test 1 <= lvl_fail <= 3

    # update_word_stats() appends a history entry and updates timestamps.
    word = TrainChinese.Word("w.1", "你", "ni3", "you", "")
    task = (TrainChinese.Hanzi, TrainChinese.Pinyin)
    word.stats[task].level = 2
    word.stats[task].date_last_reviewed = now() - Minute(45)

    t_before = now()
    Random.seed!(1234)
    TrainChinese.update_word_stats(word, task, 1)

    @test length(word.stats[task].review_history) == 1
    ev = word.stats[task].review_history[end]
    @test ev.result == 1
    @test ev.level_old == 2
    @test word.stats[task].level == ev.level_new
    @test word.stats[task].date_last_reviewed >= t_before
    @test ev.time_interval_minutes > 0

    # update_global_stats(): global level is the minimum across tasks.
    for st in values(word.stats)
        st.level = 5
    end
    word.stats[(TrainChinese.Translation, TrainChinese.Hanzi)].level = 2
    TrainChinese.update_global_stats(word)
    @test word.level_global == 2
end

@testset "Persistence round-trip" begin
    word = TrainChinese.Word("w.save", "好", "hao3", "good", "")
    task = (TrainChinese.Hanzi, TrainChinese.Pinyin)
    word.stats[task].level = 7

    mktemp() do path, io
        close(io)
        TrainChinese.save_words_to_file(Dict(word.id => word), path)
        loaded = TrainChinese.load_words_from_file(path)

        @test haskey(loaded, word.id)
        w2 = loaded[word.id]
        @test w2.hanzi == word.hanzi
        @test w2.pinyin == word.pinyin
        @test w2.translation == word.translation
        @test w2.stats[task].level == 7
    end
end

@testset "Vocabulary file parsing" begin
    @test TrainChinese.cut_hanzi("你好（context）") == ("你好", "（context）")
    @test TrainChinese.cut_hanzi("你好（一）") == ("你好（一）", "")

    pool = TrainChinese.WordPool()
    pool.known_words["w.known"] = TrainChinese.Word("w.known", "你", "ni3", "you", "old")

    mktemp() do path, io
        write(io, "# comment\n")
        write(io, "w.new | 你好 | nǐ hǎo | hello | greeting\n")
        write(io, "SKIP\n")
        write(io, "w.skip | 水 | shuǐ | water |\n")
        write(io, "SKIP\n")
        write(io, "w.known | 你 | nǐ | you | updated\n")
        write(io, "STOP\n")
        close(io)

        TrainChinese.update_word_pool_from_file!(pool, path)

        @test haskey(pool.new_words, "w.new")
        @test !haskey(pool.new_words, "w.skip")
        @test pool.new_words["w.new"].pinyin == "ni3 hao3"
        @test pool.known_words["w.known"].context == "updated"
    end
end
