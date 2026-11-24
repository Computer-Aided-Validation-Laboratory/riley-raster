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
import re
import shutil
import statistics
import struct
import subprocess
import sys
import time

if __package__:
    from .bench_common import native_exe
else:
    from bench_common import native_exe

ROOT = Path(__file__).resolve().parent.parent
METRIC_OPTIONS = {'setup': 'resource_ns', 'render': 'render_ns', 'combined': 'combined_ns'}
METRICS = tuple(METRIC_OPTIONS.values())
MODE_METRICS = {'evaluation': METRICS, 'full-render': ('combined_ns',)}
FACTORS = ('threads', 'scene', 'pattern', 'jitter', 'occupancy', 'neighbors', 'softness')
BUILD_FIELDS = ('precision', 'simd', 'simd_vector_width', 'newton_solver', 'enable_all_evaluators',
                'speckle_mask_samples_per_cell', 'optimize', 'strip', 'zig_version', 'target_arch', 'cpu_model', 'cpu_features')
RESOURCE_FIELDS = ('resource_bytes', 'duplicated_disk_records', 'record_capacity')
COMMON_CONTROLS = ('mode', 'evaluator', 'scene', 'pattern', 'threads', 'width', 'height',
                   'frames', 'texture', 'texture_filter')
PERLIN_CONTROLS = ('perlin_threshold', 'perlin_transition')

