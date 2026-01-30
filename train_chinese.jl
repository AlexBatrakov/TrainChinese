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
    println("  julia --project=. train_chinese.jl                         # start interactive training (default)")
    println("  julia --project=. train_chinese.jl --stats                 # print current pool statistics and exit")
    println("  julia --project=. train_chinese.jl --plot-history          # plot learning history and exit")
    println("  julia --project=. train_chinese.jl --save FILE             # use a custom save JSON (default: ChineseSave.json)")
    println("  julia --project=. train_chinese.jl --vocab FILE            # use a custom vocabulary TXT (default: ChineseVocabulary.txt)")
    println("  julia --project=. train_chinese.jl --stats-out FILE        # use a custom stats export TXT (default: ChineseStats.txt)")
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
            if k in ("--save", "--vocab", "--stats-out")
                opts[k] = v
            else
                push!(unknown, a)
            end
            i += 1
            continue
        end

        if a in ("--help", "-h", "--version", "-V", "--stats", "--plot-history")
            push!(flags, a)
            i += 1
        elseif a in ("--save", "--vocab", "--stats-out")
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

        if ("--help" in flags) || ("-h" in flags)
            _print_help()
            exit(0)
        elseif ("--version" in flags) || ("-V" in flags)
            _print_version(@__DIR__)
            exit(0)
        elseif "--stats" in flags
            pool = _load_pool(save_path, vocab_path)
            TrainChinese.display_statistics(pool)
            exit(0)
        elseif "--plot-history" in flags
            pool = _load_pool(save_path, vocab_path)
            TrainChinese.plot_review_history(pool)
            exit(0)
        elseif !isempty(unknown)
            println("Unknown arguments: ", join(unknown, " "))
            println("")
            _print_help()
            exit(2)
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
