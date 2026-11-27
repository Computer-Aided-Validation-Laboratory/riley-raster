#!/usr/bin/env python3
"""Statistics/runner units plus opt-in, unmocked native catalogue and record smoke.

Build install-bench-speckle-evaluators in ReleaseFast with strip=true and
enable-all-evaluators=true, then set RILEY_SPECKLE_BENCH_BINARY to its executable
and run: python3 -m unittest scripts.tests.test_bench_speckle.NativeBenchmarkTests
"""
from concurrent.futures import ThreadPoolExecutor
from contextlib import nullcontext
from copy import deepcopy
import hashlib
import io
from itertools import combinations, product
import json
import math
import os
from pathlib import Path
import tempfile
from threading import Barrier
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from scripts import bench_speckle as bench



def artifact_directory():
    """Fresh per-test scope, retained only when an artifact root was requested."""
    root = os.environ.get('RILEY_SPECKLE_BENCH_ARTIFACT_DIR')
    if root:
        Path(root).mkdir(parents=True, exist_ok=True)
        return nullcontext(str(Path(tempfile.mkdtemp(prefix='bench-smoke-', dir=root)).resolve()))
    return tempfile.TemporaryDirectory()


def full_render_flags():
    return ['--coverage', '.5', '--radius', '.25']


def process_result(stdout='', stderr=''):
    return SimpleNamespace(returncode=0, stdout=stdout.encode('utf-8'), stderr=stderr.encode('utf-8'))


def read_samples(out):
    return [json.loads(line) for line in (out / 'samples.jsonl').read_text(encoding='utf-8').splitlines()]


