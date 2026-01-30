# Thin CLI entrypoint.
#
# - Works as before: `julia train_chinese.jl`
# - Recommended: `julia --project=. train_chinese.jl`
# - When used as a package: `using TrainChinese; TrainChinese.main()`

using TOML

function _print_help()
    println("TrainChinese — terminal Chinese vocabulary trainer")
    println("")
    println("Usage:")
    println("  julia --project=. train_chinese.jl                # start interactive training (default)")
    println("  julia --project=. train_chinese.jl --stats        # print current pool statistics and exit")
    println("  julia --project=. train_chinese.jl --plot-history # plot learning history and exit")
    println("  julia --project=. train_chinese.jl --version      # print version and exit")
    println("  julia --project=. train_chinese.jl --help         # show this help and exit")
    println("")
    println("Notes:")
    println("  - Plotting uses PyPlot; it may require a working matplotlib installation.")
end

function _print_version(project_dir::String)
    try
        proj = TOML.parsefile(joinpath(project_dir, "Project.toml"))
        version = get(proj, "version", "unknown")
        println("TrainChinese v", version)
    catch
        println("TrainChinese (version unknown)")
    end
end

function _load_pool(save_path::String, vocab_path::String)
    pool = TrainChinese.WordPool(TrainChinese.load_words_from_file(save_path), Dict{String, TrainChinese.Word}())
    TrainChinese.update_word_pool_from_file!(pool, vocab_path)
    return pool
end

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
    # Minimal argument handling.
    # Default remains unchanged: no args -> interactive training session.
    if any(x -> x in ("--help", "-h"), ARGS)
        _print_help()
        exit(0)
    elseif any(x -> x in ("--version", "-V"), ARGS)
        _print_version(@__DIR__)
        exit(0)
    elseif any(==("--stats"), ARGS)
        pool = _load_pool("ChineseSave.json", "ChineseVocabulary.txt")
        TrainChinese.display_statistics(pool)
        exit(0)
    elseif any(==("--plot-history"), ARGS)
        pool = _load_pool("ChineseSave.json", "ChineseVocabulary.txt")
        TrainChinese.plot_review_history(pool)
        exit(0)
    elseif !isempty(ARGS)
        println("Unknown arguments: ", join(ARGS, " "))
        println("")
        _print_help()
        exit(2)
    else
        TrainChinese.main()
    end
end
