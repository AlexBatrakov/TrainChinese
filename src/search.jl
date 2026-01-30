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

    # Return first max_results
    return matching_words[1:min(max_results, length(matching_words))]
end
