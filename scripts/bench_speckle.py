#!/usr/bin/env python3
"""One complete, frozen, fresh-process A/B speckle comparison; stdlib only."""
import argparse
from bisect import bisect_left, bisect_right
from collections import defaultdict
import hashlib
from itertools import combinations, product
import json
import math
import os
from pathlib import Path
import random
import shutil
import statistics
import subprocess

ROOT = Path(__file__).resolve().parent.parent
METRICS = ('resource_ns', 'render_ns', 'combined_ns')
FACTORS = ('threads', 'scene', 'pattern', 'jitter', 'occupancy', 'neighbors', 'softness')


def require(ok, message):
    if not ok:
        raise ValueError(message)


def available_cpus():
    return len(os.sched_getaffinity(0)) if hasattr(os, 'sched_getaffinity') else os.cpu_count() or 1


def schedules(repeats):
    require(repeats >= 2 and repeats % 2 == 0, 'repeats must be an even total per variant >= 2')
    first = ('ABBA' * ((repeats + 3) // 4))[:repeats]
    return [first, first.translate(str.maketrans('AB', 'BA'))]


def design(args):
    tuning = args.profile == 'tuning'
    repeats = args.repeats if args.repeats is not None else (12 if tuning else 16)
    alpha = args.alpha if args.alpha is not None else (.05 if tuning else .10)
    require(math.isfinite(alpha) and 0 < alpha < 1, 'alpha must be between 0 and 1')
    require(args.permutations > 0, 'permutations must be positive')
    require(math.isfinite(args.timeout_seconds) and args.timeout_seconds > 0, 'timeout must be positive and finite')
    require(all(x > 0 for x in (args.width, args.height, args.frames, *args.cells_plate, *args.cells_sphere)),
            'dimensions, frames and cells must be positive')
    require(math.isfinite(args.radius) and args.radius > 0, 'radius must be positive and finite')
    require(math.isfinite(args.softness) and args.softness > 0, 'soft-case softness must be positive and finite')
    require(0 <= args.seed < 2**32, 'seed must be uint32')
    require(args.perlin_threshold is None or math.isfinite(args.perlin_threshold), 'Perlin threshold must be finite')
    require(args.perlin_transition is None or (math.isfinite(args.perlin_transition) and args.perlin_transition >= 0),
            'Perlin transition must be finite and nonnegative')
    workers = sorted(set(available_cpus() if x == 'available-cpus' else int(x)
                         for x in (args.workers or ['1', 'available-cpus'])))
    require(all(x > 0 for x in workers), 'workers must be positive')
    for values in (args.jitter, args.occupancy):
        require(all(math.isfinite(x) and 0 <= x <= 1 for x in (values or [])), 'jitter/occupancy must be in [0,1]')
    components = [(['plate', 'sphere'], ['hard', 'gaussian'], [0, .08], [.7, 1], [1, 4, 9])]
    if tuning:
        components = [(['plate'], ['hard'], [0, .08], [.7, 1], [9]),
                      (['sphere'], ['hard'], [.08], [.7], [9]),
                      (['plate'], ['hard'], [.08], [.7], [4]),
                      (['plate'], ['gaussian'], [.08], [.7], [9])]
    overrides = (args.scenes, args.patterns, args.jitter, args.occupancy, args.neighbors)
    cases = []
    for component in components:
        factors = [workers, *(override if override is not None else default
                              for override, default in zip(overrides, component))]
        for values in product(*factors):
            case = dict(zip(FACTORS[:-1], values))
            if (not tuning and args.occupancy is None and not args.include_full_occupancy_single_neighbor
                    and case['neighbors'] == 1 and case['occupancy'] == 1):
                continue
            if case['pattern'] == 'perlin':
                case['neighbors'] = None
            case['softness'] = args.softness if case['pattern'] == 'soft' else 0.
            if case not in cases:
                cases.append(case)
    require('texture' not in (args.a, args.b) or args.texture, 'texture mapping requires --texture')
    return dict(profile=args.profile, mode='full-render' if args.profile == 'full-render' else 'evaluation',
                configurations=cases, repeats=repeats, schedules=schedules(repeats), alpha=alpha,
                metrics=[{'setup': 'resource_ns', 'render': 'render_ns', 'combined': 'combined_ns'}[x]
                         for x in dict.fromkeys(args.metrics or (['combined'] if tuning else ['setup', 'render']))],
                permutations=args.permutations, permutation_seed=20261005,
                inference='two-sided blocked sum contrast; exact <=200000 subsets/block, otherwise Monte Carlo plus-one; joint Holm',
                require_equal_output=args.require_equal_output, skip_output_checks=args.skip_output_checks,
                config=dict(width=args.width, height=args.height, frames=args.frames, radius=args.radius,
                            seed=args.seed, texture=None, texture_filter=args.texture_filter,
                            perlin_threshold=args.perlin_threshold, perlin_transition=args.perlin_transition),
                cells=dict(plate=args.cells_plate, sphere=args.cells_sphere), variants={})


def freeze(original, destination):
    shutil.copy2(original, destination)
    with destination.open('rb') as stream:
        sha = hashlib.file_digest(stream, 'sha256').hexdigest()
    return dict(original_path=str(original.resolve()), file=str(destination), sha256=sha)


def validate_native(native, config):

    for key, value in config.items():
        if value is not None:
            actual = native.get(key)
            numeric = type(value) in (int, float) and type(actual) in (int, float)
            require(actual == value and (numeric or type(actual) is type(value)), f'native config echo mismatch: {key}')
    for metric in METRICS:
        require(type(native.get(metric)) is int and native[metric] >= 0, f'invalid {metric}: integer ns required')
    require(native['combined_ns'] == native['resource_ns'] + native['render_ns'], 'invalid combined timing')
    require(type(native.get('checksum')) is int and 0 <= native['checksum'] < 2**64, 'invalid checksum')
    evaluation = config['mode'] == 'evaluation'
    require(native.get('evaluation_counters_available') is evaluation, 'invalid counter availability')
    require(type(native.get('shaded_samples')) is int
            and (native['shaded_samples'] > 0 if evaluation else native['shaded_samples'] == 0), 'invalid shaded sample count')
    images = 0 if evaluation else config['width'] * config['height'] * config['frames']
    require(type(native.get('image_samples')) is int and native['image_samples'] == images, 'invalid mono image sample count')
    if 'backface_rejections' in native:
        require(type(native['backface_rejections']) is int and native['backface_rejections'] >= 0, 'invalid rejection count')


def fingerprint(native):
    return tuple(native.get(k) for k in ('checksum', 'shaded_samples', 'backface_rejections', 'image_samples'))


def permutation(blocks, count=100000, seed=20261005):
    """Two-sided blocked sum contrast, ties included; exact up to 200k subsets/block."""
    require(len(blocks) == 2 and all(len(a) == len(b) and a for a, b in blocks), 'invalid blocks')
    observed = abs(sum(sum(a) - sum(b) for a, b in blocks))
    pools = [(*a, *b) for a, b in blocks]
    sizes = [len(a) for a, b in blocks]
    totals = list(map(sum, pools))
    if max(math.comb(len(p), n) for p, n in zip(pools, sizes)) <= 200000:
        distributions = [[2 * sum(c) - total for c in combinations(pool, n)]
                         for pool, n, total in zip(pools, sizes, totals)]
        first, second = distributions
        second.sort()
        total = len(first) * len(second)
        tail = total if observed == 0 else sum(bisect_right(second, -observed - x)
                    + len(second) - bisect_left(second, observed - x) for x in first)
        return dict(p=tail / total, method='exact', tail=tail, assignments=total)
    rng = random.Random(seed)
    tail = sum(abs(sum(2 * sum(rng.sample(pool, n)) - total
                      for pool, n, total in zip(pools, sizes, totals))) >= observed for _ in range(count))
    return dict(p=(tail + 1) / (count + 1), method='monte-carlo-plus-one', tail=tail, assignments=count)


def holm(values):
    result = [0] * len(values)
    previous = 0
    for rank, i in enumerate(sorted(range(len(values)), key=values.__getitem__)):
        previous = max(previous, min(1, values[i] * (len(values) - rank)))
        result[i] = previous
    return result


def report(out, metadata, groups, outputs):
    records = []
    for i, case in enumerate(metadata['configurations']):
        for metric in METRICS:
            blocks = [tuple([r[metric] for r in groups[i, s, v]] for v in 'AB') for s in (0, 1)]
            a, b = ([x for block in blocks for x in block[k]] for k in (0, 1))
            am, bm = statistics.median(a), statistics.median(b)
            record = dict(case_id=i, case=case, metric=metric, a_median_ns=am, b_median_ns=bm,
                          ratio=bm / am if am else None, mean_delta_ns=(sum(b) - sum(a)) / len(a),
                          output_equal=outputs[i, 'A'] == outputs[i, 'B'])
            if metric in metadata['metrics']:
                record.update(permutation(blocks, metadata['permutations'], metadata['permutation_seed'] + i * 3 + METRICS.index(metric)))
            records.append(record)
    primary = [r for r in records if 'p' in r]
    for record, p in zip(primary, holm([r['p'] for r in primary])):
        record.update(holm_p=p, detected=p <= metadata['alpha'])
    (out / 'comparison.json').write_text(json.dumps(records, indent=2) + '\n')
    n = len(metadata['configurations'])
    lines = ['# Speckle A/B comparison', '',
             f"{metadata['profile']} / {metadata['mode']}: {n} configurations, {2*n} variant groups, "
             f"{metadata['repeats']} runs/variant/case; schedules {' / '.join(metadata['schedules'])}.",
             f"Holm alpha={metadata['alpha']}, {len(primary)} tests. B/A <1 favors B; tests use mean contrasts, tables use medians.",
             'Setup: procedural generation or texture UV/resource preparation. Decode, fixture loading and checksum reduction excluded. '
             'Render: static evaluation loop, or real full-render pipeline minus resource time. Combined = setup + render, not wall time; untested metrics descriptive.',
             f"Exact blocked permutations (ties included) up to 200000 subsets/block; otherwise {metadata['permutations']} seeded draws, (tail+1)/(draws+1). "
             'Deterministic schedules assume within-block exchangeability; drift/serial dependence may invalidate inference. Tuning exploratory; non-significance is not equivalence.',
             f"Texture filter: {metadata['config']['texture_filter']} (Catmull–Rom uses lut_lerp; nearest/linear use direct). "
             'Interpolation LUTs are compile-time constants. Texture uses one frozen asset: procedural factors are requested control labels, not texture synthesis or matching imagery. '
             f"Output mismatch cases: {sum(outputs[i, 'A'] != outputs[i, 'B'] for i in range(n))}.", '',
             '| Case | Factors (workers, scene, pattern, jitter, occupancy, neighbors, softness) | Metric | A ns | B ns | B/A | p | Holm p | Detected |',
             '|---|---|---|---:|---:|---:|---:|---:|---|']
    if metadata.get('skip_output_checks', False):
        lines.insert(2, 'Within-repeat and cross-variant output consistency checks disabled; no image consistency guarantee.')
    for r in records:
        ratio = f"{r['ratio']:.6g}" if r['ratio'] is not None else 'n/a'
        lines.append(f"| {r['case_id']} | {tuple(r['case'][k] for k in FACTORS)} | {r['metric']} | "
                     f"{r['a_median_ns']:g} | {r['b_median_ns']:g} | {ratio} | {r.get('p', 'descriptive')} | "
                     f"{r.get('holm_p', '—')} | {r.get('detected', '—')} |")
    (out / 'comparison.md').write_text('\n'.join(lines) + '\n')
    print(f"Report: {out / 'comparison.md'}")


def parser():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.ArgumentDefaultsHelpFormatter,
        epilog='Tuning: 14 cases, 12 runs/variant, combined Holm .05. Full/full-render: 80 cases, '
        '16 runs/variant, setup+render Holm .10 (counts assume two distinct worker budgets). '
        'Overrides replace factors in each tuning component; deduplicate their union. Full excludes '
        'occupancy=1/neighbors=1 unless occupancy is explicit or inclusion flag is set. '
        'Two sweeps use balanced ABBA prefixes and inverses; no warmups. Native validates catalog compatibility '
        '(--list-evaluators); each process must emit one BENCH JSON record. Fresh output only; no resume. '
        'Artifacts: metadata.json, samples.jsonl, comparison.json/.md and frozen assets.')
    p.add_argument('--out', type=Path, required=True, help='fresh comparison directory')
    p.add_argument('--profile', choices=('tuning', 'full', 'full-render'), default='tuning', help='full is evaluation-only')
    p.add_argument('--a', default='cell-hash', help='catalog evaluator or texture')
    p.add_argument('--b', default='list-indexed', help='catalog evaluator or texture')
    p.add_argument('--binary', type=Path, default=ROOT / 'zig-out/bin/bench_speckle_evaluators_f64_simd', help='common native binary')
    for v in 'ab':
        p.add_argument('--binary-' + v, type=Path, help='override common binary for ' + v.upper())
    p.add_argument('--workers', nargs='+', help='integers or available-cpus; default 1 and affinity CPU count, deduplicated')
    for name, choices in (('scenes', ('plate', 'sphere')), ('patterns', ('hard', 'soft', 'gaussian', 'perlin'))):
        p.add_argument('--' + name, nargs='+', choices=choices, help='replace profile factor')
    p.add_argument('--neighbors', nargs='+', type=int, choices=(1, 4, 9), help='replace profile factor')
    for name in ('jitter', 'occupancy'):
        p.add_argument('--' + name, nargs='+', type=float, help='replace profile factor')
    p.add_argument('--include-full-occupancy-single-neighbor', action='store_true', help='include the normally excluded pair')
    for name, default in (('frames', 16), ('width', 3840), ('height', 2160)):
        p.add_argument('--' + name, type=int, default=default, help='native workload ' + name)
    p.add_argument('--cells-plate', nargs=2, type=int, default=[320, 192], help='plate UV cell counts')
    p.add_argument('--cells-sphere', nargs=2, type=int, default=[256, 160], help='sphere UV cell counts')
    p.add_argument('--seed', type=lambda x: int(x, 0), default=0xa511e9b3, help='native uint32 seed (decimal or hex)')
    p.add_argument('--perlin-threshold', type=float, help='override Perlin coverage threshold')
    p.add_argument('--perlin-transition', type=float, help='override Perlin transition width; 0 selects hard threshold')
    p.add_argument('--radius', type=float, default=.35, help='procedural radius')
    p.add_argument('--softness', type=float, default=.04, help='soft cases only; hard/Gaussian always use 0')
    p.add_argument('--texture', type=Path, help='BMP asset required for texture mapping; copied before execution')
    p.add_argument('--texture-filter', choices=('nearest', 'linear', 'cubic_catmull_rom'), default='cubic_catmull_rom',
                   help='texture sampling: Catmull–Rom uses lut_lerp; nearest/linear use direct')
    p.add_argument('--alpha', type=float, help='override profile family-wise alpha')
    p.add_argument('--repeats', type=int, help='override even TOTAL runs per variant >=2; never capped')
    p.add_argument('--metrics', nargs='+', choices=('setup', 'render', 'combined'), help='override jointly tested metrics')
    p.add_argument('--permutations', type=int, default=100000, help='Monte Carlo draws for large repeat counts')
    output_checks = p.add_mutually_exclusive_group()
    output_checks.add_argument('--require-equal-output', action='store_true', help='also require exact cross-variant fingerprints')
    output_checks.add_argument('--skip-output-checks', action='store_true', help='disable within-repeat and cross-variant fingerprint checks; retain native validation')
    p.add_argument('--timeout-seconds', type=float, default=900, help='per-process timeout')
    return p


def main(argv=None):
    p = parser()
    args = p.parse_args(argv)
    try:
        out = args.out.resolve()
        require(not out.exists() or not any(out.iterdir()), 'use a fresh output directory; results are never overwritten')
        metadata = design(args)
        (out / 'binaries').mkdir(parents=True)
        frozen = {}
        for v in 'AB':
            original = (getattr(args, 'binary_' + v.lower()) or args.binary).resolve()
            if original not in frozen:
                frozen[original] = freeze(original, out / 'binaries' / v)
            metadata['variants'][v] = dict(frozen[original], evaluator=getattr(args, v.lower()))
        if args.texture:
            metadata['texture_asset'] = freeze(args.texture, out / ('texture' + args.texture.suffix))
            metadata['config']['texture'] = metadata['texture_asset']['file']
        (out / 'metadata.json').write_text(json.dumps(metadata, indent=2) + '\n')
        groups, outputs = defaultdict(list), {}
        total = len(metadata['configurations']) * metadata['repeats'] * 2
        print(f"{args.profile}: {len(metadata['configurations'])} configurations, {total} processes")
        with (out / 'samples.jsonl').open('w') as stream:
            for sweep, order in enumerate(metadata['schedules']):
                for i, case in enumerate(metadata['configurations']):
                    for position, v in enumerate(order):
                        spec = metadata['variants'][v]
                        u, w = metadata['cells'][case['scene']]
                        config = dict(metadata['config'], **case, mode=metadata['mode'],
                                      evaluator=spec['evaluator'], cells_u=u, cells_v=w)
                        command = [spec['file'], *[item for k, value in config.items() if value is not None
                                                  for item in ('--' + k.replace('_', '-'), str(value))]]
                        result = subprocess.run(command, capture_output=True, text=True, timeout=args.timeout_seconds, cwd=ROOT)
                        require(result.returncode == 0, f'native failed ({result.returncode}): {result.stderr[-4000:]}')
                        records = [line[6:] for line in (result.stdout + '\n' + result.stderr).splitlines() if line.startswith('BENCH ')]
                        require(len(records) == 1, 'expected exactly one BENCH JSON record')
                        native = json.loads(records[0])
                        validate_native(native, config)
                        key, value = (i, v), fingerprint(native)
                        if not args.skip_output_checks:
                            require(key not in outputs or outputs[key] == value, 'output differs across within-variant repeats')
                        other = (i, 'B' if v == 'A' else 'A')
                        if args.require_equal_output and other in outputs:
                            require(outputs[other] == value, 'cross-variant output differs')
                        outputs[key] = value
                        groups[i, sweep, v].append(native)
                        stream.write(json.dumps(dict(case_id=i, sweep=sweep, position=position, variant=v, native=native)) + '\n')
                        stream.flush()
                    print(f"Sweep {sweep + 1}, case {i + 1}/{len(metadata['configurations'])}", flush=True)
        report(out, metadata, groups, outputs)
        return 0
    except (ValueError, KeyError, TypeError, OSError, subprocess.SubprocessError) as exc:
        p.exit(1, f'error: {exc}\n')


if __name__ == '__main__':
    raise SystemExit(main())