class BenchmarkTests(unittest.TestCase):
    def args(self, *options):
        return bench.parser().parse_args(['--out', 'unused', *options])

    @patch.object(bench, 'available_cpus', return_value=14)
    def test_profiles_and_overrides(self, _):
        for profile, count, repeats, metrics, alpha in (
                ('tuning', 14, 12, ['combined_ns'], .05),
                ('full', 80, 16, ['resource_ns', 'render_ns'], .10),
                ('full-render', 8, 16, ['combined_ns'], .10)):
            d = bench.design(self.args('--profile', profile, *(full_render_flags() if profile == 'full-render' else [])))
            self.assertEqual((len(d['configurations']), d['repeats'], d['metrics'], d['alpha']),
                             (count, repeats, metrics, alpha))
            self.assertEqual(d['mode'], 'full-render' if profile == 'full-render' else 'evaluation')
        d = bench.design(self.args('--workers', '2', '2', '--scenes', 'sphere', '--patterns', 'soft',
                                   '--jitter', '.08', '--occupancy', '1', '--neighbors', '1',
                                   '--alpha', '.2', '--repeats', '6', '--metrics', 'setup', 'combined'))
        self.assertEqual(d['configurations'], [dict(threads=2, scene='sphere', pattern='soft',
                                                   jitter=.08, occupancy=1., neighbors=1, softness=.04)])
        self.assertEqual((d['alpha'], d['metrics']), (.2, ['resource_ns', 'combined_ns']))
        for options, count in ((['--occupancy', '1'], 24), (['--include-full-occupancy-single-neighbor'], 48)):
            self.assertEqual(len(bench.design(self.args('--profile', 'full', '--workers', '1', *options))['configurations']), count)
        production = ('--profile', 'full-render', *full_render_flags())
        for options in (('--repeats', '3'), ('--alpha', 'nan'), ('--frames', '0'), ('--occupancy', '2'),
                        ('--radius', 'inf'), ('--permutations', '0'), ('--softness', '0'), ('--a', 'texture'),
                        ('--perlin-threshold', 'nan'), ('--perlin-transition', '-.1'), ('--a', 'auto'),
                        ('--workers', 'two'), ('--workers', '0')):
            with self.subTest(options=options), self.assertRaises(ValueError):
                bench.design(self.args(*options))
        for options, message in ((('--a', 'classified-binned'), 'full-render requires production default evaluators'),
                                 (('--neighbors', '9'), 'full-render has no neighborhood controls'),
                                 (('--metrics', 'render'), 'full-render supports only --metrics combined')):
            with self.subTest(options=options), self.assertRaisesRegex(ValueError, message):
                bench.design(self.args(*production, *options))
        for options in (('--resume',), ('--skip-output-checks', '--require-equal-output')):
            with self.subTest(options=options), patch('sys.stderr', new_callable=io.StringIO), \
                    self.assertRaises(SystemExit) as error:
                self.args(*options)
            self.assertEqual(error.exception.code, 2)

    @patch.object(bench, 'available_cpus', return_value=1)
    def test_affinity_and_softness(self, _):
        self.assertEqual(len(bench.design(self.args())['configurations']), 7)
        self.assertEqual(len(bench.design(self.args('--profile', 'full'))['configurations']), 40)
        d = bench.design(self.args('--patterns', 'hard', 'soft', 'gaussian', '--softness', '.03'))
        for case in d['configurations']:
            self.assertEqual(case['softness'], .03 if case['pattern'] == 'soft' else 0.)

    def test_binary_default_and_explicit_paths(self):
        for platform, suffix in (('win32', '.exe'), ('linux', '')):
            with self.subTest(platform=platform), patch.object(bench.sys, 'platform', platform):
                self.assertEqual(self.args().binary, bench.ROOT / ('bin/bench_speckle_evaluators_f64_simd' + suffix))
                args = self.args('--binary', 'custom native', '--binary-a', 'A.exe', '--binary-b', 'B')
                self.assertEqual((args.binary, args.binary_a, args.binary_b), (Path('custom native'), Path('A.exe'), Path('B')))

    def test_windows_freezes_exact_source_once(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            source = root / 'custom native'
            source.write_bytes(b'exact fixture')
            source.with_suffix('.exe').write_bytes(b'suffixed fixture')
            launched = []

            def run(command, **kwargs):
                launched.append(Path(command[0]))
                return self.transport()(command, **kwargs)

            options = ['--binary', str(source), '--workers', '1', '--scenes', 'plate',
                       '--patterns', 'hard', '--neighbors', '9', '--jitter', '0',
                       '--occupancy', '1', '--repeats', '2']
            with patch.object(bench.sys, 'platform', 'win32'), \
                    patch.object(bench.subprocess, 'run', side_effect=run):
                exact = root / 'exact'
                self.assertEqual(bench.main(['--out', str(exact), *options]), 0)
                frozen = exact / 'binaries/A.exe'
                self.assertEqual(set(launched), {frozen})
                self.assertEqual(frozen.read_bytes(), b'exact fixture')
                self.assertFalse((exact / 'binaries/B.exe').exists())

    def test_windows_missing_explicit_binary_does_not_use_exe_sibling(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(bench.sys, 'platform', 'win32'), \
                patch.object(bench, 'run_logged') as run:
            root = Path(directory).resolve()
            missing = root / 'custom native'
            sibling = missing.with_suffix('.exe')
            sibling.write_bytes(b'suffixed fixture')
            for variant in ('', '-a', '-b'):
                option = '--binary' + variant
                with self.subTest(option=option):
                    out = root / ('out' + variant)
                    out.mkdir()
                    common = ['--binary', str(sibling)] if variant else []
                    args = self.args(*common, option, str(missing))
                    with self.assertRaises(FileNotFoundError) as error:
                        bench.prepare_binaries(out, args, bench.design(args))
                    self.assertEqual(error.exception.filename, str(missing))
            run.assert_not_called()

    def test_raw_perlin_matrix_deduplicates_inactive_controls(self):
        inactive = dict(neighbors=None, radius=None, jitter=None, occupancy=None)
        for profile in ('tuning', 'full'):
            for overrides in ((), ('--jitter', '0', '1.1', '--occupancy', '.7', '1',
                                   '--neighbors', '1', '4', '9', '--radius', '.6')):
                with self.subTest(profile=profile, overrides=overrides):
                    d = bench.design(self.args('--profile', profile, '--patterns', 'perlin',
                                               '--workers', '1', '--perlin-threshold', '.1',
                                               '--perlin-transition', '0', *overrides))
                    self.assertEqual(d['configurations'], [dict(threads=1, scene=scene,
                        pattern='perlin', softness=0., **inactive) for scene in ('plate', 'sphere')])
                    d['variants']['A'] = dict(evaluator='gradient-lattice', catalogue=self.catalogue())
                    config = bench.case_config(d, d['configurations'][0], 'A')
                    command = bench.native_argv('native', config)
                    self.assertTrue({f'--{key}' for key in inactive}.isdisjoint(command[1::2]))
                    argv = self.decode_command(command)
                    self.assertEqual((argv['perlin_threshold'], argv['perlin_transition']), (.1, 0.))
        with self.assertRaisesRegex(ValueError, 'raw jitter must be finite and nonnegative'):
            bench.design(self.args('--jitter', '-.1'))

    def test_raw_perlin_bypasses_dot_factor_expansion_in_mixed_designs(self):
        args = self.args('--profile', 'full', '--workers', '2', '1', '--scenes', 'sphere', 'plate',
                         '--patterns', 'hard', 'perlin', '--jitter', '0', '.08',
                         '--occupancy', '.7', '1', '--neighbors', '4', '9')
        with patch.object(bench, 'product', wraps=product) as expand:
            cases = bench.design(args)['configurations']
        dot_factors = ([0., .08], [.7, 1.], [4, 9])
        self.assertEqual([call.args for call in expand.call_args_list],
                         [([1, 2], ['sphere', 'plate'], ['hard', 'perlin']), *([dot_factors] * 4)])
        expected = []
        for worker, scene in product((1, 2), ('sphere', 'plate')):
            expected.extend(dict(threads=worker, scene=scene, pattern='hard', jitter=jitter,
                                 occupancy=occupancy, neighbors=neighbors, softness=0.)
                            for jitter, occupancy, neighbors in product(*dot_factors))
            expected.append(dict(threads=worker, scene=scene, pattern='perlin', jitter=None,
                                 occupancy=None, neighbors=None, radius=None, softness=0.))
        self.assertEqual(cases, expected)

    def test_raw_perlin_case_file_deduplicates_inactive_controls(self):
        case = dict(threads=1, scene='plate', pattern='perlin', softness=0.,
                    neighbors=None, radius=None, jitter=None, occupancy=None)
        rows = [dict(case, radius=.35, jitter=0., occupancy=.7),
                dict(case, radius=.6, jitter=1.1, occupancy=1.), case, dict(case, scene='sphere')]
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'cases.json'
            path.write_text(json.dumps(rows), encoding='utf-8')
            self.assertEqual(bench.load_cases(path), [case, dict(case, scene='sphere')])
            path.write_text(json.dumps([dict(case, neighbors=9)]), encoding='utf-8')
            with self.assertRaisesRegex(ValueError, 'invalid case neighbors'):
                bench.load_cases(path)

    @patch.object(bench, 'available_cpus', return_value=14)
    def test_explicit_cases(self, _):
        rows = []
        def add(scene, radius, jitter=0, occupancy=1, threads=1):
            rows.append(dict(threads=threads, scene=scene, pattern='gaussian', jitter=jitter,
                             occupancy=occupancy, neighbors=9, softness=0, radius=radius))
        for radius, occupancy in ((.4, 1), (.6, 1), (.6, .7)):
            for jitter in (0, .08):
                add('plate', radius, jitter, occupancy)
        for radius in (.4, .6):
            add('sphere', radius)
        for scene in ('plate', 'sphere'):
            add(scene, .4, threads='available-cpus')
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'cases.json'
            path.write_text(json.dumps(rows), encoding='utf-8')
            for profile in ('tuning', 'full'):
                d = bench.design(self.args('--case-file', str(path), '--profile', profile))
                self.assertEqual(len(d['configurations']), 10)
                self.assertEqual([c['radius'] for c in d['configurations']], [.4, .4, .6, .6, .6, .6, .4, .6, .4, .4])
                self.assertEqual([c['threads'] for c in d['configurations']], [1]*8 + [14]*2)
            with patch.object(bench, 'available_cpus', return_value=1):
                self.assertEqual(len(bench.load_cases(path)), 8)
            with self.assertRaises(ValueError):
                bench.design(self.args('--case-file', str(path), '--patterns', 'gaussian'))
            for bad in ({**rows[0], 'radius': float('nan')}, {**rows[0], 'threads': 0},
                        {**rows[0], 'jitter': -.1}, {**rows[0], 'neighbors': True},
                        {**rows[0], 'neighbors': 9.0}, {**rows[0], 'softness': .01},
                        {**rows[0], 'unexpected': 1}):
                path.write_text(json.dumps([bad]), encoding='utf-8')
                with self.assertRaises(ValueError):
                    bench.load_cases(path)


    def test_case_file_rejects_explicit_radius_and_softness_even_at_defaults(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            cases = root / 'cases.json'
            cases.write_text(json.dumps([dict(threads=1, scene='plate', pattern='gaussian',
                                             radius=.4, jitter=0, occupancy=1, neighbors=9, softness=0)]), encoding='utf-8')
            for option in ('--radius=.35', '--softness=.04'):
                with self.subTest(option=option), self.assertRaisesRegex(ValueError, '--case-file cannot be mixed'):
                    bench.design(self.args('--case-file', str(cases), option))

    def test_complete_explicit_case_passes_and_echoes_radius(self):
        row = dict(threads=1, scene='plate', pattern='gaussian', radius=.6,
                   jitter=.08, occupancy=1, neighbors=9, softness=0)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            case_file, binary = root / 'cases.json', root / 'native'
            case_file.write_text(json.dumps([row]), encoding='utf-8')
            binary.write_bytes(b'frozen fixture')
            calls = []
            def sample(config):
                calls.append(config)
                return self.native(config)
            with patch.object(bench.subprocess, 'run', side_effect=self.transport(sample)):
                self.assertEqual(bench.main(['--out', str(root / 'result'), '--binary', str(binary),
                                            '--case-file', str(case_file), '--repeats', '2',
                                            '--require-equal-output']), 0)
            self.assertEqual(len(calls), 4)
            for config in calls:
                self.assertEqual({k: config[k] for k in row}, row)
            self.assertIn('radius', (root / 'result/comparison.md').read_text(encoding='utf-8'))


    def test_zero_occupancy_respects_native_input_policy(self):
        with self.assertRaisesRegex(ValueError, 'occupancy must be positive'):
            bench.design(self.args('--patterns', 'gaussian', '--occupancy', '0'))
        bench.design(self.args('--patterns', 'perlin', '--occupancy', '0'))
        bench.design(self.args('--a', 'mock', '--b', 'mock', '--occupancy', '0'))
        with tempfile.TemporaryDirectory() as directory:
            cases = Path(directory) / 'cases.json'
            cases.write_text(json.dumps([dict(threads=1, scene='plate', pattern='soft',
                                             radius=.4, jitter=0, occupancy=0,
                                             neighbors=9, softness=.04)]), encoding='utf-8')
            out = Path(directory) / 'not-created'
            with patch.object(bench.subprocess, 'run') as native:
                with self.assertRaises(SystemExit):
                    bench.main(['--out', str(out), '--case-file', str(cases)])
                native.assert_not_called()
            self.assertFalse(out.exists())

    def test_production_policy_comes_from_native_shape_descriptors(self):
        catalogue = self.catalogue()
        catalogue['overrides_enabled'] = False  # Production routing also works in standard builds.
        # Future policy names/neighborhoods must not require a Python policy edit.
        for pattern, softness in (('hard', 0), ('soft', .02), ('gaussian', 0), ('perlin', 0)):
            current = bench.production_config(catalogue, dict(pattern=pattern, softness=softness))
            row = next(row for row in catalogue['production_configs'] if row == current)
            row['evaluator'] = 'future-' + pattern
            row['neighbors'] = None if pattern == 'perlin' else 4
            catalogue['evaluators'].append(row['evaluator'])
            config = dict(mode='full-render', evaluator='auto', pattern=pattern, softness=softness)
            self.assertEqual(bench.generation_config(catalogue, config), row)
            argv = bench.native_argv('native', config)
            self.assertEqual(argv[argv.index('--evaluator') + 1], 'auto')
            with self.assertRaises(ValueError):
                bench.generation_config(catalogue, dict(config, neighbors=4))
        duplicate = deepcopy(catalogue)
        duplicate['production_configs'].append(bench.production_config(duplicate, dict(pattern='hard', softness=0)))
        with self.assertRaisesRegex(ValueError, 'no unique native production'):
            bench.production_config(duplicate, dict(pattern='hard', softness=0))

    def test_native_generation_sampling_mapping_is_generic(self):
        sample = dict(evaluator='shared-sampler', pattern='disk', neighbors=9, soft_edges=False)
        generation = dict(evaluator='new-generation', pattern='disk', neighbors=9, soft_edges=False)
        catalogue = dict(sampling_configs=[sample], configs=[dict(generation, sampling_index=0)],
                         evaluators=['new-generation'], overrides_enabled=True)
        config = dict(evaluator='new-generation', pattern='hard', neighbors=9)
        self.assertEqual(bench.generation_config(catalogue, config), generation)
        with self.assertRaisesRegex(ValueError, 'no unique native generation configuration'):
            bench.generation_config(catalogue, dict(config, neighbors=4))
        routes = bench.catalogue_sampling_routes(catalogue)
        identity = dict(generation_evaluator='new-generation', sampling_evaluator='shared-sampler', sampling_index=0)
        identity['backing'] = 'new-backing'
        bench.validate_sampling_identity(identity, generation, routes)
        for changed in (dict(identity, generation_evaluator='shared-sampler'),
                        dict(identity, sampling_evaluator='new-generation'), dict(identity, sampling_index=1)):
            with self.assertRaises(ValueError):
                bench.validate_sampling_identity(changed, generation, routes)
        for changed in (dict(generation, sampling_index=1),
                        dict(generation, sampling_index=0, sampling=generation)):
            with self.assertRaises(ValueError):
                bench.catalogue_sampling_routes(dict(catalogue, configs=[changed]))
        with self.assertRaisesRegex(ValueError, 'wrong actual sampling evaluator'):
            routes = bench.catalogue_sampling_routes(dict(catalogue, sampling_configs=[generation]))
            bench.validate_sampling_identity(identity, generation, routes)


    def test_prepared_build_and_resource_identity_validation(self):
        config = dict(mode='evaluation', evaluator='list-indexed', pattern='hard', neighbors=9,
                      softness=0, width=32, height=24, frames=2)
        catalogue = self.catalogue()
        spec = dict(catalogue=catalogue, build_identity=catalogue['build_identity'],
                    workload_modes=catalogue['workload_modes'])
        routes, generation = bench.catalogue_sampling_routes(catalogue), bench.generation_config(catalogue, config)
        native = self.native(config)
        bench.validate_identity(native, config, spec, routes, generation)
        features = native['build_identity']['cpu_features'][::-1]
        reordered = dict(native, build_identity=dict(native['build_identity'], cpu_features=features))
        bench.validate_identity(reordered, config, spec, routes, generation)
        self.assertEqual(reordered['build_identity']['cpu_features'], features)
        self.assertNotEqual(features, spec['build_identity']['cpu_features'])
        for key, value in (('precision', 'f32'), ('simd', 'off'), ('workload_mode', 'unexpected-workload'),
                           ('build_identity', dict(catalogue['build_identity'], simd_vector_width=16)),
                           ('build_identity', dict(catalogue['build_identity'], cpu_features=['64bit', 'avx'])),
                           ('build_identity', dict(catalogue['build_identity'], cpu_features=['64bit', 'avx', 2])),
                           ('prepared_identity', None)):
            with self.subTest(key=key), self.assertRaises(ValueError):
                bench.validate_identity(dict(native, **{key: value}), config, spec, routes, generation)
        for key, value in (('sampling_index', True), ('sampling_evaluator', 'cell-hash'),
                           ('generation_evaluator', 'cell-hash'), ('backing', 'none')):
            changed = dict(native, prepared_identity=dict(native['prepared_identity'], **{key: value}))
            with self.subTest(key=key), self.assertRaises(ValueError):
                bench.validate_identity(changed, config, spec, routes, generation)
        for value in (-1, True, 1.5):
            with self.assertRaises(ValueError):
                bench.validate_native(dict(native, resource_bytes=value), bench.expected_native(config))
        bench.validate_native(dict(native, duplicated_disk_records=3, record_capacity=18), bench.expected_native(config))
        with self.assertRaises(ValueError):
            bench.validate_native(dict(native, duplicated_disk_records=19, record_capacity=18), bench.expected_native(config))
        # Backing metadata, not a Python evaluator allowlist, determines stored identity.
        native['prepared_identity'].update(backing='none', generation_evaluator=None)
        bench.validate_identity(native, config, spec, routes, generation)
        for key, value in (('generation_evaluator', config['evaluator']), ('sampling_evaluator', None),
                           ('sampling_index', None), ('backing', None), ('backing', '')):
            with self.subTest(backingless_field=key), self.assertRaises(ValueError):
                bench.validate_identity(dict(native, prepared_identity=dict(native['prepared_identity'], **{key: value})),
                                        config, spec, routes, generation)

        config = dict(mode='full-render', evaluator='texture', width=32, height=24, frames=2)
        native = self.native(config)
        bench.validate_identity(native, config, spec, None, None)
        for key in ('build_identity', 'prepared_identity', 'generation_policy',
                    'resolved_generation', *bench.RESOURCE_FIELDS):
            incomplete = dict(native)
            incomplete.pop(key)
            with self.subTest(missing=key), self.assertRaises(ValueError):
                bench.validate_identity(incomplete, config, spec, None, None)

    def transport(self, sample=None):
        """Happy-path subprocess transport only; expectations and failures stay in each test."""
        def run(command, **kwargs):
            if command[-1] == '--list-evaluators':
                return process_result(stderr=json.dumps(self.catalogue()))
            native = (sample or self.native)(self.decode_command(command))
            return process_result(stdout='BENCH ' + json.dumps(native))
        return run

    def decode_command(self, command):
        config = {k[2:].replace('-', '_'): v for k, v in zip(command[1::2], command[2::2])}
        for key in ('threads', 'width', 'height', 'frames', 'seed', 'neighbors'):
            if key in config:
                config[key] = int(config[key])
        for key in ('coverage', 'jitter', 'occupancy', 'radius', 'softness', 'perlin_threshold',
                    'perlin_transition', 'cell_size', 'cells_u', 'cells_v'):
            if key in config:
                config[key] = float(config[key])
        if config['mode'] == 'evaluation' and config['evaluator'] != 'texture':
            config.setdefault('neighbors', None)
        return config

    def test_two_sweeps_keep_raw_logs_and_reject_partial_analysis(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            binary, out = root / 'native', root / 'result'
            binary.write_bytes(b'fixture')

            options = ['--out', str(out), '--binary', str(binary), '--workers', '2', '--scenes', 'plate', 'sphere',
                       '--patterns', 'hard', '--jitter', '0', '--occupancy', '1', '--neighbors', '9', '--radius', '.425',
                       '--frames', '2', '--repeats', '2', '--require-equal-output']
            with patch.object(bench.subprocess, 'run', side_effect=self.transport()):
                self.assertEqual(bench.main(options), 0)
            samples = read_samples(out)
            self.assertEqual(len(samples), 8)
            self.assertTrue(all(row['native']['threads'] == 2 and row['native']['frames'] == 2 for row in samples))
            self.assertTrue(all(len(row['binary_sha256']) == 64 and row['command'] for row in samples))
            commands = [json.loads(line) for line in (out / 'commands.jsonl').read_text(encoding='utf-8').splitlines()]
            self.assertEqual(len(commands), 9)
            for command in commands:
                for suffix in ('.stdout', '.stderr', '.command.json'):
                    self.assertTrue((out / 'logs' / (command['label'] + suffix)).exists())
            metadata = json.loads((out / 'metadata.json').read_text(encoding='utf-8'))
            self.assertEqual([(r['case_id'], r['sweep'], r['position'], r['variant']) for r in samples],
                             [(i, s, p, v) for s, order in enumerate(('AB', 'BA'))
                              for i in range(2) for p, v in enumerate(order)])
            validator = bench.SampleValidator(metadata)
            validator.add(samples[0])
            for bad, error in ((samples[0], 'duplicate sample position'),
                               (dict(samples[1], position=-1), 'invalid sample position'),
                               (dict(samples[1], variant='A'), 'sample order differs'),
                               (dict(samples[1], sweep=2), 'invalid sample location')):
                with self.subTest(error=error), self.assertRaisesRegex(ValueError, error):
                    validator.add(bad)
            for row in samples[1:-1]:
                validator.add(row)
            with self.assertRaisesRegex(ValueError, 'partial results'):
                validator.finish()
            validator.add(samples[-1])
            groups, outputs = validator.finish()
            self.assertEqual(len(groups), 8)
            self.assertEqual(len(outputs), 4)
            before = {p: p.read_bytes() for p in out.rglob('*') if p.is_file()}
            with patch.object(bench.subprocess, 'run') as native, \
                    patch('sys.stderr', new_callable=io.StringIO) as stderr, self.assertRaises(SystemExit) as error:
                bench.main(options)
            self.assertEqual(error.exception.code, 1)
            self.assertIn('use a fresh output directory; no resume', stderr.getvalue())
            native.assert_not_called()
            self.assertEqual({p: p.read_bytes() for p in out.rglob('*') if p.is_file()}, before)

    def test_concurrent_runners_claim_output_exclusively(self):
        for existing in (False, True):
            with self.subTest(existing=existing), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                out = root / 'out'
                if existing:
                    out.mkdir()
                sources = [root / name for name in ('first', 'second')]
                for source in sources:
                    source.write_bytes(source.name.encode('ascii'))
                claim = out / '.comparison-claim'
                both_saw_empty = Barrier(2, timeout=5)
                open_path = Path.open

                def open_at_claim(path, mode='r', *args, **kwargs):
                    if path == claim:
                        self.assertEqual(mode, 'x')
                        both_saw_empty.wait()
                    return open_path(path, mode, *args, **kwargs)

                def run(source):
                    options = ['--out', str(out), '--binary', str(source), '--workers', '1', '--scenes', 'plate',
                               '--patterns', 'hard', '--jitter', '0', '--occupancy', '1', '--neighbors', '9', '--repeats', '2']
                    try:
                        return bench.main(options)
                    except SystemExit as exc:
                        return exc.code

                with patch.object(Path, 'open', open_at_claim), \
                        patch.object(bench.subprocess, 'run', side_effect=self.transport()) as native, \
                        patch('sys.stderr', new_callable=io.StringIO) as stderr, ThreadPoolExecutor(2) as pool:
                    codes = list(pool.map(run, sources))
                self.assertCountEqual(codes, [0, 1])
                self.assertIn('use a fresh output directory', stderr.getvalue())
                self.assertEqual(native.call_count, 5)
                winner = sources[codes.index(0)]
                metadata = json.loads((out / 'metadata.json').read_text(encoding='utf-8'))
                self.assertEqual(metadata['runner_argv'][3], str(winner))
                for spec in metadata['variants'].values():
                    self.assertEqual(Path(spec['original_path']), winner)
                    self.assertEqual(Path(spec['file']).read_bytes(), winner.read_bytes())
                self.assertEqual(len(read_samples(out)), 4)

    def test_catalogue_preflight(self):
        stale_modes = {'matching-stale-evaluation': 'evaluation', 'matching-stale-full-render': 'full-render'}
        for scenario in ('features-reordered', 'route', 'build', 'features', 'feature-duplicate', 'missing-build',
                         'workload', 'workload-object', 'extra-workload', *stale_modes,
                         'unsupported', 'missing-sampling-configs', 'invalid-default'):
            with self.subTest(scenario=scenario), tempfile.TemporaryDirectory() as directory:
                success = scenario == 'features-reordered'
                root = Path(directory)
                a, b, out = root / 'a', root / 'b', root / 'out'
                a.write_bytes(b'a')
                b.write_bytes(b'b')
                transport = self.transport()

                def run(command, **kwargs):
                    if command[-1] != '--list-evaluators':
                        self.assertTrue(success, 'sampling started before preflight rejected the catalogue')
                        return transport(command, **kwargs)
                    catalogue = self.catalogue()
                    if scenario in stale_modes:
                        catalogue['workload_modes'][stale_modes[scenario]] += '-v1'
                    if Path(command[0]).stem == 'B':
                        if success:
                            catalogue['build_identity']['cpu_features'].reverse()
                        elif scenario == 'route':
                            catalogue['configs'][0]['sampling_index'] = 999
                        elif scenario == 'build':
                            catalogue['build_identity']['simd'] = 'off'
                        elif scenario == 'features':
                            catalogue['build_identity']['cpu_features'] = ['64bit', 'avx']
                        elif scenario == 'feature-duplicate':
                            catalogue['build_identity']['cpu_features'].append('avx2')
                        elif scenario == 'missing-build':
                            catalogue.pop('build_identity')
                        elif scenario == 'workload':
                            catalogue['workload_modes']['evaluation'] = 'different'
                        elif scenario == 'workload-object':
                            catalogue['workload_modes'] = list(catalogue['workload_modes'].values())
                        elif scenario == 'extra-workload':
                            catalogue['workload_modes']['legacy'] = catalogue['workload_modes']['evaluation']
                        elif scenario == 'unsupported':
                            catalogue['configs'] = []
                        elif scenario == 'invalid-default':
                            catalogue['defaults']['perlin_threshold'] = None
                        else:
                            catalogue.pop('sampling_configs')
                    return process_result(stdout=json.dumps(catalogue))
                options = ['--out', str(out), '--binary-a', str(a), '--binary-b', str(b), '--workers', '1',
                           '--scenes', 'plate', '--patterns', 'hard', '--jitter', '0', '--occupancy', '1',
                           '--neighbors', '9', '--repeats', '2']
                with patch.object(bench.subprocess, 'run', side_effect=run) as process:
                    if success:
                        self.assertEqual(bench.main(options), 0)
                        self.assertEqual(len(read_samples(out)), 4)
                    else:
                        with self.assertRaises(SystemExit):
                            bench.main(options)
                        self.assertFalse((out / 'samples.jsonl').exists())
                expected_calls = 1 if scenario in stale_modes else 6 if success else 2
                self.assertEqual(process.call_count, expected_calls)
                self.assertEqual((out / 'comparison.json').exists(), success)

    def test_raw_perlin_freezes_binary_a_defaults_and_validates_the_effective_echo(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            a, b = root / 'a', root / 'b'
            a.write_bytes(b'a')
            b.write_bytes(b'b')
            defaults = {'A': dict(seed=41, perlin_threshold=.2, perlin_transition=.3),
                        'B': dict(seed=42, perlin_threshold=.6, perlin_transition=.7)}

            def run(command, **kwargs):
                variant = Path(command[0]).stem
                if command[-1] == '--list-evaluators':
                    return process_result(stdout=json.dumps(dict(self.catalogue(), defaults=defaults[variant])))
                config = self.decode_command(command)
                self.assertEqual({key: config[key] for key in defaults['A']}, defaults['A'])
                native = self.native(config)
                if variant == 'B':
                    native['resolved_grid']['perlin_coverage_threshold'] = defaults['B']['perlin_threshold']
                return process_result(stdout='BENCH ' + json.dumps(native))

            options = ['--out', str(root / 'out'), '--binary-a', str(a), '--binary-b', str(b),
                       '--a', 'gradient-lattice', '--b', 'cell-hash', '--workers', '1',
                       '--scenes', 'plate', '--patterns', 'perlin', '--jitter', '0',
                       '--occupancy', '1', '--repeats', '2']
            with patch.object(bench.subprocess, 'run', side_effect=run), \
                    patch('sys.stderr', new_callable=io.StringIO) as stderr, self.assertRaises(SystemExit):
                bench.main(options)
            self.assertIn('native config echo mismatch: resolved_grid.perlin_coverage_threshold', stderr.getvalue())
            self.assertEqual([row['variant'] for row in read_samples(root / 'out')], ['A', 'B'])

    def test_f32_echo_validation_uses_exact_selected_precision(self):
        config = dict(mode='evaluation', evaluator='list-indexed', pattern='soft', neighbors=4,
                      width=32, height=24, frames=2, radius=.425, jitter=.03, occupancy=.8,
                      cells_u=8.1, cells_v=4.2, softness=.02, seed=42,
                      perlin_threshold=.13, perlin_transition=.17)
        native = dict(self.native(config), precision='f32')
        grid = native['resolved_grid']
        for key, value in grid.items():
            if type(value) is float:
                grid[key] = bench.native_float(value, 'f32')
            elif isinstance(value, list):
                grid[key] = [bench.native_float(x, 'f32') for x in value]
        expected = bench.expected_native(config)
        self.assertEqual(expected['resolved_grid'], dict(pattern='disk', evaluator='list_indexed', neighbor_count='four',
                         radius_mean=.425, radius_jitter=.03, occupancy=.8, cells_per_uv=[8.1, 4.2], edge_softness=.02,
                         perlin_coverage_threshold=.13, perlin_coverage_transition_width=.17, seed=42))
        bench.validate_native(native, expected)
        # Real Zig JSON uses the promoted f32 value, not its shortest f32 decimal.
        self.assertEqual(grid['radius_mean'], 0.42500001192092896)
        for value in (.425, .426):
            grid['radius_mean'] = value
            with self.subTest(value=value), self.assertRaises(ValueError):
                bench.validate_native(native, expected)

    def test_f32_echo_overflow_exits_cleanly_and_keeps_observation(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            binary, out = root / 'native', root / 'result'
            binary.write_bytes(b'fixture')
            def run(command, **kwargs):
                if command[-1] == '--list-evaluators':
                    catalogue = self.catalogue()
                    catalogue['build_identity']['precision'] = 'f32'
                    return process_result(stdout=json.dumps(catalogue))
                native = self.native(self.decode_command(command))
                native['precision'] = native['build_identity']['precision'] = 'f32'
                native['resolved_grid']['radius_mean'] = bench.native_float(native['resolved_grid']['radius_mean'], 'f32')
                return process_result(stdout='BENCH ' + json.dumps(native))
            validate_native = bench.validate_native

            def validate(native, expected):
                row, = read_samples(out)
                self.assertEqual(row['native'], native)
                validate_native(native, expected)

            with patch.object(bench.subprocess, 'run', side_effect=run), \
                    patch.object(bench, 'validate_native', side_effect=validate), \
                    patch('sys.stderr', new_callable=io.StringIO) as stderr, self.assertRaises(SystemExit) as error:
                bench.main(['--out', str(out), '--binary', str(binary), '--workers', '1',
                            '--scenes', 'plate', '--patterns', 'hard', '--neighbors', '9',
                            '--jitter', '0', '--occupancy', '1', '--repeats', '2',
                            '--perlin-threshold', '1e40'])
            self.assertEqual(error.exception.code, 1)
            self.assertIn('native config echo outside f32 range: resolved_grid.perlin_coverage_threshold', stderr.getvalue())
            self.assertIn(str(out / 'logs/sweep-0-case-0-position-0-A'), stderr.getvalue())
            self.assertNotIn('Traceback', stderr.getvalue())
            self.assertEqual(len(read_samples(out)), 1)
            self.assertFalse((out / 'comparison.json').exists())

    def test_logged_process_retains_exact_streams_and_status(self):
        command = ['café native', 'one two']
        success = process_result(stdout='BENCH {"texture": "C:/café λ/texture.bmp"}\r\n')
        success.stderr = b'non-UTF-8 diagnostic: \xff\r\n'
        failure = SimpleNamespace(returncode=7, stdout=success.stdout, stderr=success.stderr)
        timeout = bench.subprocess.TimeoutExpired(command, 1, output=b'partial stdout', stderr=b'partial UTF-8: \xce')
        with tempfile.TemporaryDirectory() as directory:
            logs = Path(directory) / 'logs'
            for label, result, error, status in (
                    ('success', success, None, {'returncode': 0}),
                    ('failure', failure, (ValueError, r'command failed \(7\); full logs:'), {'returncode': 7}),
                    ('timeout', timeout, (ValueError, 'timed out.*full logs:'), {'timeout_seconds': 1}),
                    ('launch-error', OSError('missing executable'), (OSError, 'missing executable; full logs:'),
                     {'error': 'missing executable'})):
                effect = {'side_effect': result} if isinstance(result, Exception) else {'return_value': result}
                with self.subTest(label=label), patch.object(bench.subprocess, 'run', **effect) as run, \
                        patch('sys.stdout', new_callable=io.StringIO) as stdout, \
                        patch('sys.stderr', new_callable=io.StringIO) as stderr:
                    if error:
                        with self.assertRaisesRegex(*error):
                            bench.run_logged(command, logs.parent, label, 1)
                    else:
                        lines = bench.run_logged(command, logs.parent, label, 1)
                        self.assertEqual(json.loads(lines[0][6:])['texture'], 'C:/café λ/texture.bmp')
                    run.assert_called_once_with(command, capture_output=True, timeout=1, cwd=bench.ROOT)
                    self.assertEqual((stdout.getvalue(), stderr.getvalue()), ('', ''))
                    for stream in ('stdout', 'stderr'):
                        self.assertEqual((logs / f'{label}.{stream}').read_bytes(), getattr(result, stream, b''))
                    record = json.loads((logs / f'{label}.command.json').read_text(encoding='utf-8'))
                    self.assertEqual(record['command'], command)
                    self.assertEqual({k: record[k] for k in status}, status)

    def test_schedules(self):
        self.assertEqual(bench.schedules(6), ['ABBAAB', 'BAABBA'])

    def test_exact_bruteforce_and_holm(self):
        for n in range(1, 5):
            blocks = [(list(range(n)), list(range(n, 2*n))), ([1]*n, [2]*n)]
            distributions = [[2*sum(c)-sum(a+b) for c in combinations(a+b, n)] for a, b in blocks]
            observed = abs(sum(sum(a)-sum(b) for a, b in blocks))
            tail = sum(abs(a+b) >= observed for a, b in product(*distributions))
            result = bench.permutation(blocks)
            self.assertEqual(result['tail'], tail)
            self.assertEqual(result['p'], tail / (len(distributions[0])*len(distributions[1])))
        self.assertEqual(bench.permutation([([1], [1]), ([1], [1])])['p'], 1)
        self.assertEqual(bench.holm([.01, .04, .03]), [.03, .06, .06])

    def test_monte_carlo(self):
        blocks = [(list(range(12)), list(range(12, 24)))] * 2
        result = bench.permutation(blocks, 100, 9)
        self.assertEqual(result, bench.permutation(blocks, 100, 9))
        self.assertEqual(result['method'], 'monte-carlo-plus-one')
        self.assertEqual(result['p'], (result['tail'] + 1) / 101)


    def catalogue(self):
        build = dict(precision='f64', simd='on', simd_vector_width=8, newton_solver='fast',
                     enable_all_evaluators=True, speckle_mask_samples_per_cell=8,
                     optimize='ReleaseFast', strip=True, zig_version='0.17.1', target_arch='x86_64', cpu_model='test',
                     cpu_features=['64bit', 'avx', 'avx2'])
        samples = [dict(evaluator=evaluator, pattern=pattern, neighbors=neighbors, soft_edges=soft)
                   for evaluator in ('cell-hash', 'list-indexed', 'cell-binned')
                   for pattern in ('disk', 'gaussian', 'perlin')
                   for neighbors in ((None,) if pattern == 'perlin' else (1, 4, 9))
                   for soft in ((False, True) if pattern == 'disk' else (None,))]
        samples.extend(dict(evaluator=evaluator, pattern='disk', neighbors=9, soft_edges=False)
                       for evaluator in ('classified-indexed', 'classified-binned'))
        samples.append(dict(evaluator='gradient-lattice', pattern='perlin', neighbors=None, soft_edges=None))
        return dict(evaluators=['gradient-lattice', 'texture', 'cell-hash', 'list-indexed', 'cell-binned',
                                'classified-indexed', 'classified-binned'], overrides_enabled=True,
                    configs=[dict(row, sampling_index=i) for i, row in enumerate(samples)],
                    defaults=dict(seed=123, perlin_threshold=0., perlin_transition=.12),
                    sampling_configs=samples, build_identity=build,
                    production_configs=[row for row in samples if
                        (row['evaluator'], row['pattern'], row['neighbors'], row['soft_edges']) in
                        (('classified-binned', 'disk', 9, False), ('cell-binned', 'disk', 9, True),
                         ('cell-binned', 'gaussian', 9, None), ('gradient-lattice', 'perlin', None, None))],
                    workload_modes=bench.WORKLOAD_MODES.copy())

    def native(self, config):
        evaluation = config['mode'] == 'evaluation'
        catalogue = self.catalogue()
        identity = None
        if evaluation:
            identity = dict(generation_evaluator=None, sampling_evaluator=None, sampling_index=None, backing='none')
            if config['evaluator'] != 'texture':
                generation = bench.generation_config(catalogue, config)
                route = bench.catalogue_sampling_routes(catalogue)[tuple(generation.values())]
                identity.update(generation_evaluator=config['evaluator'], sampling_evaluator=route['sampling']['evaluator'],
                                sampling_index=route['sampling_index'], backing='strip_list')
        native = {key: config[key] for key in ('mode', 'evaluator', 'scene', 'pattern', 'threads', 'width', 'height',
                                               'frames', 'texture', 'texture_filter') if key in config}
        combined_ns = 3
        if evaluation:
            resource_ns = 0 if config['evaluator'] == 'texture' else 1
            native.update(resource_ns=resource_ns, render_ns=2)
            combined_ns = resource_ns + 2
        native.update(combined_ns=combined_ns, checksum=7 if evaluation else None,
                    image_hash=None if evaluation else 'a' * 64,
                    shaded_samples=10 if evaluation else 0, evaluation_counters_available=evaluation,
                    image_samples=0 if evaluation else config['width'] * config['height'] * config['frames'],
                    precision='f64', simd='on', workload_mode=catalogue['workload_modes'][config['mode']],
                    build_identity=catalogue['build_identity'], prepared_identity=identity,
                    **dict.fromkeys(bench.RESOURCE_FIELDS))
        native.update(physical_params=None, resolved_grid=None, resolved_generation=None, generation_policy=None)
        if evaluation and config['evaluator'] != 'texture':
            params = dict(pattern='disk' if config['pattern'] in ('hard', 'soft') else config['pattern'],
                          evaluator=config['evaluator'].replace('-', '_'))
            for public, option in (('radius_mean', 'radius'), ('radius_jitter', 'jitter'), ('occupancy', 'occupancy'),
                                   ('edge_softness', 'softness'), ('perlin_coverage_threshold', 'perlin_threshold'),
                                   ('perlin_coverage_transition_width', 'perlin_transition'), ('seed', 'seed')):
                if option in config:
                    params[public] = config[option]
            if 'neighbors' in config:
                params['neighbor_count'] = {None: None, 1: 'one', 4: 'four', 9: 'nine'}[config['neighbors']]
            if 'cells_u' in config:
                params['cells_per_uv'] = [config['cells_u'], config['cells_v']]
            native.update(resolved_grid=params, resolved_generation=generation)
        if not evaluation and config['evaluator'] != 'texture':
            generation = bench.generation_config(catalogue, config)
            if config['pattern'] == 'perlin':
                params = dict(cell_size=config['cell_size'], threshold=config['perlin_threshold'],
                              transition_width=config['perlin_transition'], seed=config['seed'])
            else:
                params = {k: config[k] for k in ('coverage', 'radius', 'jitter', 'occupancy', 'seed')}
                if config['pattern'] in ('hard', 'soft'):
                    params['edge_softness'] = config['softness']
            native.update(physical_params={generation['pattern']: params}, generation_policy=generation)
        return native

    def test_physical_cases_have_no_grid_compatibility_and_validate_types(self):
        physical = dict(threads=1, scene='plate', pattern='hard', coverage=.5, radius=.25,
                        jitter=.01, occupancy=.7, softness=0)
        perlin = dict(threads=1, scene='sphere', pattern='perlin', cell_size=.25,
                      perlin_threshold=.1, perlin_transition=0)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'cases.json'
            perlin_default = dict(threads=1, scene='plate', pattern='perlin', cell_size=.25)
            rows = [physical, perlin, perlin_default]
            path.write_text(json.dumps([*rows, physical]), encoding='utf-8')
            self.assertEqual(bench.design(self.args('--profile', 'full-render', '--case-file', str(path)))['configurations'],
                             rows)
            for changed in (dict(physical, neighbors=9), dict(physical, coverage=True), dict(physical, radius=None),
                            dict(physical, jitter=.3), dict(physical, occupancy=0), dict(perlin, radius=.25),
                            dict(perlin, cell_size=False), dict(perlin, perlin_transition=-1)):
                path.write_text(json.dumps([changed]), encoding='utf-8')
                with self.subTest(changed=changed), self.assertRaises(ValueError):
                    bench.load_cases(path, production=True)
        for flags in ([], ['--coverage', '.5'], ['--radius', '.25'], ['--coverage', '.5', '--radius', '.25', '--cells-plate', '8', '4'],
                      ['--patterns', 'perlin', '--radius', '.25'], ['--coverage', '.5', '--radius', '.25', '--softness', '.01']):
            with self.subTest(flags=flags), self.assertRaises(ValueError):
                bench.design(self.args('--profile', 'full-render', *flags))
        with self.assertRaisesRegex(ValueError, 'cell_size'):
            bench.design(self.args('--profile', 'full-render', '--patterns', 'perlin'))
        bench.design(self.args('--profile', 'full-render', '--patterns', 'perlin', '--cell-size', '.25'))
        bench.design(self.args('--profile', 'full-render', '--coverage', '.5', '--radius', '.25', '--softness', '0'))

    def test_physical_jitter_boundary_rejects_before_freezing_but_raw_remains_valid(self):
        case = dict(threads=1, scene='plate', pattern='hard', coverage=.5, radius=.25,
                    jitter=.125, occupancy=1., softness=0.)
        flags = ['--profile', 'full-render', '--workers', '1', '--scenes', 'plate', '--patterns', 'hard',
                 *full_render_flags(), '--jitter']
        self.assertEqual(bench.design(self.args(*flags, '.125'))['configurations'], [case])
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path = root / 'cases.json'
            path.write_text(json.dumps([case]), encoding='utf-8')
            self.assertEqual(bench.load_cases(path, production=True), [case])
            above = math.nextafter(case['jitter'], math.inf)
            path.write_text(json.dumps([dict(case, jitter=above)]), encoding='utf-8')
            for options in (flags + [repr(above)], ['--profile', 'full-render', '--case-file', str(path)]):
                out = root / 'not-created'
                with self.subTest(options=options), patch.object(bench, 'freeze') as freeze, \
                        patch.object(bench.subprocess, 'run') as native, patch('sys.stderr', new_callable=io.StringIO):
                    with self.assertRaises(SystemExit):
                        bench.main(['--out', str(out), *options])
                    freeze.assert_not_called()
                    native.assert_not_called()
                self.assertFalse(out.exists())
            raw = {key: value for key, value in case.items() if key != 'coverage'}
            raw.update(jitter=.75 * case['radius'], neighbors=9)
            path.write_text(json.dumps([raw]), encoding='utf-8')
            self.assertEqual(bench.load_cases(path), [raw])
            self.assertEqual(bench.design(self.args('--case-file', str(path)))['configurations'], [raw])

    def test_texture_argv_omits_all_procedural_controls_without_changing_case(self):
        for profile in ('full', 'full-render'):
            args = self.args('--profile', profile, '--a', 'texture', '--texture', 'café texture.bmp',
                             '--scenes', 'plate', '--patterns', 'soft', '--workers', '1',
                             '--jitter', '0', '--occupancy', '1',
                             *(['--coverage', '.5', '--radius', '.25', '--softness', '.02']
                               if profile == 'full-render' else ['--neighbors', '9']))
            metadata = bench.design(args)
            metadata['config']['texture'] = str(args.texture)
            metadata['variants']['A'] = dict(evaluator='texture')
            case, = metadata['configurations']
            before = dict(case)
            config = bench.case_config(metadata, case, 'A')
            command = bench.native_argv('native', config)
            self.assertEqual(self.decode_command(command), dict(
                mode=metadata['mode'], evaluator='texture', scene='plate', pattern='soft', threads=1,
                width=3840, height=2160, frames=16, texture='café texture.bmp',
                texture_filter='cubic_catmull_rom'))
            self.assertEqual(case, before)

    def test_texture_only_case_file_needs_no_procedural_controls(self):
        with tempfile.TemporaryDirectory() as directory:
            cases = Path(directory) / 'cases.json'
            row = dict(threads=1, scene='plate', pattern='soft')
            cases.write_text(json.dumps([row]), encoding='utf-8')
            for profile in ('full', 'full-render'):
                flags = ('--profile', profile, '--a', 'texture', '--b', 'texture', '--texture', 'image.bmp')
                metadata = bench.design(self.args(*flags, '--case-file', str(cases)))
                self.assertEqual(metadata['configurations'], [row])

                with self.assertRaisesRegex(ValueError, 'does not accept procedural controls'):
                    bench.design(self.args(*flags, '--radius', '.25'))

    def test_raw_texture_pair_metrics_and_frozen_binaries(self):
        for profile, requested, metrics, failure in (
                ('tuning', (), {'render_ns'}, None),
                ('full', (), {'render_ns'}, None),
                ('full', ('combined',), {'combined_ns'}, None),
                ('full', ('render',), {'render_ns'}, None),
                ('full', ('combined', 'render'), None, 'combined and render are identical'),
                ('full', ('setup',), None, 'setup is not measured'),
                ('full', ('setup', 'render'), None, 'setup is not measured')):
            with self.subTest(profile=profile, requested=requested), \
                    tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                a, b, texture = (root / name for name in ('a', 'b', 'image.bmp'))
                for source in (a, b, texture):
                    source.write_bytes(source.name.encode('ascii'))
                out = root / 'nested' / 'result'
                if requested == ('setup', 'render'):
                    out.mkdir(parents=True)  # An existing empty output directory stays empty too.
                sources = {'A': a, 'B': b}

                catalogued = {}

                def run(command, **kwargs):
                    binary = Path(command[0])
                    variant = binary.stem
                    if command[-1] == '--list-evaluators':
                        self.assertNotIn(binary, sources.values())
                        catalogued[variant] = binary.read_bytes()
                        sources[variant].write_bytes(b'rebuilt after catalogue')
                        return process_result(stdout=json.dumps(self.catalogue()))
                    self.assertEqual(binary.parent, out / 'binaries')
                    self.assertEqual(binary.read_bytes(), catalogued[variant])
                    return process_result(stdout='BENCH ' + json.dumps(self.native(self.decode_command(command))))

                options = ['--out', str(out), '--profile', profile, '--binary-a', str(a), '--binary-b', str(b),
                           '--a', 'texture', '--b', 'texture', '--texture', str(texture), '--workers', '1',
                           '--scenes', 'plate', '--repeats', '2']
                if requested:
                    options += ['--metrics', *requested]
                with patch.object(bench.subprocess, 'run', side_effect=run) as process:
                    if failure:
                        with patch('sys.stderr', new_callable=io.StringIO) as stderr, self.assertRaises(SystemExit) as error:
                            bench.main(options)
                        self.assertEqual(error.exception.code, 1)
                        self.assertIn(failure, stderr.getvalue())
                        if requested == ('setup', 'render'):
                            self.assertEqual(list(out.iterdir()), [])
                        else:
                            self.assertFalse(out.parent.exists())
                        process.assert_not_called()
                        continue
                    self.assertEqual(bench.main(options), 0)
                self.assertEqual(process.call_count, 6)
                metadata = json.loads((out / 'metadata.json').read_text(encoding='utf-8'))
                self.assertEqual(set(metadata['metrics']), metrics)
                comparison = json.loads((out / 'comparison.json').read_text(encoding='utf-8'))
                self.assertEqual({record['metric'] for record in comparison if 'p' in record}, metrics)
                for sample in read_samples(out):
                    self.assertEqual(sample['binary_sha256'], hashlib.sha256(catalogued[sample['variant']]).hexdigest())

    def test_failed_catalogue_preserves_logs_and_frozen_paths_in_partial_metadata(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            a, b, out = (root / name for name in ('a', 'b', 'out'))
            a.write_bytes(b'original a')
            b.write_bytes(b'original b')

            def run(command, **kwargs):
                self.assertEqual(command[1:], ['--list-evaluators'])
                if Path(command[0]).stem == 'A':
                    return process_result(stdout=json.dumps(self.catalogue()))
                result = process_result(stderr='failed to catalogue B')
                result.returncode = 1
                return result

            options = ['--out', str(out), '--binary-a', str(a), '--binary-b', str(b),
                       '--a', 'texture', '--b', 'texture', '--texture', 'unused.bmp']
            with patch.object(bench.subprocess, 'run', side_effect=run), \
                    patch('sys.stderr', new_callable=io.StringIO) as stderr, self.assertRaises(SystemExit):
                bench.main(options)
            self.assertIn(f'full logs: {out / "logs/catalogue-B"}', stderr.getvalue())
            self.assertEqual((out / 'logs/catalogue-B.stderr').read_text(encoding='utf-8'), 'failed to catalogue B')
            self.assertFalse((out / 'samples.jsonl').exists())
            variants = json.loads((out / 'metadata.json').read_text(encoding='utf-8'))['variants']
            self.assertIn('catalogue', variants['A'])
            self.assertNotIn('catalogue', variants['B'])
            for variant, original in (('A', a), ('B', b)):
                frozen = bench.native_exe(out / 'binaries' / variant)
                self.assertEqual(Path(variants[variant]['file']), frozen)
                self.assertEqual(frozen.read_bytes(), original.read_bytes())

    def test_raw_texture_resource_time_is_checked_in_mixed_comparisons(self):
        for resource_ns in (0, 1):
            with self.subTest(resource_ns=resource_ns), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                binary, texture, out = (root / name for name in ('native', 'image.bmp', 'out'))
                binary.write_bytes(b'native')
                texture.write_bytes(b'texture')

                def run(command, **kwargs):
                    if command[-1] == '--list-evaluators':
                        return process_result(stdout=json.dumps(self.catalogue()))
                    native = self.native(self.decode_command(command))
                    if native['evaluator'] == 'texture':
                        native.update(resource_ns=resource_ns, combined_ns=native['render_ns'] + resource_ns)
                    return process_result(stdout='BENCH ' + json.dumps(native))

                options = ['--out', str(out), '--binary', str(binary), '--a', 'texture', '--b', 'list-indexed',
                           '--texture', str(texture), '--workers', '1', '--scenes', 'plate', '--patterns', 'hard',
                           '--jitter', '0', '--occupancy', '1', '--neighbors', '4', '--metrics', 'render', '--repeats', '2']
                with patch.object(bench.subprocess, 'run', side_effect=run):
                    if resource_ns == 0:
                        self.assertEqual(bench.main(options), 0)
                        self.assertEqual(len(read_samples(out)), 4)
                    else:
                        with patch('sys.stderr', new_callable=io.StringIO) as stderr, self.assertRaises(SystemExit):
                            bench.main(options)
                        self.assertIn('requires resource_ns == 0', stderr.getvalue())
                        row, = read_samples(out)
                        self.assertEqual(row['native']['resource_ns'], resource_ns)
                        self.assertFalse((out / 'comparison.json').exists())

    def test_physical_canonical_requests_include_all_controls(self):
        common = dict(mode='full-render', evaluator='auto', width=32, height=24, frames=1)
        # Handwritten expectations must not use the fake producer or the request normalizer.
        for pattern, tag, softness in (('soft', 'disk', .02), ('gaussian', 'gaussian', 0.)):
            config = dict(common, pattern=pattern, coverage=.4, radius=.3, jitter=.01, occupancy=.7, softness=softness, seed=42)
            params = dict(coverage=.4, radius=.3, jitter=.01, occupancy=.7, seed=42)
            if tag == 'disk':
                params['edge_softness'] = softness
            expected = dict(common, pattern=pattern, resolved_grid=None, physical_params={tag: params})
            self.assertEqual(bench.expected_native(config), expected)
        common.update(pattern='perlin')
        config = dict(common, cell_size=.25, perlin_threshold=.1, perlin_transition=.19, seed=43)
        expected = dict(common, resolved_grid=None, physical_params=dict(perlin=
            dict(cell_size=.25, threshold=.1, transition_width=.19, seed=43)))
        self.assertEqual(bench.expected_native(config), expected)

    def test_nested_echo_comparison_branches(self):
        expected = dict(value=.1, count=42, enabled=True, cells=[1.5, 2.25], absent=None)
        actual = dict(expected, value=.10000000149011612)
        bench.validate_echo({'disk': actual}, {'disk': expected}, 'f32', 'physical_params.')
        bench.validate_echo({'disk': expected}, {'disk': expected}, 'f64', 'physical_params.')
        for key, value in (('value', .1), ('value', '0.1'), ('count', 43), ('count', 42.),
                           ('enabled', False), ('enabled', 1), ('cells', [1.5]), ('cells', (1.5, 2.25)),
                           ('cells', [1.5, 2.5]), ('absent', 0)):
            with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                bench.validate_echo({'disk': dict(actual, **{key: value})}, {'disk': expected}, 'f32', 'physical_params.')
        missing = dict(actual)
        missing.pop('count')
        for wrong in ({'disk': missing}, {'disk': None}, [], {'disk': actual, 'gaussian': actual}):
            with self.subTest(wrong=wrong), self.assertRaises(ValueError):
                bench.validate_echo(wrong, {'disk': expected}, 'f32', 'physical_params.')

    def test_native_contract(self):
        for mode in ('evaluation', 'full-render'):
            config = dict(mode=mode, evaluator='texture', width=32, height=24, frames=2,
                          texture='/custom.bmp', texture_filter='cubic_catmull_rom')
            native = self.native(config)
            expected = bench.expected_native(config)
            bench.validate_native(native, expected)
            bad = [('mode', 'unexpected-mode'), ('texture', '/wrong.bmp'), ('texture_filter', 'linear'),
                   ('physical_params', {}), ('resolved_grid', {}), ('checksum', -1),
                   ('evaluation_counters_available', mode != 'evaluation'), ('image_samples', 1),
                   ('shaded_samples', 0 if mode == 'evaluation' else 10), ('image_hash', 'not-a-digest')]
            bad += [('combined_ns', 9), ('render_ns', float('nan'))] if mode == 'evaluation' else [('resource_ns', None)]
            for key, value in bad:
                with self.assertRaises(ValueError, msg=key):
                    bench.validate_native({**native, key: value}, expected)

    def test_complete_run_and_failure(self):
        for profile, failure in (('tuning', None), ('full', None), ('full-render', None),
                                 ('tuning', 'repeat'), ('tuning', 'equal'), ('tuning', 'record'), ('tuning', 'duplicate-record'), ('tuning', 'json'), ('tuning', 'object'),
                                 ('full-render', 'equal'), ('full-render', 'skip'), ('full-render', 'vary')):
            with self.subTest(profile=profile, failure=failure), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                binary, other, texture = root / 'native', root / 'other', root / 'asset.bmp'
                binary.write_bytes(b'original A')
                other.write_bytes(b'original B')
                texture.write_bytes(b'original texture')
                out, calls = root / 'comparison', []

                def run(command, **kwargs):
                    if command[-1] == '--list-evaluators':
                        return process_result(stdout=json.dumps(self.catalogue()))
                    config = self.decode_command(command)
                    calls.append(config['evaluator'])
                    self.assertEqual(Path(command[0]).read_bytes(), b'original A' if config['evaluator'] == 'texture' else b'original B')
                    self.assertEqual(Path(config['texture']).read_bytes(), b'original texture')
                    self.assertEqual(config['texture_filter'], 'cubic_catmull_rom')
                    binary.write_bytes(b'rebuilt A')
                    other.write_bytes(b'rebuilt B')
                    texture.write_bytes(b'changed texture')
                    native = self.native(config)
                    value = 1 if config['evaluator'] == 'texture' else 2
                    if failure in ('skip', 'vary'):
                        value = len(calls)
                    if failure == 'repeat' and len(calls) == 4:
                        value = 9
                    if profile == 'full-render':
                        native['image_hash'] = f'{value:064x}'
                    else:
                        native['checksum'] = value
                    text = '' if failure == 'record' and len(calls) == 2 else 'BENCH ' + json.dumps(native)
                    if failure == 'duplicate-record' and len(calls) == 2:
                        text += '\n' + text
                    if failure == 'json' and len(calls) == 2:
                        text = 'BENCH invalid json'
                    if failure == 'object' and len(calls) == 2:
                        text = 'BENCH []'
                    return process_result(stdout=text)

                options = ['--out', str(out), '--profile', profile, '--binary', str(binary), '--binary-b', str(other),
                           '--a', 'texture', '--b', 'auto' if profile == 'full-render' else 'list-indexed', '--texture', str(texture), '--workers', '1', '--scenes', 'plate',
                           '--patterns', 'soft', '--jitter', '.08', '--occupancy', '.7',
                           '--width', '32', '--height', '24', '--frames', '2', '--repeats', '2']
                options += ['--coverage', '.5', '--radius', '.5', '--softness', '.04'] if profile == 'full-render' else ['--neighbors', '4']
                if failure == 'equal':
                    options.append('--require-equal-output')
                if failure == 'skip':
                    options.append('--skip-output-checks')
                with patch.object(bench.subprocess, 'run', side_effect=run):
                    if failure and failure != 'skip':
                        with self.assertRaises(SystemExit):
                            bench.main(options)
                        self.assertFalse((out / 'comparison.json').exists())
                        self.assertFalse((out / 'comparison.md').exists())
                    else:
                        self.assertEqual(bench.main(options), 0)
                        evaluator = 'auto' if profile == 'full-render' else 'list-indexed'
                        self.assertEqual(calls, ['texture', evaluator, evaluator, 'texture'])
                        records = json.loads((out / 'comparison.json').read_text(encoding='utf-8'))
                        self.assertEqual(sum('p' in r for r in records), 2 if profile == 'full' else 1)
                        self.assertTrue(all(not r['output_equal'] for r in records))
                        metadata = json.loads((out / 'metadata.json').read_text(encoding='utf-8'))
                        self.assertEqual(metadata['runner_sha256'], hashlib.sha256(Path(bench.__file__).read_bytes()).hexdigest())
                        self.assertEqual(len(metadata['variants']['A']['sha256']), 64)
                        self.assertEqual(metadata['skip_output_checks'], failure == 'skip')
                        self.assertEqual(set(metadata['resource_metric_semantics']), set(bench.RESOURCE_FIELDS))
                        self.assertIn('cubic_catmull_rom', (out / 'comparison.md').read_text(encoding='utf-8'))
                        if failure == 'skip':
                            samples = read_samples(out)
                            for variant in 'AB':
                                self.assertEqual(len({r['native']['image_hash'] for r in samples if r['variant'] == variant}), 2)
                            self.assertIn('no image consistency guarantee', (out / 'comparison.md').read_text(encoding='utf-8'))
                self.assertTrue((out / 'samples.jsonl').read_text(encoding='utf-8'))


class NativeBenchmarkTests(unittest.TestCase):
    def setUp(self):
        binary = os.environ.get('RILEY_SPECKLE_BENCH_BINARY')
        if not binary:
            self.skipTest('set RILEY_SPECKLE_BENCH_BINARY to a stripped ReleaseFast all-evaluator native build')
        self.binary = Path(binary).resolve()
        self.assertTrue(self.binary.is_file(), f'native binary does not exist: {self.binary}')
        self.out = Path(self.enterContext(artifact_directory()))
        print(f'Native smoke artifacts: {self.out}', flush=True)

    def test_real_public_controls_change_render_and_reject_metadata_mutations(self):
        binary, out = self.binary, self.out
        catalogue_lines = bench.run_logged([str(binary), '--list-evaluators'], out, 'catalogue', 120)
        catalogue = json.loads(next(line for line in catalogue_lines if line.startswith(b'{')))
        routes = bench.catalogue_sampling_routes(catalogue)
        spec = dict(catalogue=catalogue, build_identity=catalogue['build_identity'], workload_modes=catalogue['workload_modes'])
        # Keep the direct-binary controls test independent of runner collection,
        # but share its catalogue-derived generation and argv construction.
        def sample(config, label):
            command = bench.native_argv(binary, config)
            lines = bench.run_logged(command, out, label, 120)
            records = [json.loads(line[6:]) for line in lines if line.startswith(b'BENCH ')]
            self.assertEqual(len(records), 1)
            native = records[0]
            generation = bench.generation_config(catalogue, config)
            bench.validate_native(native, bench.expected_native(config))
            bench.validate_identity(native, config, spec, routes, generation)
            return native, generation
        for pattern in ('hard', 'soft', 'gaussian', 'perlin'):
            config = dict(mode='full-render', evaluator='auto',
                          pattern=pattern, threads=1, scene='plate', width=96, height=64, frames=1, seed=42)
            config.update(dict(cell_size=.25, perlin_threshold=.1, perlin_transition=.19)
                          if pattern == 'perlin' else dict(coverage=.4, radius=.3, jitter=.01, occupancy=.7,
                                                          softness=.02 if pattern == 'soft' else 0.))
            native, generation = sample(config, pattern)
            if pattern != 'hard':  # One actual-control mutation per disk/Gaussian/Perlin schema.
                wrong = deepcopy(native)
                wrong['physical_params'][generation['pattern']]['seed'] = 43
                with self.subTest(pattern=pattern), self.assertRaises(ValueError):
                    bench.validate_native(wrong, bench.expected_native(config))
            changes = (dict(cell_size=.16, perlin_threshold=.4, perlin_transition=.3)
                       if pattern == 'perlin' else dict(coverage=.3, radius=.35, jitter=.1, occupancy=1.))
            if pattern == 'soft':
                changes['softness'] = .08
            for key, value in dict(changes, seed=43).items():
                requested = dict(config, **{key: value})
                changed, _ = sample(requested, pattern + '-' + key)
                self.assertNotEqual(native['image_hash'], changed['image_hash'], f'ignored public control: {pattern}/{key}')

        # Texture has no physical request: neither mode requires coverage/radius.
        for mode, filtering in (('evaluation', 'cubic_catmull_rom'), ('full-render', 'nearest'),
                                ('full-render', 'linear'), ('full-render', 'cubic_catmull_rom')):
            config = dict(mode=mode, evaluator='texture', threads=1, scene='plate', pattern='hard',
                          width=32, height=24, frames=1, texture='texture/speck128_mono_u8.bmp', texture_filter=filtering)
            native, _ = sample(config, mode + '-texture-' + filtering)
            self.assertIsNone(native['physical_params'])
            self.assertIsNone(native['resolved_grid'])
            if mode == 'evaluation':
                self.assertEqual(native['resource_ns'], 0)
                self.assertEqual(native['combined_ns'], native['render_ns'])

        # Requested mock controls must survive the wildcard generation/sampling route.
        config = dict(mode='evaluation', evaluator='mock', pattern='soft', neighbors=4,
                      width=32, height=24, frames=1, threads=1, scene='plate', seed=42,
                      radius=.425, jitter=.03, occupancy=.8, softness=.02, cells_u=8.1, cells_v=4.2,
                      perlin_threshold=.13, perlin_transition=.17)
        native, generation = sample(config, 'raw-requested-neighbors')
        self.assertEqual(native['resolved_grid']['neighbor_count'], 'four')
        self.assertIsNone(generation['neighbors'])
        wrong = dict(native, resolved_grid=dict(native['resolved_grid'], neighbor_count=None))
        with self.assertRaises(ValueError):
            bench.validate_native(wrong, bench.expected_native(config))

        # Execute the supplied binary, not the Python preflight, for each claim.
        for flags, error in ((['--evaluator', 'cell-hash'], 'FullRenderRequiresProductionDefaults'),
                             (['--evaluator', 'classified-binned'], 'FullRenderRequiresProductionDefaults'),
                             (['--neighbors', '9'], 'FullRenderRequiresProductionDefaults'),
                             (['--evaluator', 'texture'], 'TextureControlsNotApplicable')):
            label = 'reject-' + '-'.join(flags).replace('--', '')
            command = [str(binary), '--mode', 'full-render', '--pattern', 'hard',
                       '--width', '32', '--height', '24', '--frames', '1', *full_render_flags(), *flags]
            with self.subTest(flags=flags), self.assertRaisesRegex(ValueError, 'command failed'):
                bench.run_logged(command, out, label, 120)
            stderr = (out / 'logs' / (label + '.stderr')).read_text(encoding='utf-8')
            self.assertIn(error, stderr)
            self.assertNotIn('BENCH ', stderr)

    def test_full_render_hash_distinguishes_old_repeated_frame_collision(self):
        # A wrapping sum of f64 samples collided for these two fields at 16 frames.
        hashes = {}
        for seed in (13, 18, 13):
            command = [str(self.binary), '--mode', 'full-render', '--evaluator', 'auto',
                       '--pattern', 'hard', '--scene', 'plate', '--threads', '1',
                       '--width', '96', '--height', '64', '--frames', '16',
                       '--radius', '.3', '--coverage', '.4', '--seed', str(seed)]
            lines = bench.run_logged(command, self.out, f'hash-{seed}-{len(hashes)}', 120)
            native = json.loads(next(line[6:] for line in lines if line.startswith(b'BENCH ')))
            self.assertEqual(native['image_samples'], 96 * 64 * 16)
            self.assertRegex(native['image_hash'], '^[0-9a-f]{64}$')
            if seed in hashes:
                self.assertEqual(native['image_hash'], hashes[seed])
            hashes[seed] = native['image_hash']
        self.assertNotEqual(hashes[13], hashes[18])

    def test_texture_only_native_comparisons_launch_frozen_executable(self):
        for profile in ('full', 'full-render'):
            out = self.out / profile
            options = ['--out', str(out), '--binary', str(self.binary), '--profile', profile,
                       '--a', 'texture', '--b', 'texture', '--texture', 'texture/speck128_mono_u8.bmp',
                       '--scenes', 'plate', '--patterns', 'soft', '--width', '32', '--height', '24',
                       '--frames', '1', '--workers', '1', '--repeats', '2', '--require-equal-output']
            self.assertEqual(bench.main(options), 0)
            for row in read_samples(out):
                self.assertEqual(Path(row['command'][0]), bench.native_exe(out / 'binaries/A').resolve())
                self.assertEqual(row['native']['pattern'], 'soft')
                self.assertIsNone(row['native']['physical_params'])
                self.assertIsNone(row['native']['resolved_grid'])

    def test_raw_kernel_equality_and_production_repeatability_protocol(self):
        # One raw priority case; production covers each public tag, not a scene/worker matrix.
        for profile, patterns, a, b, flags in (
                ('full', ['hard'], 'cell-binned', 'classified-binned', ['--neighbors', '9', '--cells-plate', '8', '4']),
                ('full-render', ['hard', 'soft', 'gaussian', 'perlin'], 'auto', 'auto',
                 ['--coverage', '.5', '--softness', '.02', '--cell-size', '.25'])):
            out = self.out / profile
            metric = 'render' if profile == 'full' else 'combined'
            self.assertEqual(bench.main([
                '--out', str(out), '--binary', str(self.binary), '--profile', profile, '--a', a, '--b', b,
                '--workers', '1', '--scenes', 'plate', '--patterns', *patterns,
                '--jitter', '0', '--occupancy', '1', '--radius', '.425',
                '--width', '32', '--height', '24', '--frames', '2',
                '--repeats', '2', '--metrics', metric, '--require-equal-output', *flags]), 0)
            metadata = json.loads((out / 'metadata.json').read_text(encoding='utf-8'))
            catalogue = metadata['variants']['B']['catalogue']
            rows = read_samples(out)
            self.assertEqual(len(rows), 4 * len(patterns))
            self.assertEqual({row['native']['pattern'] for row in rows}, set(patterns))
            for row in rows:
                native = row['native']
                mode = 'evaluation' if profile == 'full' else 'full-render'
                self.assertEqual(native['workload_mode'], bench.WORKLOAD_MODES[mode])
                if profile == 'full' and row['variant'] == 'B':
                    identity = native['prepared_identity']
                    generation = dict(evaluator='classified-binned', pattern='disk', neighbors=9, soft_edges=False)
                    route = bench.catalogue_sampling_routes(catalogue)[tuple(generation.values())]
                    self.assertEqual(identity, dict(generation_evaluator='classified-binned', sampling_evaluator='classified-binned',
                                                   sampling_index=route['sampling_index'], backing='classified_binned'))
                    self.assertGreater(native['resource_bytes'], 0)
                    self.assertGreater(native['duplicated_disk_records'], 0)
                    self.assertLessEqual(native['duplicated_disk_records'], native['record_capacity'])
                if profile == 'full-render':
                    self.assertIsNone(native['prepared_identity'])
                    self.assertIsNotNone(native['physical_params'])
                    self.assertIsNone(native['resolved_grid'])
                    self.assertIsNone(native['resolved_generation'])
                    self.assertEqual(native['generation_policy'], bench.production_config(
                        catalogue, metadata['configurations'][row['case_id']]))
                    self.assertTrue(all(native[field] is None for field in bench.RESOURCE_FIELDS))
            if profile == 'full':
                identities = {row['variant']: row['native']['prepared_identity'] for row in rows}
                self.assertEqual(identities['A']['sampling_evaluator'], 'cell-binned')
                self.assertEqual(identities['B']['sampling_evaluator'], 'classified-binned')
                self.assertNotEqual(identities['A']['sampling_index'], identities['B']['sampling_index'])
            reports = json.loads((out / 'comparison.json').read_text(encoding='utf-8'))
            self.assertEqual(len(reports), (3 if profile == 'full' else 1) * len(patterns))
            self.assertTrue(all(row['output_equal'] for row in reports))
            primary = [row for row in reports if 'p' in row]
            self.assertEqual(len(primary), len(patterns))
            self.assertTrue(all(row['metric'] == metric + '_ns' for row in primary))
            claim = 'raw cross-kernel equality' if profile == 'full' else 'production repeatability/protocol only'
            print(f'Native smoke passed: {claim}, {len(rows)} real observations', flush=True)

        # Catalogue availability, unlike sampling fidelity, still checks every selected configuration.
        for profile in ('tuning', 'full', 'full-render'):
            defaults = bench.parser().parse_args(['--out', 'unused', '--profile', profile, '--workers', '1',
                *(full_render_flags() if profile == 'full-render' else [])])
            matrix = bench.design(defaults)
            matrix['variants'] = {'A': dict(evaluator=defaults.a, catalogue=catalogue), 'B': dict(evaluator=defaults.b, catalogue=catalogue)}
            for case in matrix['configurations']:
                for variant in 'AB':
                    bench.generation_config(catalogue, bench.case_config(matrix, case, variant))


if __name__ == '__main__':
    unittest.main()
