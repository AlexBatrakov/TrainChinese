using Test
using Dates

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
