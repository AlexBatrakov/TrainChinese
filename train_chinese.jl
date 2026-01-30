# Thin CLI entrypoint.
#
# - Works as before: `julia train_chinese.jl`
# - Recommended: `julia --project=. train_chinese.jl`
# - When used as a package: `using TrainChinese; TrainChinese.main()`

using TOML

function _is_broken_pipe(err)::Bool
    if !(err isa Base.IOError)
        return false
    end
    if isdefined(Base, :UV_EPIPE)
        try
            return err.code == Base.UV_EPIPE
        catch
            # fall through
        end
    end
    return occursin("broken pipe", lowercase(sprint(showerror, err)))
end

function _print_help()
    println("TrainChinese — terminal Chinese vocabulary trainer")
    println("")
    println("Usage:")
    println("  trainchinese                                        # start interactive training (default)")
    println("  trainchinese --stats                                # print current pool statistics and exit")
    println("  trainchinese --plot-history                         # plot per-task history (colors = tasks) and exit")
    println("  trainchinese --plot-history --no-show               # generate plot without opening a window")
    println("  trainchinese --plot-history --save-plot FILE.png    # save plot to a file and exit")
    println("  trainchinese --plot-word-history                    # plot per-word learning history and exit")
    println("  trainchinese --install-plotting                     # install optional plotting dependency (PyPlot) into cli/")
    println("  trainchinese --save FILE                            # use a custom save JSON (default: ChineseSave.json)")
    println("  trainchinese --vocab FILE                           # use a custom vocabulary TXT (default: ChineseVocabulary.txt)")
    println("  trainchinese --stats-out FILE                       # use a custom stats export TXT (default: ChineseStats.txt)")
    println("  trainchinese --version                              # print version and exit")
    println("  trainchinese --help                                 # show this help and exit")
    println("")
    println("Alternative (without wrapper):")
    println("  julia --project=. train_chinese.jl [ARGS...]")
    println("")
    println("Notes:")
    println("  - Plotting uses PyPlot; it may require a working matplotlib installation.")
    println("  - The wrapper uses a dedicated environment in cli/ for plotting dependencies.")
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

function _parse_value(arg::String)
    if startswith(arg, "--") && occursin('=', arg)
        k, v = split(arg, '='; limit=2)
        return (k, v)
    end
    return nothing
end

function _parse_cli_args(args::Vector{String})
    flags = Set{String}()
    opts = Dict{String, String}()
    unknown = String[]

    i = 1
    while i <= length(args)
        a = args[i]

        kv = _parse_value(a)
        if kv !== nothing
            k, v = kv
            if k in ("--save", "--vocab", "--stats-out", "--save-plot")
                opts[k] = v
            else
                push!(unknown, a)
            end
            i += 1
            continue
        end

        if a in ("--help", "-h", "--version", "-V", "--stats", "--plot-history", "--plot-word-history", "--install-plotting", "--no-show")
            push!(flags, a)
            i += 1
        elseif a in ("--save", "--vocab", "--stats-out", "--save-plot")
            if i == length(args)
                println("Missing value for ", a)
                println("")
                _print_help()
                exit(2)
            end
            opts[a] = args[i + 1]
            i += 2
        else
            push!(unknown, a)
            i += 1
        end
    end

    return flags, opts, unknown
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

    try
        flags, opts, unknown = _parse_cli_args(ARGS)
        save_path = get(opts, "--save", "ChineseSave.json")
        vocab_path = get(opts, "--vocab", "ChineseVocabulary.txt")
        stats_path = get(opts, "--stats-out", "ChineseStats.txt")

        if !isempty(unknown) && !(("--help" in flags) || ("-h" in flags))
            println("Unknown arguments: ", join(unknown, " "))
            println("")
            _print_help()
            exit(2)
        end

        if ("--help" in flags) || ("-h" in flags)
            _print_help()
            exit(0)
        elseif ("--version" in flags) || ("-V" in flags)
            _print_version(@__DIR__)
            exit(0)
        elseif "--install-plotting" in flags
            import Pkg
            Pkg.activate(joinpath(@__DIR__, "cli"))
            Pkg.instantiate()
            println("Installed plotting dependencies into the CLI environment.")
            println("Re-run with: trainchinese --plot-history")
            exit(0)
        elseif "--stats" in flags
            pool = _load_pool(save_path, vocab_path)
            TrainChinese.display_statistics(pool)
            exit(0)
        elseif "--plot-history" in flags
            pool = _load_pool(save_path, vocab_path)
            show_plot = !("--no-show" in flags)
            save_plot = get(opts, "--save-plot", nothing)

            # TrainChinese plotting is implemented as a Julia extension that activates
            # when PyPlot is present *and loaded* in the active environment.
            try
                @eval import PyPlot
            catch
                println("Plotting requires PyPlot.")
                println("Run: trainchinese --install-plotting")
                exit(2)
            end
            TrainChinese.plot_task_review_history(pool; show_plot=show_plot, save_path=save_plot)
            exit(0)
        elseif "--plot-word-history" in flags
            pool = _load_pool(save_path, vocab_path)
            show_plot = !("--no-show" in flags)
            save_plot = get(opts, "--save-plot", nothing)

            try
                @eval import PyPlot
            catch
                println("Plotting requires PyPlot.")
                println("Run: trainchinese --install-plotting")
                exit(2)
            end
            TrainChinese.plot_word_learning_history(pool; show_plot=show_plot, save_path=save_plot)
            exit(0)
        else
            TrainChinese.main(; save_path=save_path, vocab_path=vocab_path, stats_path=stats_path)
        end
    catch err
        # If stdout is piped to a consumer that closes early (e.g. `--help | head`),
        # printing can raise EPIPE. Treat it as a clean exit.
        if _is_broken_pipe(err)
            exit(0)
        end
        rethrow()
    end
end
