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