# These are runner workload definitions, not defaults read from the executable.
RAW_RADIUS = .35
RAW_SOFTNESS = .04
RAW_CELLS = dict(plate=[320, 192], sphere=[256, 160])


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
    """Normalize profile-dependent variant defaults in place and build the frozen design."""
    tuning = args.profile == 'tuning'
    production = args.profile == 'full-render'
    require(not production or all(metric == 'combined' for metric in args.metrics or ()),
            'full-render supports only --metrics combined')
    args.a = args.a or ('auto' if production else 'cell-binned')
    args.b = args.b or ('auto' if production else 'list-indexed')
    repeats = args.repeats if args.repeats is not None else (12 if tuning else 16)
    alpha = args.alpha if args.alpha is not None else (.05 if tuning else .10)
    texture_only = args.a == args.b == 'texture'
    if texture_only and not production:
        requested = set(args.metrics or ())
        require('setup' not in requested, '--metrics setup is not measured for raw texture/texture')
        require(not {'combined', 'render'} <= requested,
                '--metrics combined and render are identical for raw texture/texture; choose one')
        default_metrics = ['render']
    else:
        default_metrics = ['combined'] if tuning or production else ['setup', 'render']
    if 'texture' in (args.a, args.b):
        require(args.texture, 'texture mapping requires --texture')
    if production:
        require(all(v in ('auto', 'texture') for v in (args.a, args.b)),
                'full-render requires production default evaluators; use auto or texture')
    else:
        require('auto' not in (args.a, args.b), 'raw evaluation requires explicit evaluators or texture')
    perlin = {key: getattr(args, key) for key in PERLIN_CONTROLS}
    procedural_controls = (args.jitter, args.occupancy, args.neighbors, args.radius,
                           args.softness, args.coverage, args.cell_size)
    if texture_only:
        require(all(v is None for v in (*procedural_controls, args.seed, args.cells_plate,
                                       args.cells_sphere, *perlin.values()))
                and not args.include_full_occupancy_single_neighbor,
                'texture/texture does not accept procedural controls')
    if args.case_file:
        require(all(v is None for v in (args.scenes, args.patterns, args.workers, *procedural_controls,
                                       *(perlin.values() if production else ()))),
                '--case-file cannot be mixed with case factor or physical control overrides')
    overrides = (args.scenes, args.patterns, args.jitter, args.occupancy, args.neighbors)
    radius = args.radius if production else (RAW_RADIUS if args.radius is None else args.radius)
    softness = args.softness if production else (RAW_SOFTNESS if args.softness is None else args.softness)
    require(math.isfinite(alpha) and 0 < alpha < 1, 'alpha must be between 0 and 1')
    require(args.permutations > 0, 'permutations must be positive')
    require(math.isfinite(args.timeout_seconds) and args.timeout_seconds > 0, 'timeout must be positive and finite')
    cells = dict(plate=args.cells_plate or RAW_CELLS['plate'], sphere=args.cells_sphere or RAW_CELLS['sphere'])
    require(all(math.isfinite(x) and x > 0 for x in (args.width, args.height, args.frames, *cells["plate"], *cells["sphere"])),
            'dimensions, frames and cells must be positive')
    require(args.seed is None or 0 <= args.seed < 2**32, 'seed must be uint32')
    if not production and not texture_only:
        require(math.isfinite(radius) and radius > 0, 'radius must be positive and finite')
        require(math.isfinite(softness) and softness > 0, 'invalid soft-case softness')
        require(args.perlin_threshold is None or math.isfinite(args.perlin_threshold),
                'Perlin threshold must be finite')
        require(args.perlin_transition is None or math.isfinite(args.perlin_transition)
                and args.perlin_transition >= 0, 'Perlin transition must be finite and nonnegative')
    require(all(x == 'available-cpus' or x.isdecimal() and int(x) > 0 for x in args.workers or ()),
            'workers must be positive integers or available-cpus')
    workers = sorted(set(available_cpus() if x == 'available-cpus' else int(x)
                         for x in (args.workers or ['1', 'available-cpus'])))
    if not production and not texture_only:
        require(all(math.isfinite(x) and 0 <= x <= 1 for x in args.occupancy or []),
                'occupancy must be in [0,1]')
        require(all(math.isfinite(x) and x >= 0 for x in args.jitter or []),
                'raw jitter must be finite and nonnegative')
    components = [(['plate', 'sphere'], ['hard', 'gaussian'], [0, .08], [.7, 1], [1, 4, 9])]
    if production:
        require(args.neighbors is None and not args.include_full_occupancy_single_neighbor,
                'full-render has no neighborhood controls; production defaults only')
        require(args.cells_plate is None and args.cells_sphere is None,
                'reference-grid controls require raw evaluation; use --cell-size for Perlin')
        components = [(['plate', 'sphere'], ['hard', 'gaussian'], [0], [1])]
    else:
        require(args.coverage is None and args.cell_size is None,
                '--coverage and --cell-size require full-render')
    if tuning:
        components = [(['plate'], ['hard'], [0, .08], [.7, 1], [9]),
                      (['sphere'], ['hard'], [.08], [.7], [9]),
                      (['plate'], ['hard'], [.08], [.7], [4]),
                      (['plate'], ['gaussian'], [.08], [.7], [9])]
    if args.case_file:
        cases = load_cases(args.case_file, production=production, texture_only=texture_only)
    elif texture_only:
        cases = [dict(threads=threads, scene=scene, pattern=pattern)
                 for threads, scene, pattern in product(workers, dict.fromkeys(args.scenes or ['plate', 'sphere']),
                                                        dict.fromkeys(args.patterns or ['hard']))]
    else:
        cases = []
        raw_perlin_pairs = set()
        for component in components:
            scenes, patterns, *dot_factors = (override if override is not None else default
                                               for override, default in zip(overrides, component))
            for threads, scene, pattern in product(workers, scenes, patterns):
                if pattern == 'perlin':
                    if production:
                        case = dict(threads=threads, scene=scene, pattern=pattern, cell_size=args.cell_size,
                                    **{k: v for k, v in perlin.items() if v is not None})
                        if case not in cases:
                            cases.append(case)
                    elif (threads, scene) not in raw_perlin_pairs:
                        raw_perlin_pairs.add((threads, scene))
                        cases.append(dict(threads=threads, scene=scene, pattern=pattern, jitter=None,
                                          occupancy=None, neighbors=None, radius=None, softness=0.))
                    continue
                for values in product(*dot_factors):
                    case = dict(zip(FACTORS, (threads, scene, pattern, *values)))
                    if (not tuning and not production and args.occupancy is None and not args.include_full_occupancy_single_neighbor
                            and case['neighbors'] == 1 and case['occupancy'] == 1):
                        continue
                    case['softness'] = softness if pattern == 'soft' else 0.
                    if production:
                        case.update(coverage=args.coverage, radius=radius)
                    if case not in cases:
                        cases.append(case)
        if production:
            patterns = {case['pattern'] for case in cases}
            require(patterns - {'perlin'} or all(x is None for x in (
                    args.coverage, args.radius, args.jitter, args.occupancy, args.softness)),
                    'physical controls require disk/Gaussian cases')
            require(not args.softness or 'soft' in patterns, 'positive softness requires soft disk cases')
            require('perlin' in patterns or all(x is None for x in (args.cell_size, *perlin.values())),
                    'Perlin controls require Perlin cases')
            for case in cases:
                validate_physical_case(case)
    if not production and any(evaluator not in ('texture', 'mock') for evaluator in (args.a, args.b)):
        require(all(case['pattern'] == 'perlin' or case['occupancy'] > 0 for case in cases),
                'disk/Gaussian occupancy must be positive for procedural evaluators')
    return dict(profile=args.profile, mode='full-render' if production else 'evaluation',
                configurations=cases, repeats=repeats, schedules=schedules(repeats), alpha=alpha,
                metrics=[METRIC_OPTIONS[x] for x in dict.fromkeys(args.metrics or default_metrics)],
                permutations=args.permutations, permutation_seed=20261005,
                inference='two-sided blocked sum contrast; exact <=200000 subsets/block, otherwise Monte Carlo plus-one; joint Holm',
                require_equal_output=args.require_equal_output, skip_output_checks=args.skip_output_checks,
                config=dict(width=args.width, height=args.height, frames=args.frames,
                            seed=args.seed, texture=None, texture_filter=args.texture_filter,
                            **({} if production or texture_only else dict(
                                radius=None if args.case_file else radius, **perlin))),
                cells={} if production or texture_only else cells, variants={})


