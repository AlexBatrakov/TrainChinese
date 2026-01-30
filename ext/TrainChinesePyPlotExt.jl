module TrainChinesePyPlotExt

using Dates
using TrainChinese
import PyPlot

function plot_word_review_history(pool::TrainChinese.WordPool; show_plot::Bool=true, save_path::Union{Nothing, String}=nothing)
    task_specs = [
        ("Hanzi → Pinyin",       (TrainChinese.Hanzi, TrainChinese.Pinyin)),
        ("Hanzi → Translation",  (TrainChinese.Hanzi, TrainChinese.Translation)),
        ("Pinyin → Hanzi",       (TrainChinese.Pinyin, TrainChinese.Hanzi)),
        ("Pinyin → Translation", (TrainChinese.Pinyin, TrainChinese.Translation)),
        ("Translation → Hanzi",  (TrainChinese.Translation, TrainChinese.Hanzi)),
        ("Translation → Pinyin", (TrainChinese.Translation, TrainChinese.Pinyin))
    ]

    colors = ["red", "blue", "green", "orange", "purple", "cyan"]

    Base.invokelatest(getfield(PyPlot, :figure); figsize=(10, 6))

    for (task_index, (task_label, task_type)) in enumerate(task_specs)
        color = colors[task_index]

        for word in values(pool.known_words)
            history = word.stats[task_type].review_history
            isempty(history) && continue

            t0 = history[1].date_reviewed
            times_all = [(h.date_reviewed - t0) / Minute(1) for h in history]
            levels_all = [h.level_new for h in history]
            keep = findall(t -> t > 0, times_all)
            isempty(keep) && continue

            Base.invokelatest(getfield(PyPlot, :plot),
                times_all[keep], levels_all[keep] .+ 0.15 * task_index, ".";
                color=color, label="_nolegend_")
        end
    end

    # Ensure the legend always contains a clean color → task mapping.
    # We add one "proxy" point per task (at NaN) so it doesn't affect axis limits.
    for (task_index, (task_label, _)) in enumerate(task_specs)
        color = colors[task_index]
        Base.invokelatest(getfield(PyPlot, :plot), [NaN], [NaN], "."; color=color, label=task_label)
    end

    Base.invokelatest(getfield(PyPlot, :xlabel), "Minutes since first review (per word/task; log scale)")
    Base.invokelatest(getfield(PyPlot, :ylabel), "Word level")
    Base.invokelatest(getfield(PyPlot, :title), "Review history by task (color = task)")
    Base.invokelatest(getfield(PyPlot, :grid), true)
    Base.invokelatest(getfield(PyPlot, :tight_layout))
    Base.invokelatest(getfield(PyPlot, :xscale), "log")
    Base.invokelatest(getfield(PyPlot, :legend); loc="upper left", title="Task (color)")

    if save_path !== nothing
        Base.invokelatest(getfield(PyPlot, :savefig), save_path; bbox_inches="tight")
    end

    if show_plot
        Base.invokelatest(getfield(PyPlot, :show))
    end

    return nothing
end

function plot_review_history(words::Vector{TrainChinese.Word}; max_words::Int=40, annotate::Bool=true, show_plot::Bool=true, save_path::Union{Nothing, String}=nothing)
    Base.invokelatest(getfield(PyPlot, :figure); figsize=(10, 6))
    Base.invokelatest(getfield(PyPlot, :title), "Word learning history")
    Base.invokelatest(getfield(PyPlot, :xlabel), "Minutes since first review (per word; log scale)")
    Base.invokelatest(getfield(PyPlot, :ylabel), "Average level (mean across tasks)")

    offset_step = 0.10
    offset_index = 0

    for word in Iterators.take(words, max_words)
        events = Vector{Tuple{DateTime, Tuple{TrainChinese.AttributeType, TrainChinese.AttributeType}, Int}}()
        for (task_type, stats) in word.stats
            for h in stats.review_history
                push!(events, (h.date_reviewed, task_type, h.level_new))
            end
        end

        isempty(events) && continue
        sort!(events, by = e -> e[1])

        t0 = events[1][1]
        task_levels = Dict(task => 0 for task in keys(word.stats))
        times = Float64[]
        global_levels = Float64[]
        for (dt, task_type, level_new) in events
            task_levels[task_type] = level_new
            push!(times, (dt - t0) / Minute(1))
            push!(global_levels, sum(values(task_levels)) / length(task_levels))
        end

        keep = findall(t -> t > 0, times)
        isempty(keep) && continue
        Base.invokelatest(getfield(PyPlot, :plot), times[keep], global_levels[keep]; linewidth=2)

        if annotate
            y_offset = offset_step * ((offset_index % 2 == 0) ? 1 : -1)
            Base.invokelatest(getfield(PyPlot, :annotate),
                word.hanzi,
                (times[keep[end]], global_levels[keep[end]] + y_offset);
                fontsize=12, fontname="Arial Unicode MS", ha="left")
            offset_index += 1
        end
    end

    Base.invokelatest(getfield(PyPlot, :xscale), "log")
    Base.invokelatest(getfield(PyPlot, :grid), true)
    Base.invokelatest(getfield(PyPlot, :tight_layout))

    if save_path !== nothing
        Base.invokelatest(getfield(PyPlot, :savefig), save_path)
    end

    if show_plot
        Base.invokelatest(getfield(PyPlot, :show))
    end

    return nothing
end

function plot_review_history(pool::TrainChinese.WordPool; max_words::Int=40, annotate::Bool=true, show_plot::Bool=true, save_path::Union{Nothing, String}=nothing)
    words = collect(values(pool.known_words))
    return plot_review_history(words; max_words=max_words, annotate=annotate, show_plot=show_plot, save_path=save_path)
end

end
