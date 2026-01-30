# TrainChinese

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

## Requirements

- Julia (recent 1.x).

Julia packages used by the script:

- `JSON`
- `StatsBase`
- `PyPlot`

(`Dates`, `Statistics`, `Random`, `Printf` are part of the standard library.)

If you don’t have the packages installed yet, start Julia and run:

```julia
import Pkg
Pkg.add(["JSON", "StatsBase", "PyPlot"])
```

## Quick start

From the repository folder:

```bash
julia train_chinese.jl
```

The trainer will:

1. Load progress from `ChineseSave.json`.
2. Load vocabulary from `ChineseVocabulary.txt` and merge new entries into the pool.
3. Start an interactive training session and periodically write updated progress/stats.

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
- Turn the script into a Julia package with a small CLI entry point.
- Add automated tests for file parsing and scheduling math.

## License

No explicit license yet.

If you want this to be easy to reuse (and look “normal” to employers), consider adding an OSI-approved license file.