def load_cases(path: Path, *, production: bool = False, texture_only: bool = False) -> list[dict]:
    """Explicit non-Cartesian cases; resolve worker aliases once and deduplicate."""
    raw = json.loads(path.read_text(encoding='utf-8'))
    require(isinstance(raw, list) and raw, 'case file must contain a nonempty JSON list')
    cases = []
    for row in raw:
        require(isinstance(row, dict), 'invalid case fields')
        common = {'threads', 'scene', 'pattern'}
        optional = set()
        if texture_only:
            fields = common
        elif production and row.get('pattern') == 'perlin':
            fields = common | {'cell_size'}
            optional = set(PERLIN_CONTROLS)
        elif production:
            fields = set(FACTORS) - {'neighbors'} | {'coverage', 'radius'}
        else:
            fields = set(FACTORS) | {'radius'}
        require(fields <= row.keys() <= fields | optional, 'invalid case fields')
        case = dict(row)
        if case['threads'] == 'available-cpus':
            case['threads'] = available_cpus()
        require(type(case['threads']) is int and 0 < case['threads'] < 65536, 'invalid case workers')
        require(case['scene'] in ('plate', 'sphere'), 'invalid case scene')
        require(case['pattern'] in ('hard', 'soft', 'gaussian', 'perlin'), 'invalid case pattern')
        if production and not texture_only:
            validate_physical_case(case)
        elif not texture_only:
            perlin = case['pattern'] == 'perlin'
            require(case['neighbors'] is None if perlin else
                    type(case['neighbors']) is int and case['neighbors'] in (1, 4, 9), 'invalid case neighbors')
            for key in ('radius', 'jitter', 'occupancy', 'softness'):
                value = case[key]
                require((perlin and key != 'softness' and value is None)
                        or (type(value) in (int, float) and math.isfinite(value)), 'invalid case ' + key)
            radius, jitter, occupancy = (case[key] for key in ('radius', 'jitter', 'occupancy'))
            require((occupancy is None or 0 <= occupancy <= 1) and (jitter is None or jitter >= 0),
                    'invalid case occupancy/jitter')
            require((radius is None or radius > 0) and case['softness'] >= 0, 'invalid case radius/softness')
            require((case['softness'] > 0) == (case['pattern'] == 'soft'), 'invalid case edge softness')
            if perlin:
                case.update(jitter=None, occupancy=None, radius=None)

        if case not in cases:
            cases.append(case)
    return cases


def validate_physical_case(case):
    """Validate public inputs, not the physical solver's derived model."""
    controls = (('cell_size', *(key for key in PERLIN_CONTROLS if key in case))
                if case['pattern'] == 'perlin' else ('coverage', 'radius', 'jitter', 'occupancy', 'softness'))
    for key in controls:
        require(type(case.get(key)) in (int, float) and math.isfinite(case[key]), 'full-render requires finite ' + key)
    if case['pattern'] == 'perlin':
        require(case['cell_size'] > 0 and case.get('perlin_transition', 0) >= 0, 'invalid Perlin controls')
    else:
        require(0 < case['coverage'] < 1 and case['radius'] > 0, 'invalid physical coverage/radius')
        require(0 < case['occupancy'] <= 1 and 0 <= case['jitter'] <= .5 * case['radius'], 'invalid physical occupancy/jitter')
        require(case['softness'] >= 0 and (case['softness'] > 0) == (case['pattern'] == 'soft'), 'invalid physical softness')


def freeze(original, destination):
    shutil.copy2(original, destination)
    with destination.open('rb') as stream:
        sha = hashlib.file_digest(stream, 'sha256').hexdigest()
    return dict(original_path=str(original.resolve()), file=str(destination), sha256=sha)


def validate_echo(actual, expected, precision, path=''):
    if isinstance(expected, dict):
        require(isinstance(actual, dict), 'invalid native config object: ' + path)
        require(path != 'physical_params.' or set(actual) == set(expected), 'invalid physical parameter tag')
        for key, value in expected.items():
            require(key in actual, 'missing native config field: ' + path + key)
            validate_echo(actual[key], value, precision, path + key + '.')
        return
    if isinstance(expected, list):
        require(isinstance(actual, list) and len(actual) == len(expected), 'invalid native config array: ' + path)
        for index, (value, wanted) in enumerate(zip(actual, expected)):
            validate_echo(value, wanted, precision, path + str(index) + '.')
        return
    numeric = type(expected) is float and type(actual) in (int, float)
    try:
        if precision == 'f32' and numeric:
            # std.json.Stringify promotes f32 to f64 before formatting JSON numbers.
            equal = actual == native_float(expected, precision)
        else:
            equal = actual == expected
    except OverflowError as exc:
        raise ValueError('native config echo outside f32 range: ' + path.rstrip('.')) from exc
    require(equal and (numeric or type(actual) is type(expected)), 'native config echo mismatch: ' + path.rstrip('.'))


def validate_native(native, config):
    require(isinstance(native, dict), 'BENCH record must be a JSON object')
    validate_echo(native, config, native.get('precision'))
    mode = config['mode']
    for metric in MODE_METRICS[mode]:
        require(type(native.get(metric)) is int and native[metric] >= 0, f'invalid {metric}: integer ns required')
    evaluation = mode == 'evaluation'
    if evaluation:
        require(native['combined_ns'] == native['resource_ns'] + native['render_ns'], 'invalid combined timing')
        if config['evaluator'] == 'texture':
            require(native['resource_ns'] == 0, 'raw texture requires resource_ns == 0')
    else:
        require('resource_ns' not in native and 'render_ns' not in native,
                'full-render must omit resource_ns and render_ns')
    checksum, image_hash = native['checksum'], native['image_hash']
    if evaluation:
        require(type(checksum) is int and 0 <= checksum < 2**64 and image_hash is None, 'invalid raw checksum')
    else:
        require(checksum is None and isinstance(image_hash, str) and re.fullmatch('[0-9a-f]{64}', image_hash),
                'invalid full-render image hash')
    require(native.get('evaluation_counters_available') is evaluation, 'invalid counter availability')
    require(type(native.get('shaded_samples')) is int
            and (native['shaded_samples'] > 0 if evaluation else native['shaded_samples'] == 0), 'invalid shaded sample count')
    images = 0 if evaluation else config['width'] * config['height'] * config['frames']
    require(type(native.get('image_samples')) is int and native['image_samples'] == images, 'invalid mono image sample count')
    if 'backface_rejections' in native:
        require(type(native['backface_rejections']) is int and native['backface_rejections'] >= 0, 'invalid rejection count')
    require(native.get('precision') in ('f32', 'f64'), 'missing/invalid native precision')
    require(native.get('simd') in ('on', 'off'), 'missing/invalid native SIMD mode')
    require(isinstance(native.get('workload_mode'), str) and native['workload_mode'], 'missing native workload_mode')
    for key in RESOURCE_FIELDS:
        value = native.get(key)
        require(value is None or type(value) is int and value >= 0, 'invalid resource metric: ' + key)
    if native.get('record_capacity') is not None and native.get('duplicated_disk_records') is not None:
        require(native['duplicated_disk_records'] <= native['record_capacity'], 'live records exceed capacity')


