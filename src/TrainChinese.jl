module TrainChinese

# Keep the implementation in a single place.
# When used as a package ("using TrainChinese"), this includes definitions
# without auto-running the interactive CLI.
include(joinpath(@__DIR__, "..", "train_chinese.jl"))

export main

end
