# Contributing

Thanks for considering contributing!

## Quick dev setup

```bash
julia --project=. -e 'import Pkg; Pkg.instantiate()'
```

Run tests:

```bash
julia --project=. -e 'import Pkg; Pkg.test()'
```

## Optional plotting (local)

Plotting uses `PyPlot` behind a Julia extension and is intentionally **not** a hard dependency of the package.

Use the wrapper + CLI environment:

```bash
./bin/trainchinese --install-plotting
./bin/trainchinese --plot-history
```

## Style

- Prefer small, focused PRs.
- Keep public APIs backward-compatible when reasonable.
- Update README/help text when changing CLI behavior.