def catalogue_sampling_routes(catalogue):
    """Read native canonicalization; never duplicate evaluator-specific policy here."""
    fields = ('evaluator', 'pattern', 'neighbors', 'soft_edges')
    samples = catalogue['sampling_configs']
    routes = {}
    require(isinstance(samples, list) and samples, 'missing native sampling catalogue')
    for row in samples:
        require(isinstance(row, dict) and set(row) == set(fields)
                and isinstance(row['evaluator'], str) and row['evaluator']
                and (row['pattern'] is None or isinstance(row['pattern'], str))
                and (row['neighbors'] is None or type(row['neighbors']) is int)
                and (row['soft_edges'] is None or type(row['soft_edges']) is bool),
                'invalid native sampling descriptor')
    require(len({tuple(row[k] for k in fields) for row in samples}) == len(samples),
            'duplicate native sampling config')
    for row in catalogue['configs']:
        require(isinstance(row, dict) and set(row) == {*fields, 'sampling_index'},
                'invalid native generation descriptor')
        key = tuple(row[k] for k in fields)
        index = row['sampling_index']
        require(type(index) is int and 0 <= index < len(samples), 'invalid native sampling index')
        require(key not in routes, 'duplicate native generation config')
        routes[key] = dict(sampling_index=index, sampling=samples[index])
    return routes


def validate_sampling_identity(identity, generation, routes):
    """Validate stored generation and actual dispatch as distinct prepared identities."""
    key = tuple(generation[k] for k in ('evaluator', 'pattern', 'neighbors', 'soft_edges'))
    route = routes[key]
    require(isinstance(identity.get('backing'), str) and identity['backing'], 'invalid prepared backing identity')
    stored_generation = None if identity.get('backing') == 'none' else generation['evaluator']
    require(identity['generation_evaluator'] == stored_generation, 'wrong stored generation identity')
    require(type(identity['sampling_index']) is int and identity['sampling_index'] == route['sampling_index'],
            'wrong actual sampling index')
    require(identity['sampling_evaluator'] == route['sampling']['evaluator'], 'wrong actual sampling evaluator')


def fingerprint(native):
    return tuple(native.get(k) for k in ('image_hash', 'checksum', 'shaded_samples',
                                        'backface_rejections', 'image_samples'))


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
    mode = metadata['mode']
    records = []
    factors = tuple(dict.fromkeys(k for case in metadata['configurations'] for k in case))
    for i, case in enumerate(metadata['configurations']):
        for metric in MODE_METRICS[mode]:
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
    (out / 'comparison.json').write_text(json.dumps(records, indent=2) + '\n', encoding='utf-8')
    n = len(metadata['configurations'])
    lines = ['# Speckle A/B comparison', '',
             f"{metadata['profile']} / {metadata['mode']}: {n} configurations, {2*n} variant groups, "
             f"{metadata['repeats']} runs/variant/case; schedules {' / '.join(metadata['schedules'])}.",
             f"Holm alpha={metadata['alpha']}, {len(primary)} tests. B/A <1 favors B; tests use mean contrasts, tables use medians.",
             ('Combined times the production render operation, including procedural resource preparation. '
              'Output hashing is untimed. Reported production policy is declared, not observed.'
              if mode == 'full-render' else 'Combined = setup + evaluation, not wall time.'),
             'Blocked permutation tests assume within-block exchangeability. Untested metrics are descriptive; '
             'non-significance is not equivalence.',
             f"Texture filter: {metadata['config']['texture_filter']}. Procedural factors do not change the frozen texture. "
             f"Output mismatch cases: {sum(outputs[i, 'A'] != outputs[i, 'B'] for i in range(n))}.", '',
             f"| Case | Factors ({', '.join(factors)}) | Metric | A ns | B ns | B/A | p | Holm p | Detected |",
             '|---|---|---|---:|---:|---:|---:|---:|---|']
    lines.insert(2, 'Native identity: ' + '; '.join(
        f"{v}: SHA256 {spec['sha256']}"
        for v, spec in metadata['variants'].items()) + '. See metadata.json for exact build/workload identities and catalogues.')
    lines.insert(3, 'See metadata.json for resource metric definitions; raw native records and process logs are retained.')
    if metadata.get('skip_output_checks', False):
        lines.insert(2, 'Within-repeat and cross-variant output consistency checks disabled; no image consistency guarantee.')
    for r in records:
        ratio = f"{r['ratio']:.6g}" if r['ratio'] is not None else 'n/a'
        lines.append(f"| {r['case_id']} | {tuple(r['case'].get(k) for k in factors)} | {r['metric']} | "
                     f"{r['a_median_ns']:g} | {r['b_median_ns']:g} | {ratio} | {r.get('p', 'descriptive')} | "
                     f"{r.get('holm_p', '—')} | {r.get('detected', '—')} |")
    (out / 'comparison.md').write_text('\n'.join(lines) + '\n', encoding='utf-8')
    print(f"Report: {out / 'comparison.md'}")


