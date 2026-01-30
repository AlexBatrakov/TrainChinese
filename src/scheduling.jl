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
