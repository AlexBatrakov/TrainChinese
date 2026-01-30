module TrainChinese

using Dates
using JSON
using Statistics
using Random
using Printf
using PyPlot
using StatsBase

include("types.jl")
include("scheduling.jl")
include("ui.jl")
include("pinyin.jl")
include("platform_macos.jl")
include("vocabulary.jl")
include("persistence.jl")
include("search.jl")
include("tasks.jl")
include("training.jl")

export main, display_statistics, plot_word_review_history

end
