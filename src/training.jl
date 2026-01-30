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

"""Plot review history for known words across the six directed tasks.

The plot shows how the per-task spaced-repetition level changes over time.
Time is measured in minutes since the first review within each word+task history.

Keyword args:
- `show_plot::Bool=true`: call `PyPlot.show()` at the end (set to `false` for tests / headless runs).
"""
function plot_word_review_history(pool::WordPool; show_plot::Bool=true)
    task_specs = [
        ("Hanzi → Pinyin",       (Hanzi, Pinyin)),
        ("Hanzi → Translation",  (Hanzi, Translation)),
        ("Pinyin → Hanzi",       (Pinyin, Hanzi)),
        ("Pinyin → Translation", (Pinyin, Translation)),
        ("Translation → Hanzi",  (Translation, Hanzi)),
        ("Translation → Pinyin", (Translation, Pinyin))
    ]

    colors = ["red", "blue", "green", "orange", "purple", "cyan"]

    PyPlot.figure(figsize=(10, 6))

    labeled = fill(false, length(task_specs))

    for (task_index, (task_label, task_type)) in enumerate(task_specs)
        color = colors[task_index]

        for word in values(pool.known_words)
            history = word.stats[task_type].review_history
            isempty(history) && continue

            t0 = history[1].date_reviewed
            times = [(h.date_reviewed - t0) / Minute(1) for h in history]
            levels = [h.level_new for h in history]

            if length(times) >= 2
                label = labeled[task_index] ? "_nolegend_" : task_label
                PyPlot.plot(times[2:end], levels[2:end] .+ 0.15 * task_index, ".", color=color, label=label)
                labeled[task_index] = true
            end
        end
    end

    PyPlot.xlabel("Time since first review (minutes)")
    PyPlot.ylabel("Word level")
    PyPlot.title("Review history by task")
    PyPlot.grid(true)
    PyPlot.tight_layout()
    PyPlot.xscale("log")
    PyPlot.legend(loc="upper left", bbox_to_anchor=(1, 1))

    if show_plot
        PyPlot.show()
    end

    return nothing
end

"""Plot per-word learning history (one line per word).

This is an adaptation of an older helper that plotted a single trajectory per word
and annotated the last point with hanzi.

Because the current data model stores review history per *task* (e.g. `Hanzi → Pinyin`),
this function reconstructs an approximate *global* level history by:
1) merging all per-task review events for the word
2) replaying them in chronological order
3) recomputing the global level as the minimum across task levels after each event

Keyword args:
- `max_words::Int=40`: limit plotted words to avoid unreadable clutter
- `annotate::Bool=true`: annotate the last point with hanzi
- `show_plot::Bool=true`: call `PyPlot.show()` (set `false` for tests/headless)
"""
function plot_review_history(words::Vector{Word}; max_words::Int=40, annotate::Bool=true, show_plot::Bool=true)
    PyPlot.figure(figsize=(10, 6))
    PyPlot.title("Word learning history")
    PyPlot.xlabel("Time")
    PyPlot.ylabel("Global level (min across tasks)")

    offset_step = 0.10
    offset_index = 0

    # To keep the plot readable: use the first N words.
    for word in Iterators.take(words, max_words)
        # Build merged event list: (date, task_type, level_new)
        events = Vector{Tuple{DateTime, Tuple{AttributeType, AttributeType}, Int}}()
        for (task_type, stats) in word.stats
            for h in stats.review_history
                push!(events, (h.date_reviewed, task_type, h.level_new))
            end
        end

        isempty(events) && continue
        sort!(events, by = e -> e[1])

        # Replay to reconstruct global level over time.
        task_levels = Dict(task => 0 for task in keys(word.stats))
        times = DateTime[]
        global_levels = Int[]
        for (dt, task_type, level_new) in events
            task_levels[task_type] = level_new
            push!(times, dt)
            push!(global_levels, minimum(values(task_levels)))
        end

        PyPlot.plot(times, global_levels, linewidth=2)

        if annotate
            y_offset = offset_step * ((offset_index % 2 == 0) ? 1 : -1)
            PyPlot.annotate(word.hanzi, (times[end], global_levels[end] + y_offset),
                fontsize=12, fontname="Arial Unicode MS", ha="left")
            offset_index += 1
        end
    end

    PyPlot.grid(true)
    PyPlot.tight_layout()

    if show_plot
        PyPlot.show()
    end

    return nothing
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

    start_training_session(pool, params)
end
