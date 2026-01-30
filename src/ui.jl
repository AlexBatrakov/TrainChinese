"""Wrap `text` with ANSI escape codes for terminal coloring."""
function colored_text(text::String, color::Symbol)
    colors = Dict(
        :red => "\x1b[31m",
        :green => "\x1b[32m",
        :yellow => "\x1b[33m",
        :blue => "\x1b[34m",
        :reset => "\x1b[0m"
    )
    return "$(colors[color])$text$(colors[:reset])"
end
