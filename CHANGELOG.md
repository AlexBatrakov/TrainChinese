# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [0.1.0] - 2026-01-31

### Added

- Terminal-based Chinese vocabulary trainer with spaced repetition.
- Directed tasks per word: Hanzi, Pinyin (tone numbers), Translation.
- Persistent progress (`ChineseSave.json`) and stats export (`ChineseStats.txt`).
- Optional plotting via `PyPlot` using a Julia extension, kept out of the core dependency set.
- Dedicated `cli/` environment + wrapper scripts for a smoother CLI install.
- CLI plotting flags: `--plot-history`, `--plot-word-history`, `--no-show`, `--save-plot`.
- Screenshots in the README.
- Contributing guide and GitHub issue/PR templates.