def parser():
    p = argparse.ArgumentParser(description=__doc__,
        epilog='Use a fresh output directory; no resume or overwrite. '
        'The runner checks catalogue and build compatibility, '
        'then collects two balanced sweeps without warmups. Native observations check support and mesh '
        'feasibility. Frozen inputs, raw observations, process logs and reports are saved in --out.')
    p.add_argument('--out', type=Path, required=True, help='fresh comparison directory')
    p.add_argument('--profile', choices=('tuning', 'full', 'full-render'), default='tuning',
                   help='full is raw evaluation; full-render uses physical inputs and the production policy '
                        '(default: %(default)s)')
    p.add_argument('--a', help='catalog evaluator or texture; default cell-binned in evaluation, auto in full-render')
    p.add_argument('--b', help='catalog evaluator or texture; default list-indexed in evaluation, auto in full-render; use classified-binned with --patterns hard --neighbors 9')
    p.add_argument('--binary', type=Path,
        default=native_exe(ROOT / 'zig-out/bin/bench_speckle_evaluators_f64_simd'),
        help='common native binary (default: %(default)s)')
    for v in 'ab':
        p.add_argument('--binary-' + v, type=Path, help='override common binary for ' + v.upper())
    p.add_argument('--case-file', type=Path, help='nonempty JSON list with exact keys. Raw (hard|soft|gaussian|perlin): '
                   'threads, scene, pattern, radius, jitter, occupancy, neighbors, softness. Raw Perlin neighbors is null; '
                   'radius, jitter and occupancy may be null and are ignored. '
                   'Full-render hard|soft|gaussian: threads, scene, pattern, coverage, radius, jitter, occupancy, softness. '
                   'Full-render perlin: threads, scene, pattern, cell_size; optional perlin_threshold and perlin_transition. '
                   'Texture/texture (either mode): threads, scene, pattern (scenario label only). '
                   'scene is plate|sphere; threads is a positive integer or available-cpus')
    p.add_argument('--workers', nargs='+', help='integers or available-cpus; default 1 and affinity CPU count, deduplicated')
    for name, choices in (('scenes', ('plate', 'sphere')), ('patterns', ('hard', 'soft', 'gaussian', 'perlin'))):
        p.add_argument('--' + name, nargs='+', choices=choices, help='replace profile factor')
    p.add_argument('--neighbors', nargs='+', type=int, choices=(1, 4, 9), help='replace profile factor')
    p.add_argument('--jitter', nargs='+', type=float,
                   help='replace radius jitter factor: raw cell units or full-render reference-mesh units '
                        '(default: 0 for full-render disk/Gaussian)')
    p.add_argument('--occupancy', nargs='+', type=float,
                   help='replace cell occupancy factor (default: 1 for full-render disk/Gaussian)')
    p.add_argument('--include-full-occupancy-single-neighbor', action='store_true', help='include the normally excluded pair')
    for name, default in (('frames', 16), ('width', 3840), ('height', 2160)):
        p.add_argument('--' + name, type=int, default=default, help='native workload ' + name + ' (default: %(default)s)')
    p.add_argument('--cells-plate', nargs=2, type=float, help=f'raw evaluation plate UV cell counts (profile default {RAW_CELLS["plate"]})')
    p.add_argument('--cells-sphere', nargs=2, type=float, help=f'raw evaluation sphere UV cell counts (profile default {RAW_CELLS["sphere"]})')
    p.add_argument('--seed', type=lambda x: int(x, 0), help='procedural uint32 seed (decimal or hex); default from binary A')
    p.add_argument('--perlin-threshold', type=float, help='Perlin noise threshold; default from binary A')
    p.add_argument('--perlin-transition', type=float, help='Perlin transition width; default from binary A; 0 selects hard threshold')
    p.add_argument('--coverage', type=float, help='required full-render disk/Gaussian nominal coverage')
    p.add_argument('--radius', type=float, help=f'required physical radius in full-render; raw normalized radius defaults to {RAW_RADIUS}')
    p.add_argument('--cell-size', type=float, help='required full-render Perlin cell size in reference-mesh units')
    p.add_argument('--softness', type=float, help=f'soft cases only: required physical half-width in full-render; raw defaults to {RAW_SOFTNESS}')
    p.add_argument('--texture', type=Path, help='BMP asset required for texture mapping; copied before execution')
    p.add_argument('--texture-filter', choices=('nearest', 'linear', 'cubic_catmull_rom'), default='cubic_catmull_rom',
                   help='texture sampling: Catmull–Rom uses lut_lerp; nearest/linear use direct '
                        '(default: %(default)s)')
    p.add_argument('--alpha', type=float, help='override profile family-wise alpha')
    p.add_argument('--repeats', type=int, help='override even TOTAL runs per variant >=2; never capped')
    p.add_argument('--metrics', nargs='+', choices=tuple(METRIC_OPTIONS),
                   help='jointly tested metrics: setup=resource_ns, render=render_ns, combined=combined_ns. '
                        'Defaults to setup and render for full, combined otherwise. Raw texture/texture '
                        'defaults to render, rejects setup, and accepts only one of render or combined; '
                        'full-render only supports combined')
    p.add_argument('--permutations', type=int, default=100000,
                   help='Monte Carlo draws for large repeat counts (default: %(default)s)')
    output_checks = p.add_mutually_exclusive_group()
    output_checks.add_argument('--require-equal-output', action='store_true', help='also require exact cross-variant fingerprints')
    output_checks.add_argument('--skip-output-checks', action='store_true', help='disable within-repeat and cross-variant fingerprint checks; retain native validation')
    p.add_argument('--timeout-seconds', type=float, default=900,
                   help='per-native-process timeout (default: %(default)s)')
    return p


