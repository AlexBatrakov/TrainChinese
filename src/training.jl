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
    attribute_to_train_from = argmin(x -> x[2].level, word.stats)[1][1]
    println("Training attribute: ", attribute_to_train_from)

    if attribute_to_train_from == Hanzi
        train_from_hanzi(word, pool)
    elseif attribute_to_train_from == Pinyin
        train_from_pinyin(word, pool)
    elseif attribute_to_train_from == Translation
        train_from_translation(word, pool)
    else
        println("Unknown attribute to train: ", attribute_to_train_from)
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

"""Display learning statistics for the current word pool.

This is a convenience function intended for interactive use from the REPL.
It prints:
- total known/new words
- distribution of words across coarse learning phases (based on `level_global`)
- per-task averages and priority counts for the six directed tasks
"""
function display_statistics(pool::WordPool)
    total_known = length(pool.known_words)
    total_new = length(pool.new_words)

    gradations = calculate_gradations(pool)
    gradation_labels = [
        ("ephemeral",  "Ephemeral:      (≤ 16 minutes)"),
        ("fleeting",   "Fleeting:       (≤ 4 hours)"),
        ("short-term", "Short-term:     (≤ 68 hours)"),
        ("transition", "Transition:     (≤ 45 days)"),
        ("long-term",  "Long-term:      (≤ 2 years)"),
        ("permanent",  "Permanent:      (≥ 2 years)")
    ]

    println("Statistics:")
    println("Known words: ", total_known)
    println("New words:   ", total_new)

    println("\nWords by memory phase (based on global level):")
    for (key, label) in gradation_labels
        println(rpad(label, 30), " ", get(gradations, key, 0))
    end

    task_specs = [
        ("Hanzi → Pinyin",       (Hanzi, Pinyin)),
        ("Hanzi → Translation",  (Hanzi, Translation)),
        ("Pinyin → Hanzi",       (Pinyin, Hanzi)),
        ("Pinyin → Translation", (Pinyin, Translation)),
        ("Translation → Hanzi",  (Translation, Hanzi)),
        ("Translation → Pinyin", (Translation, Pinyin))
    ]

    for (task_name, task_type) in task_specs
        total_level = 0
        total_priority = 0.0
        high_priority_count = 0
        medium_priority_count = 0

        for word in values(pool.known_words)
            word_stats = word.stats[task_type]
            total_level += word_stats.level

            word_priority = calculate_priority(word_stats.level, word_stats.date_last_reviewed)
            if word_priority >= 1
                high_priority_count += 1
            elseif word_priority >= 0.5
                medium_priority_count += 1
            end
            total_priority += word_priority
        end

        avg_task_level = total_known > 0 ? total_level / total_known : 0.0
        avg_task_priority = total_known > 0 ? total_priority / total_known : 0.0

        println("\nTask stats: ", task_name)
        println("Average level: ", @sprintf("%.2f", avg_task_level))
        println("High priority (≥ 1.0): ", high_priority_count)
        println("Medium priority (0.5–1.0): ", medium_priority_count)
        println("Average priority: ", @sprintf("%.3f", avg_task_priority))
    end

    return nothing
end

function _plotting_ext()
    return Base.get_extension(TrainChinese, :TrainChinesePyPlotExt)
end

function _plotting_install_hint()
    return "Install it with one of:\n" *
           "  - `trainchinese --install-plotting` (recommended)\n" *
           "  - `julia --project=cli -e 'import Pkg; Pkg.instantiate()'`"
end

"""Plot review history for known words across the six directed tasks.

This functionality is optional and requires `PyPlot` installed in the active
project environment.
"""
function plot_word_review_history(pool::WordPool; show_plot::Bool=true, save_path::Union{Nothing, String}=nothing)
    ext = _plotting_ext()
    ext === nothing && throw(ArgumentError("Plotting requires PyPlot, but it is not available.\n" * _plotting_install_hint()))
    return ext.plot_word_review_history(pool; show_plot=show_plot, save_path=save_path)
end

"""Plot per-task review history (colors = tasks).

This is a clearer name for the plot implemented by `plot_word_review_history`.
"""
function plot_task_review_history(pool::WordPool; show_plot::Bool=true, save_path::Union{Nothing, String}=nothing)
    return plot_word_review_history(pool; show_plot=show_plot, save_path=save_path)
end

"""Plot per-word learning history (one line per word).

This functionality is optional and requires `PyPlot` installed in the active
project environment.
"""
function plot_review_history(words::Vector{Word}; max_words::Int=40, annotate::Bool=true, show_plot::Bool=true, save_path::Union{Nothing, String}=nothing)
    ext = _plotting_ext()
    ext === nothing && throw(ArgumentError("Plotting requires PyPlot, but it is not available.\n" * _plotting_install_hint()))
    return ext.plot_review_history(words; max_words=max_words, annotate=annotate, show_plot=show_plot, save_path=save_path)
end

"""Plot per-word learning history (one line per word, annotated with Hanzi).

This is a clearer name for the plot implemented by `plot_review_history`.
"""
function plot_word_learning_history(words::Vector{Word}; max_words::Int=40, annotate::Bool=true, show_plot::Bool=true, save_path::Union{Nothing, String}=nothing)
    return plot_review_history(words; max_words=max_words, annotate=annotate, show_plot=show_plot, save_path=save_path)
end

"""Convenience overload: plot per-word learning history for `pool.known_words`."""
function plot_review_history(pool::WordPool; max_words::Int=40, annotate::Bool=true, show_plot::Bool=true, save_path::Union{Nothing, String}=nothing)
    words = collect(values(pool.known_words))
    return plot_review_history(words; max_words=max_words, annotate=annotate, show_plot=show_plot, save_path=save_path)
end

"""Convenience overload: plot per-word learning history for `pool.known_words`.

This is a clearer name for the plot implemented by `plot_review_history`.
"""
function plot_word_learning_history(pool::WordPool; max_words::Int=40, annotate::Bool=true, show_plot::Bool=true, save_path::Union{Nothing, String}=nothing)
    return plot_review_history(pool; max_words=max_words, annotate=annotate, show_plot=show_plot, save_path=save_path)
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
function start_training_session(pool::WordPool, params::TrainingParams;
    save_path::String="ChineseSave.json",
    stats_path::String="ChineseStats.txt")
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
        save_words_to_file(pool.known_words, save_path)
        save_stats_to_file(pool.known_words, stats_path)

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
function main(; save_path::String="ChineseSave.json",
    vocab_path::String="ChineseVocabulary.txt",
    stats_path::String="ChineseStats.txt")
    pool = WordPool(load_words_from_file(save_path), Dict{String, Word}())
    params = TrainingParams()

    # Update the word pool from the vocabulary file
    update_word_pool_from_file!(pool, vocab_path)

    start_training_session(pool, params; save_path=save_path, stats_path=stats_path)
end
