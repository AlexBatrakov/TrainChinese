# TrainChinese

[![CI](https://github.com/AlexBatrakov/TrainChinese/actions/workflows/ci.yml/badge.svg)](https://github.com/AlexBatrakov/TrainChinese/actions/workflows/ci.yml)

Terminal-based Chinese vocabulary trainer written in Julia.

The app focuses on active recall across three attributes of a word:
**Hanzi**, **Pinyin** (with tone numbers), and **English translation**. It schedules reviews using a simple spaced-repetition model and saves your progress to JSON.

## Features

- Interactive CLI training sessions.
- Multiple directed tasks per word (e.g. `Hanzi -> Pinyin`, `Translation -> Hanzi`, etc.).
- Spaced repetition based on time since last review and current level.
- Persistent progress (`ChineseSave.json`) and a human-readable stats export (`ChineseStats.txt`).
- macOS helpers:
	- Text-to-speech via `say`.
	- Keyboard layout toggle via `osascript` (useful for Hanzi input).

## Screenshots

Interactive training in the terminal:

![CLI screenshot](assets/cli.png)

Per-task review history (colors = tasks):

![Per-task history plot](assets/plot-history.png)

Per-word learning history:

![Per-word history plot](assets/plot-word-history.png)

## Algorithm overview (spaced repetition)

This trainer models forgetting as an exponential decay process and uses it to:

1. Decide which words are due for review.
2. Update the learning level after each attempt.
3. Keep **separate progress** for different skills (so you don’t end up “knowing how to write it” but forgetting how it sounds).

### Priority (when a word is due)

For each task, the script derives a **priority** from time since last review and the current level:

```
priority = (minutes_since_last_review) / 2^level
```

Intuition:

- Right after a review, `minutes_since_last_review` is small → low priority.
- Higher `level` means a longer effective half-life (`2^level`) → the same time gap becomes less urgent.

The session selects words whose **global** priority is high enough (plus level-0 words) and trains them in small random batches.

### Memory strength (probability-like “how likely I remember it”)

Priority is converted into **memory strength** (0..1) using an exponential decay:

```
memory_strength = 2^(-C * priority)
```

So the longer you wait (higher priority), the lower the memory strength becomes.

### Probabilistic level updates (multi-level jumps)

Instead of `level += 1` / `level -= 1`, the update is **probabilistic** and can jump multiple levels.

- If you answered correctly, the chance to increase the level is higher when `memory_strength` was low.
  - Meaning: if you hadn’t seen the item for a long time but still recalled it, that’s strong evidence of learning.
- If you answered incorrectly, the chance to decrease the level is higher when `memory_strength` was high.
  - Meaning: if you reviewed recently (model says you should remember) but failed, that’s a bad signal.

The script applies the update as a chain of Bernoulli trials, so in rare cases the level can go up/down by more than one.

### Separate levels per skill (directed tasks)

Each word tracks statistics for *directed* tasks between the three attributes:

- Hanzi, Pinyin (tone numbers), Translation

This produces tasks like:

- `Hanzi -> Pinyin`, `Hanzi -> Translation`
- `Pinyin -> Hanzi`, `Pinyin -> Translation`
- `Translation -> Hanzi`, `Translation -> Pinyin`

The **global level** of a word is derived from these task levels (the weakest task dominates), which prevents “lopsided learning”.

### Training modes (what you actually practice)

For a chosen word, the trainer selects the *weakest starting attribute* and then runs a short sequence:

- Start from Hanzi: warm-up Hanzi input → train `Hanzi -> Pinyin` and `Hanzi -> Translation`
- Start from Pinyin (sound): warm-up with TTS → train `Pinyin -> Hanzi` and `Pinyin -> Translation`
- Start from Translation: show translation/context → train `Translation -> Hanzi` and `Translation -> Pinyin`

### Translation task via keywords (not exact wording)

Translation recall is implemented as: type keywords → get a shortlist → choose the intended option.

Input format:

```
translation_kw1+translation_kw2;context_kw1+context_kw2
```

This allows you to remember the *idea* (key words) instead of reproducing the exact dictionary wording.

## Requirements

- Julia (recent 1.x).

The main dependencies are declared in `Project.toml` (e.g. `JSON`, `StatsBase`).
Optional plotting is implemented via an extension and requires `PyPlot`.

To install the base dependencies for this repo:

```bash
julia --project=. -e 'import Pkg; Pkg.instantiate()'
```

## Quick start

From the repository folder:

```bash
./bin/trainchinese
```

Alternative (without the wrapper):

```bash
julia --project=. train_chinese.jl
```

## Plotting (optional)

Plotting uses `PyPlot` and is intentionally installed into the separate `cli/` environment.

Recommended:

```bash
./bin/trainchinese --install-plotting
./bin/trainchinese --plot-history
```

Manual (equivalent):

```bash
julia --project=cli -e 'import Pkg; Pkg.instantiate()'
```

## Installed CLI (optional)

If you want to run the trainer as a command (e.g. `trainchinese --help`), this repo includes a small wrapper script:

- macOS/Linux: `bin/trainchinese`
- Windows (PowerShell): `bin/trainchinese.ps1`

On macOS/Linux, make it executable and add it to your `PATH` (via symlink):

```bash
chmod +x bin/trainchinese
mkdir -p ~/.local/bin
ln -sf "$(pwd)/bin/trainchinese" ~/.local/bin/trainchinese
```

Then you can run:

```bash
trainchinese --help
trainchinese --stats
```

### CLI options

```bash
trainchinese --help
```

Common flags:

- `--stats` — print current pool statistics and exit
- `--plot-history` — plot per-task history (colors = tasks) and exit (requires `PyPlot`)
- `--plot-history --no-show` — generate the plot without opening a GUI window
- `--plot-history --save-plot FILE.png` — save the plot to a file and exit
- `--plot-word-history` — plot per-word learning history and exit (requires `PyPlot`)
- `--install-plotting` — install plotting deps into the `cli/` environment
- `--save FILE` — override save JSON (default: `ChineseSave.json`)
- `--vocab FILE` — override vocabulary TXT (default: `ChineseVocabulary.txt`)
- `--stats-out FILE` — override stats export TXT (default: `ChineseStats.txt`)

If you run without the wrapper, you may need to instantiate dependencies first:

```bash
julia --project=. -e 'import Pkg; Pkg.instantiate()'
```

The wrapper (`bin/trainchinese`) instantiates the `cli/` environment automatically on first run.

The trainer will:

1. Load progress from `ChineseSave.json`.
2. Load vocabulary from `ChineseVocabulary.txt` and merge new entries into the pool.
3. Start an interactive training session and periodically write updated progress/stats.

## Using it as a Julia project/package

This repo contains a `Project.toml` and a small module wrapper in `src/TrainChinese.jl`, so you can also use it from the Julia REPL:

```julia
import Pkg
Pkg.activate(".")
Pkg.instantiate()

using TrainChinese
TrainChinese.main()
```

## Data files

### `ChineseVocabulary.txt`

This is the source vocabulary list. Each non-empty, non-comment line uses a `|`-separated format:

```
id | hanzi | pinyin | translation | optional context
```

Notes:

- `id` should be unique and stable (examples in the repo: `hsk1.4`, `duo.12`).
- Pinyin may contain tone marks in the file; the script converts them to tone numbers.
- `context` is optional and helps disambiguate similar translations.

### `ChineseSave.json`

Saved progress (levels, last review timestamps, per-task history). This repo may contain a longer file as an example/test dataset.

### `ChineseStats.txt`

A quick tabular export for human inspection (per-task levels + mean/min per word).

### `cedict_1_0_ts_utf-8_mdbg.txt`

CC-CEDICT-based dictionary file used by the trainer for additional lookups.

## Platform notes

- macOS: the script uses `say` and `osascript` in the interactive flow.
- Linux/Windows: you can still run the trainer, but you may want to disable or replace the macOS-specific helpers if they don’t exist on your system.

## Roadmap ideas (optional)

- Make TTS/layout helpers cross-platform (feature flags or OS detection).
- Add a small installed CLI wrapper (so you can run it without typing `julia --project=...`).
- Expand automated tests for parsing, scheduling, and persistence.

## License

MIT License. See `LICENSE`.