def run_logged(command: list[str], out: Path, label: str, timeout: float | None = None) -> list[bytes]:
    """Retain the exact streams and argv; return lines for protocol parsing."""
    logs = out / 'logs'
    logs.mkdir(exist_ok=True)
    record = dict(command=command, cwd=str(ROOT), started_ns=time.time_ns(), label=label)
    stdout, stderr = b'', b''
    try:
        result = subprocess.run(command, capture_output=True, timeout=timeout, cwd=ROOT)
        stdout, stderr = result.stdout, result.stderr
        record['returncode'] = result.returncode
    except subprocess.TimeoutExpired as exc:
        stdout, stderr = exc.stdout or b'', exc.stderr or b''
        record['timeout_seconds'] = timeout
        raise ValueError(f'command timed out after {timeout}s; full logs: {logs / label}') from exc
    except OSError as exc:
        record['error'] = str(exc)
        raise OSError(f'{exc}; full logs: {logs / label}') from exc
    finally:
        record['finished_ns'] = time.time_ns()
        (logs / (label + '.stdout')).write_bytes(stdout)
        (logs / (label + '.stderr')).write_bytes(stderr)
        (logs / (label + '.command.json')).write_text(json.dumps(record, indent=2) + '\n', encoding='utf-8')
        with (out / 'commands.jsonl').open('a', encoding='utf-8') as stream:
            stream.write(json.dumps(record) + '\n')
    require(result.returncode == 0, f'command failed ({result.returncode}); full logs: {logs / label}')
    return stdout.splitlines() + stderr.splitlines()


def shape_controls(config):
    """Translate runner case tags; evaluator/neighborhood policy remains native-owned."""
    return dict(pattern='disk' if config['pattern'] in ('hard', 'soft') else config['pattern'],
                soft_edges=config.get('softness', 0) > 0)


def production_config(catalogue, config):
    controls = shape_controls(config)
    matches = [row for row in catalogue['production_configs']
               if all(row[k] is None or row[k] == value for k, value in controls.items())]
    require(len(matches) == 1, 'requested controls have no unique native production configuration')
    return dict(matches[0])


def generation_config(catalogue, config):
    if config['evaluator'] == 'texture':
        require('texture' in catalogue['evaluators'], 'texture absent from native catalogue')
        return None
    if config.get('mode') == 'full-render':
        require(config['evaluator'] == 'auto' and 'neighbors' not in config,
                'full-render requires the automatic production policy')
        return production_config(catalogue, config)
    require(config['evaluator'] in catalogue['evaluators'], 'evaluator absent from native catalogue')
    require(catalogue['overrides_enabled'] is True, 'native evaluator overrides disabled')
    shape = shape_controls(config)
    controls = dict(evaluator=config['evaluator'], pattern=shape['pattern'],
                    neighbors=config['neighbors'], soft_edges=shape['soft_edges'])
    matches = [row for row in catalogue['configs']
               if all(row[k] is None or row[k] == value for k, value in controls.items())]
    require(len(matches) == 1, 'requested controls have no unique native generation configuration')
    return {k: matches[0][k] for k in controls}


def case_config(metadata, case, variant):
    evaluator = metadata['variants'][variant]['evaluator']
    config = {**metadata['config'], **case, 'mode': metadata['mode'], 'evaluator': evaluator}
    if evaluator == 'texture':
        return {k: config[k] for k in COMMON_CONTROLS if k in config}
    raw = metadata['mode'] == 'evaluation'
    # Pin omitted controls to A's advertised values, even if B differs.
    defaults = metadata['variants']['A']['catalogue']['defaults']
    for key in ('seed', *(PERLIN_CONTROLS if raw or case['pattern'] == 'perlin' else ())):
        if config.get(key) is None:
            config[key] = defaults[key]
    if raw:
        config['cells_u'], config['cells_v'] = metadata['cells'][case['scene']]
    return config


def comparable_build_identity(build):
    """Copy of a build identity for comparison; CPU features are a set, so native order is ignored."""
    return dict(build, cpu_features=sorted(build['cpu_features']))


def validate_identity(native, config, spec, routes, generation):
    build = spec['build_identity']
    require(native['precision'] == build['precision'] and native['simd'] == build['simd'],
            'native precision/SIMD differs from frozen identity')
    require(native['workload_mode'] == spec['workload_modes'][config['mode']], 'native workload_mode mismatch')
    native_build = native.get('build_identity')
    require(isinstance(native_build, dict) and isinstance(native_build.get('cpu_features'), list)
            and all(isinstance(name, str) for name in native_build['cpu_features'])
            and comparable_build_identity(native_build) == comparable_build_identity(build),
            'native build identity differs from catalogue')
    require(all(key in native for key in RESOURCE_FIELDS), 'missing nullable resource metrics')
    require('prepared_identity' in native, 'missing prepared identity field')
    identity = native['prepared_identity']
    if config['mode'] == 'evaluation':
        require(isinstance(identity, dict), 'missing prepared identity')
        if generation is not None:
            validate_sampling_identity(identity, generation, routes)
        else:
            require(identity == dict(generation_evaluator=None, sampling_evaluator=None,
                                     sampling_index=None, backing='none'), 'texture has procedural prepared identity')
    else:
        require(identity is None, 'full-render prepared identity was not collected')
    evaluation = config['mode'] == 'evaluation'
    require('resolved_generation' in native and native['resolved_generation'] == (generation if evaluation else None),
            'wrong generation identity')
    require('generation_policy' in native and native['generation_policy'] == (None if evaluation else generation),
            'wrong declared generation policy')


