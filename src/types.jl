"""
Enum describing which attribute of a word is being trained or recalled.

- `Hanzi`: Chinese characters
- `Pinyin`: pinyin with tone numbers
- `Translation`: English translation (plus optional context)
"""
@enum AttributeType begin
    Hanzi         # Hanzi (Chinese characters)
    Pinyin        # Pinyin
    Translation   # Translation
end

"""Parse a string like `"Hanzi"` into an `AttributeType`.

Returns `nothing` if the string does not match any enum value.
"""
function parse_attribute_type(str::String)::Union{AttributeType, Nothing}
    let insts = instances(AttributeType),
        p = findfirst(==(Symbol(str)) ∘ Symbol, insts)
        return p !== nothing ? insts[p] : nothing
    end
end

"""Single review event (one attempt sequence) captured for analytics and scheduling."""
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

# Keyword-argument constructor
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

"""Per-task statistics for a word.

Each word is trained as multiple directed tasks (e.g. `Hanzi -> Pinyin`).
This struct stores the spaced-repetition level and review history for one such task.
"""
mutable struct WordStats
    level::Int                         # Learning level for this task
    date_last_reviewed::DateTime       # Last review time for this task
    count_correct::Int                 # Number of correct answers for this task
    count_hint::Int                    # Number of answers with a hint for this task
    count_incorrect::Int               # Number of incorrect answers for this task
    review_history::Vector{RewievInfo} # Review history
end

WordStats() = WordStats(0, now(), 0, 0, 0, Vector{RewievInfo}())

"""Vocabulary item tracked by the trainer.

Fields include the word itself (`hanzi`, `pinyin`, `translation`, optional `context`),
global spaced-repetition level, and per-task stats for all attribute pairs.

`correlation_errors` is used to capture common confusions (e.g. mixing up similar hanzi).
"""
mutable struct Word
    id::String                          # Unique word ID (e.g. "hsk1.98", "duo.7", or "hsk3.487.a")
    hanzi::String                       # Hanzi
    pinyin::String                      # Pinyin (with tone numbers)
    translation::String                 # Translation
    context::String                     # Optional context for disambiguation
    date_added::DateTime                # Time when the word was added
    date_last_reviewed_global::DateTime # Global time since last review
    level_global::Int64                 # Global level
    stats::Dict{Tuple{AttributeType, AttributeType}, WordStats} # Per-task stats
    correlation_errors::Dict{AttributeType, Dict{String, Int64}}    # Correlation errors with other words (keys: Hanzi, Pinyin, Translation)
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

"""Container holding two word pools.

- `known_words`: words currently being trained (have progress)
- `new_words`: words available to be introduced
"""
struct WordPool
    known_words::Dict{String, Word}   # Words currently being learned
    new_words::Dict{String, Word}     # Words not studied yet
end

WordPool() = WordPool(Dict{String, Word}(), Dict{String, Word}())

struct TrainingParams
    max_ephemeral_words::Int  # Maximum number of words in the "ephemeral" group
    max_fleeting_words::Int   # Maximum number of words in "ephemeral" + "fleeting"
    max_total_words::Int      # Maximum total number of words eligible for review
end

# Keyword-argument constructor
function TrainingParams(; max_ephemeral_words::Int=5, max_fleeting_words::Int=20, max_total_words::Int=50)
    return TrainingParams(max_ephemeral_words, max_fleeting_words, max_total_words)
end
