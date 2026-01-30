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