def native_float(value, precision):
    """Normalize a requested float exactly as the native CLI's selected precision."""
    return struct.unpack('f', struct.pack('f', value))[0] if precision == 'f32' else float(value)


def expected_native(config):
    """Build one expected echo in native units; the independent actual comes from grid/mesh inputs."""
    raw = config['mode'] == 'evaluation'
    expected = {key: config[key] for key in COMMON_CONTROLS if config.get(key) is not None}
    expected.update(physical_params=None, resolved_grid=None)
    if config['evaluator'] == 'texture':
        return expected
    pattern = shape_controls(config)['pattern']
    names = (dict(radius_mean='radius', radius_jitter='jitter', occupancy='occupancy', edge_softness='softness',
                  perlin_coverage_threshold='perlin_threshold', perlin_coverage_transition_width='perlin_transition') if raw else
             dict(cell_size='cell_size', threshold='perlin_threshold', transition_width='perlin_transition') if pattern == 'perlin' else
             dict(coverage='coverage', radius='radius', jitter='jitter', occupancy='occupancy', edge_softness='softness'))
    params = {native: config[option] if option == 'seed' else float(config[option])
              for native, option in dict(names, seed='seed').items() if config.get(option) is not None}
    if raw and 'cells_u' in config:
        params['cells_per_uv'] = [float(config[key]) for key in ('cells_u', 'cells_v')]
    if raw:
        params.update(pattern=pattern, evaluator=config['evaluator'].replace('-', '_'))
        if 'neighbors' in config:
            params['neighbor_count'] = {None: None, 1: 'one', 4: 'four', 9: 'nine'}[config['neighbors']]
        expected['resolved_grid'] = params
    else:
        expected['physical_params'] = {pattern: params}
    return expected


class SampleValidator:
    """Cache per-variant routes/case controls; inspect each new observation exactly once."""
    def __init__(self, metadata):
        mode = metadata['mode']
        require(mode in MODE_METRICS, 'invalid benchmark mode')
        metrics = metadata['metrics']
        require(isinstance(metrics, list) and metrics and all(metric in MODE_METRICS[mode] for metric in metrics),
                f'invalid requested timing metrics for {mode}')
        self.metadata = metadata
        self.routes = {variant: catalogue_sampling_routes(spec['catalogue'])
                       for variant, spec in metadata['variants'].items()}
        self.cases = {}
        for i, case in enumerate(metadata['configurations']):
            for variant, spec in metadata['variants'].items():
                config = case_config(metadata, case, variant)
                self.cases[i, variant] = (config, generation_config(spec['catalogue'], config), expected_native(config))
        self.outputs, self.positions = {}, set()
        self.groups = defaultdict(list)

    def add(self, row):
        metadata = self.metadata
        i, sweep, position, variant = (row[k] for k in ('case_id', 'sweep', 'position', 'variant'))
        require(type(i) is int and 0 <= i < len(metadata['configurations'])
                and type(sweep) is int and sweep in (0, 1), 'invalid sample location')
        require(type(position) is int and 0 <= position < len(metadata['schedules'][sweep]), 'invalid sample position')
        require(metadata['schedules'][sweep][position] == variant, 'sample order differs from schedule')
        location = (i, sweep, position)
        require(location not in self.positions, 'duplicate sample position')
        native = row['native']
        config, generation, expected = self.cases[i, variant]
        validate_native(native, expected)
        validate_identity(native, config, metadata['variants'][variant], self.routes[variant], generation)
        key, value = (i, variant), fingerprint(native)
        if not metadata['skip_output_checks']:
            require(key not in self.outputs or self.outputs[key] == value, 'output differs across within-variant repeats')
        other = (i, 'B' if variant == 'A' else 'A')
        if metadata['require_equal_output'] and other in self.outputs:
            require(self.outputs[other] == value, 'cross-variant output differs')
        self.positions.add(location)
        self.outputs[key] = value
        self.groups[i, sweep, variant].append(native)

    def finish(self):
        require(len(self.positions) == len(self.metadata['configurations']) * self.metadata['repeats'] * 2,
                'partial results cannot produce complete-comparison statistics')
        return self.groups, self.outputs


def native_argv(binary, config):
    """Encode the variant's active controls, already normalized by case_config."""
    return [str(binary), *[item for key, value in config.items() if value is not None
                          for item in ('--' + key.replace('_', '-'), str(value))]]


