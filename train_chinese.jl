# Thin CLI entrypoint.
#
# - Works as before: `julia train_chinese.jl`
# - Recommended: `julia --project=. train_chinese.jl`
# - When used as a package: `using TrainChinese; TrainChinese.main()`

# Try to load the package from the current environment first.
# If that fails (common when running without `--project=.`), fall back to
# activating the local project environment.
try
    @eval using TrainChinese
catch
    import Pkg
    Pkg.activate(@__DIR__)
    @eval using TrainChinese
end

if abspath(PROGRAM_FILE) == @__FILE__
    TrainChinese.main()
end
