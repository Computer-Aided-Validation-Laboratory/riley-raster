This directory contains 100-run performance reference summaries.

These files are not used by the perf test scripts as live gold baselines.
They are committed as a machine-specific reference so other developers can
compare their locally generated perf gold against an existing dataset.

Reference machine:
- AMD Ryzen 7 8845HS (Zen4) Laptop CPU

Contents:
- `perf_*_1thread/`
- `perf_*_4thread/`

Each subdirectory contains summary artifacts copied from a 100-run perf gold
generation:
- `bench_stats_median.csv`
- `bench_stats_mad.csv`
- `bench_stats_min.csv`
- `bench_stats_max.csv`
- `bench_stats_cov.csv`
- `metadata.json`
- `config.txt`
- `command.txt`
- `stdout.txt`
- `stderr.txt`

To run perf tests on a different machine, generate local perf gold with the
perf scripts and use that as the active baseline. Treat the data in this
directory as a rough external reference only.