def run_comparison(out, metadata):
    """Supervise both sweeps, validating each flushed observation once; never resume."""
    validator = SampleValidator(metadata)
    with (out / 'samples.jsonl').open('x', encoding='utf-8') as stream:
        for sweep in (0, 1):
            for i in range(len(metadata['configurations'])):
                for position, variant in enumerate(metadata['schedules'][sweep]):
                    spec = metadata['variants'][variant]
                    config = validator.cases[i, variant][0]
                    command = native_argv(spec['file'], config)
                    label = f'sweep-{sweep}-case-{i}-position-{position}-{variant}'
                    lines = run_logged(command, out, label, metadata['timeout_seconds'])
                    try:
                        records = [line[6:] for line in lines if line.startswith(b'BENCH ')]
                        require(len(records) == 1, 'expected exactly one BENCH JSON record')
                        row = dict(case_id=i, sweep=sweep, position=position, variant=variant, command=command,
                                   binary_sha256=spec['sha256'], native=json.loads(records[0].decode('utf-8')))
                        # Preserve even the failing observation; never report a partial comparison.
                        stream.write(json.dumps(row) + '\n')
                        stream.flush()
                        validator.add(row)
                    except (ValueError, KeyError, TypeError, IndexError) as exc:
                        raise ValueError(f'{exc}; full logs: {out / "logs" / label}') from exc
                print(f"Sweep {sweep + 1}, case {i + 1}/{len(metadata['configurations'])}", flush=True)
    return validator.finish()


def claim_output(out):
    """Claim a new or empty directory exclusively for this run, even if it fails."""
    message = 'use a fresh output directory; no resume; results are never overwritten'
    out.mkdir(parents=True, exist_ok=True)
    require(not any(out.iterdir()), message)
    try:
        # Both runners can see an empty directory; only one can create the claim.
        with (out / '.comparison-claim').open('x'):
            pass
    except FileExistsError as exc:
        raise ValueError(message) from exc


def prepare_binaries(out, args, metadata):
    """Freeze and catalogue the actual executables and require matching identities."""
    (out / 'binaries').mkdir()
    frozen = {}
    for variant in 'AB':
        original = (getattr(args, 'binary_' + variant.lower()) or args.binary).resolve()
        if original not in frozen:
            frozen[original] = freeze(original, native_exe(out / 'binaries' / variant))
        metadata['variants'][variant] = dict(frozen[original], evaluator=getattr(args, variant.lower()))
    catalogues = {}
    mode = metadata['mode']
    for variant, spec in metadata['variants'].items():
        if spec['file'] not in catalogues:
            lines = run_logged([spec['file'], '--list-evaluators'], out,
                               'catalogue-' + variant, args.timeout_seconds)
            records = [json.loads(line.decode('utf-8')) for line in lines if line.startswith(b'{')]
            require(len(records) == 1, 'expected exactly one native evaluator catalogue')
            catalogues[spec['file']] = records[0]
        spec['catalogue'] = catalogues[spec['file']]
        spec.update(build_identity=spec['catalogue']['build_identity'],
                    workload_modes=spec['catalogue']['workload_modes'])
        defaults = spec['catalogue']['defaults']
        require(isinstance(defaults, dict) and type(defaults.get('seed')) is int
                and 0 <= defaults['seed'] < 2**32
                and all(type(defaults.get(key)) in (int, float) and math.isfinite(defaults[key])
                        for key in PERLIN_CONTROLS)
                and defaults['perlin_transition'] >= 0, 'invalid native procedural defaults')
        require(set(spec['build_identity']) == set(BUILD_FIELDS), 'incomplete/unknown build identity fields')
        features = spec['build_identity']['cpu_features']
        require(isinstance(features, list) and all(isinstance(name, str) and name for name in features)
                and len(features) == len(set(features)), 'CPU features must be unique enabled Zig feature names')
        require(spec['build_identity']['precision'] in ('f32', 'f64') and spec['build_identity']['simd'] in ('on', 'off'),
                'invalid precision/SIMD identity')
        require(spec['build_identity']['optimize'] == 'ReleaseFast' and spec['build_identity']['strip'] is True,
                'benchmarks require ReleaseFast with debug information stripped')
        require(isinstance(spec['workload_modes'], dict) and isinstance(spec['workload_modes'].get(mode), str)
                and spec['workload_modes'][mode], 'missing workload identity')
    a, b = (metadata['variants'][variant] for variant in 'AB')
    require(comparable_build_identity(a['build_identity']) == comparable_build_identity(b['build_identity']),
            'A/B build configurations differ')
    require(a['workload_modes'][mode] == b['workload_modes'][mode], 'A/B workload modes differ')


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv

    p = parser()
    args = p.parse_args(argv)
    try:
        out = args.out.resolve()
        metadata = design(args)
        metadata.update(timeout_seconds=args.timeout_seconds, runner_argv=argv,
                        runner_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                        resource_metric_semantics=dict(
                            resource_bytes='retained backing bytes, excluding allocator overhead; null if uncollected',
                            duplicated_disk_records='live bin records summed from counts; null if uncollected',
                            record_capacity='allocated record slots, including unused slots; null if uncollected'))
        claim_output(out)
        try:
            prepare_binaries(out, args, metadata)
            if args.texture:
                metadata['texture_asset'] = freeze(args.texture, out / ('texture' + args.texture.suffix))
                metadata['config']['texture'] = metadata['texture_asset']['file']
        finally:
            (out / 'metadata.json').write_text(json.dumps(metadata, indent=2) + '\n', encoding='utf-8')
        print(f"{args.profile}: {len(metadata['configurations'])} configurations, "
              f"{len(metadata['configurations']) * metadata['repeats'] * 2} samples; two independent timing blocks", flush=True)
        groups, outputs = run_comparison(out, metadata)
        report(out, metadata, groups, outputs)
        return 0
    except (ValueError, KeyError, TypeError, IndexError, OSError, subprocess.SubprocessError) as exc:
        p.exit(1, f'error: {exc}\n')


if __name__ == '__main__':
    raise SystemExit(main())
