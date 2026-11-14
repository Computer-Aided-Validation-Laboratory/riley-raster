#!/usr/bin/env python3
"""Statistics/runner units plus opt-in, unmocked native catalogue and record smoke.

Build install-bench-speckle-evaluators in ReleaseFast with strip=true and
enable-all-evaluators=true, then set RILEY_SPECKLE_BENCH_BINARY to its executable
and run: python3 -m unittest scripts.tests.test_bench_speckle.NativeBenchmarkTests
"""
from itertools import combinations, product
import json
import hashlib
import io
import os

from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from scripts import bench_speckle as bench


def read_samples(out):
    return [json.loads(line) for line in (out / 'samples.jsonl').read_text().splitlines()]


class BenchmarkTests(unittest.TestCase):
    def args(self, *options):
        return bench.parser().parse_args(['--out', 'unused', *options])

    @patch.object(bench, 'available_cpus', return_value=14)
    def test_profiles_and_overrides(self, _):
        for profile, count, repeats, metrics, alpha in (
                ('tuning', 14, 12, ['combined_ns'], .05),
                ('full', 80, 16, ['resource_ns', 'render_ns'], .10),
                ('full-render', 80, 16, ['resource_ns', 'render_ns'], .10)):
            d = bench.design(self.args('--profile', profile))
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
        for options in (('--repeats', '3'), ('--alpha', 'nan'), ('--frames', '0'), ('--occupancy', '2'),
                        ('--radius', 'inf'), ('--permutations', '0'), ('--softness', '0'), ('--a', 'texture'),
                        ('--perlin-threshold', 'nan'), ('--perlin-transition', '-.1'),
                        ('--workers', 'two'), ('--workers', '0')):
            with self.assertRaises(ValueError):
                bench.design(self.args(*options))

    @patch.object(bench, 'available_cpus', return_value=1)
    def test_affinity_and_softness(self, _):
        self.assertEqual(len(bench.design(self.args())['configurations']), 7)
        self.assertEqual(len(bench.design(self.args('--profile', 'full'))['configurations']), 40)
        d = bench.design(self.args('--patterns', 'hard', 'soft', 'gaussian', '--softness', '.03'))
        for case in d['configurations']:
            self.assertEqual(case['softness'], .03 if case['pattern'] == 'soft' else 0.)
        self.assertEqual(self.args().binary, bench.ROOT / 'zig-out/bin/bench_speckle_evaluators_f64_simd')

    def test_default_pair_supports_all_profile_cases(self):
        args = self.args()
        self.assertEqual((args.a, args.b), ('cell-binned', 'list-indexed'))
        catalogue = self.catalogue()
        for profile in ('tuning', 'full', 'full-render'):
            metadata = bench.design(self.args('--profile', profile, '--workers', '1'))
            metadata['variants'] = {'A': dict(evaluator=args.a), 'B': dict(evaluator=args.b)}
            for case in metadata['configurations']:
                for variant in 'AB':
                    bench.generation_config(catalogue, bench.case_config(metadata, case, variant))
        with self.assertRaisesRegex(ValueError, 'no unique native generation configuration'):
            bench.generation_config(catalogue, dict(evaluator='classified-indexed', pattern='gaussian',
                                                   neighbors=9, softness=0))

    def test_render_metric_is_selected_independently_of_workload_mode(self):
        for profile in ('tuning', 'full', 'full-render'):
            metadata = bench.design(self.args('--profile', profile, '--metrics', 'render'))
            self.assertEqual(metadata['metrics'], ['render_ns'])
            self.assertEqual(metadata['mode'], 'full-render' if profile == 'full-render' else 'evaluation')

    def test_perlin_has_no_neighborhood_override(self):
        d = bench.design(self.args('--profile', 'full', '--patterns', 'perlin',
                                   '--workers', '1', '--scenes', 'plate',
                                   '--jitter', '.08', '--occupancy', '.7',
                                   '--perlin-threshold', '.1', '--perlin-transition', '0'))
        self.assertEqual(len(d['configurations']), 1)
        self.assertIsNone(d['configurations'][0]['neighbors'])
        self.assertEqual(d['configurations'][0]['softness'], 0.)
        self.assertEqual(d['config']['perlin_threshold'], .1)
        self.assertEqual(d['config']['perlin_transition'], 0.)

    def test_texture_filters(self):
        self.assertEqual(bench.design(self.args())['config']['texture_filter'], 'cubic_catmull_rom')
        for filter in ('nearest', 'linear', 'cubic_catmull_rom'):
            self.assertEqual(bench.design(self.args('--texture-filter', filter))['config']['texture_filter'], filter)


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
            path.write_text(json.dumps(rows))
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
                        {**rows[0], 'neighbors': 4, 'radius': 1.1}, {**rows[0], 'neighbors': True},
                        {**rows[0], 'neighbors': 9.0}, {**rows[0], 'softness': .01},
                        {**rows[0], 'unexpected': 1}):
                path.write_text(json.dumps([bad]))
                with self.assertRaises(ValueError):
                    bench.load_cases(path)

    def test_case_file_rejects_explicit_radius_and_softness_even_at_defaults(self):
        self.assertIsNone(self.args().radius)
        self.assertIsNone(self.args().softness)
        ordinary = bench.design(self.args('--patterns', 'soft'))
        self.assertEqual(ordinary['config']['radius'], .35)
        self.assertTrue(all(c['softness'] == .04 for c in ordinary['configurations']))
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            cases = root / 'cases.json'
            cases.write_text(json.dumps([dict(threads=1, scene='plate', pattern='gaussian',
                                             radius=.4, jitter=0, occupancy=1, neighbors=9, softness=0)]))
            for options in (['--radius', '.35'], ['--radius=.35'], ['--radius', '.6'],
                            ['--softness', '.04'], ['--softness=.04'], ['--softness', '.03']):
                with self.subTest(options=options):
                    with self.assertRaisesRegex(ValueError, '--case-file cannot be mixed'):
                        bench.design(self.args('--case-file', str(cases), *options))
                    out = root / 'not-created'
                    with patch.object(bench.subprocess, 'run') as native:
                        with self.assertRaises(SystemExit):
                            bench.main(['--out', str(out), '--case-file', str(cases), *options])
                        native.assert_not_called()
                    self.assertFalse(out.exists())
            explicit = bench.design(self.args('--patterns', 'soft', '--radius', '.35', '--softness', '.04'))
            self.assertEqual(explicit, ordinary)

    def test_complete_explicit_case_passes_and_echoes_radius(self):
        row = dict(threads=1, scene='plate', pattern='gaussian', radius=.6,
                   jitter=.08, occupancy=1, neighbors=9, softness=0)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            case_file, binary = root / 'cases.json', root / 'native'
            case_file.write_text(json.dumps([row]))
            binary.write_bytes(b'frozen fixture')
            calls = []
            def run(command, **kwargs):
                if command[-1] == '--list-evaluators':
                    return SimpleNamespace(returncode=0, stdout=json.dumps(self.catalogue()), stderr='')
                config = {k[2:].replace('-', '_'): v for k, v in zip(command[1::2], command[2::2])}
                for key in ('threads', 'width', 'height', 'frames', 'cells_u', 'cells_v', 'seed', 'neighbors'):
                    config[key] = int(config[key])
                for key in ('jitter', 'occupancy', 'radius', 'softness'):
                    config[key] = float(config[key])
                calls.append(config)
                return SimpleNamespace(returncode=0, stdout='BENCH ' + json.dumps(self.native(config)), stderr='')
            with patch.object(bench.subprocess, 'run', side_effect=run):
                self.assertEqual(bench.main(['--out', str(root / 'result'), '--binary', str(binary),
                                            '--case-file', str(case_file), '--repeats', '2',
                                            '--require-equal-output']), 0)
            self.assertEqual(len(calls), 4)
            for config in calls:
                self.assertEqual({k: config[k] for k in row}, row)
            self.assertIn('radius', (root / 'result/comparison.md').read_text())


    def test_zero_occupancy_respects_native_input_policy(self):
        with self.assertRaisesRegex(ValueError, 'occupancy must be positive'):
            bench.design(self.args('--patterns', 'gaussian', '--occupancy', '0'))
        bench.design(self.args('--patterns', 'perlin', '--occupancy', '0'))
        bench.design(self.args('--a', 'mock', '--b', 'mock', '--occupancy', '0'))
        with tempfile.TemporaryDirectory() as directory:
            cases = Path(directory) / 'cases.json'
            cases.write_text(json.dumps([dict(threads=1, scene='plate', pattern='soft',
                                             radius=.4, jitter=0, occupancy=0,
                                             neighbors=9, softness=.04)]))
            out = Path(directory) / 'not-created'
            with patch.object(bench.subprocess, 'run') as native:
                with self.assertRaises(SystemExit):
                    bench.main(['--out', str(out), '--case-file', str(cases)])
                native.assert_not_called()
            self.assertFalse(out.exists())

    def test_native_generation_sampling_mapping_is_generic(self):
        sample = dict(evaluator='shared-sampler', pattern='disk', neighbors=9, soft_edges=False)
        generation = dict(evaluator='new-generation', pattern='disk', neighbors=9, soft_edges=False)
        catalogue = dict(sampling_configs=[sample], configs=[dict(generation, sampling_index=0, sampling=sample)])
        routes = bench.catalogue_sampling_routes(catalogue)
        identity = dict(generation_evaluator='new-generation', sampling_evaluator='shared-sampler', sampling_index=0)
        identity['backing'] = 'new-backing'
        bench.validate_sampling_identity(identity, generation, routes)
        for changed in (dict(identity, generation_evaluator='shared-sampler'),
                        dict(identity, sampling_evaluator='new-generation'), dict(identity, sampling_index=1)):
            with self.assertRaises(ValueError):
                bench.validate_sampling_identity(changed, generation, routes)
        with self.assertRaises(ValueError):
            bench.catalogue_sampling_routes(dict(sampling_configs=[sample],
                                                 configs=[dict(generation, sampling_index=1, sampling=sample)]))


    def test_prepared_build_and_resource_identity_validation(self):
        config = dict(mode='evaluation', evaluator='list-indexed', pattern='hard', neighbors=9,
                      softness=0, width=32, height=24, frames=2)
        catalogue = self.catalogue()
        spec = dict(catalogue=catalogue, build_identity=catalogue['build_identity'],
                    workload_modes=catalogue['workload_modes'])
        routes, generation = bench.catalogue_sampling_routes(catalogue), bench.generation_config(catalogue, config)
        native = self.native(config)
        bench.validate_identity(native, config, spec, routes, generation)
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
                bench.validate_native(dict(native, resource_bytes=value), config)
        bench.validate_native(dict(native, duplicated_disk_records=3, record_capacity=18), config)
        with self.assertRaises(ValueError):
            bench.validate_native(dict(native, duplicated_disk_records=19, record_capacity=18), config)
        # Backing metadata, not a Python evaluator allowlist, determines stored identity.
        native['prepared_identity'].update(backing='none', generation_evaluator=None)
        bench.validate_identity(native, config, spec, routes, generation)
        for key, value in (('generation_evaluator', config['evaluator']), ('sampling_evaluator', None),
                           ('sampling_index', None), ('backing', None), ('backing', '')):
            with self.subTest(backingless_field=key), self.assertRaises(ValueError):
                bench.validate_identity(dict(native, prepared_identity=dict(native['prepared_identity'], **{key: value})),
                                        config, spec, routes, generation)

    def test_native_identity_fields_are_required(self):
        catalogue = self.catalogue()
        spec = dict(catalogue=catalogue, build_identity=catalogue['build_identity'],
                    workload_modes=catalogue['workload_modes'])
        for mode in ('evaluation', 'full-render'):
            config = dict(mode=mode, evaluator='texture', width=32, height=24, frames=2)
            native = self.native(config)
            bench.validate_identity(native, config, spec, None, None)
            for key in ('build_identity', 'prepared_identity', *bench.RESOURCE_FIELDS):
                incomplete = dict(native)
                incomplete.pop(key)
                with self.subTest(mode=mode, key=key), self.assertRaises(ValueError):
                    bench.validate_identity(incomplete, config, spec, None, None)

    def decode_command(self, command):
        config = {k[2:].replace('-', '_'): v for k, v in zip(command[1::2], command[2::2])}
        for key in ('threads', 'width', 'height', 'frames', 'cells_u', 'cells_v', 'seed', 'neighbors'):
            if key in config:
                config[key] = int(config[key])
        for key in ('jitter', 'occupancy', 'radius', 'softness', 'perlin_threshold', 'perlin_transition'):
            if key in config:
                config[key] = float(config[key])
        return config

    def test_two_sweeps_keep_raw_logs_and_reject_partial_analysis(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            binary, out = root / 'native', root / 'result'
            binary.write_bytes(b'fixture')
            def run(command, **kwargs):
                if command[-1] == '--list-evaluators':
                    return SimpleNamespace(returncode=0, stdout='', stderr=json.dumps(self.catalogue()))
                return SimpleNamespace(returncode=0, stdout='BENCH ' + json.dumps(self.native(self.decode_command(command))), stderr='')
            options = ['--out', str(out), '--binary', str(binary), '--workers', '2', '--scenes', 'plate', 'sphere',
                       '--patterns', 'hard', '--jitter', '0', '--occupancy', '1', '--neighbors', '9', '--radius', '.425',
                       '--frames', '2', '--repeats', '2', '--require-equal-output']
            with patch.object(bench.subprocess, 'run', side_effect=run):
                self.assertEqual(bench.main(options), 0)
            samples = read_samples(out)
            self.assertEqual(len(samples), 8)
            self.assertTrue(all(row['native']['threads'] == 2 and row['native']['frames'] == 2 for row in samples))
            self.assertTrue(all(len(row['binary_sha256']) == 64 and row['command'] for row in samples))
            commands = [json.loads(line) for line in (out / 'commands.jsonl').read_text().splitlines()]
            self.assertEqual(len(commands), 9)
            for command in commands:
                for suffix in ('.stdout', '.stderr', '.command.json'):
                    self.assertTrue((out / 'logs' / (command['label'] + suffix)).exists())
            metadata = json.loads((out / 'metadata.json').read_text())
            validator = bench.SampleValidator(metadata)
            for row in samples[:-1]:
                validator.add(row)
            with self.assertRaisesRegex(ValueError, 'partial results'):
                validator.finish()
            validator.add(samples[-1])
            groups, outputs = validator.finish()
            self.assertEqual(len(groups), 8)
            self.assertEqual(len(outputs), 4)
            before = (out / 'samples.jsonl').read_bytes()
            with patch('sys.stderr', new_callable=io.StringIO) as stderr, self.assertRaises(SystemExit):
                bench.main(options)
            self.assertIn('no resume', stderr.getvalue())
            self.assertEqual(before, (out / 'samples.jsonl').read_bytes())

    def test_catalogue_preflight_rejects_mismatches_before_sampling(self):
        for failure in ('route', 'build', 'features', 'feature-duplicate', 'missing-build',
                                'workload', 'workload-object', 'unsupported', 'missing-sampling-configs'):
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                a, b, out = root / 'a', root / 'b', root / 'out'
                a.write_bytes(b'a')
                b.write_bytes(b'b')
                calls = []
                def run(command, **kwargs):
                    calls.append(command)
                    self.assertEqual(command[-1], '--list-evaluators')
                    catalogue = self.catalogue()
                    if Path(command[0]).name == 'B':
                        if failure == 'route':
                            catalogue['configs'][0]['sampling_index'] = 999
                        elif failure == 'build':
                            catalogue['build_identity']['simd'] = 'off'
                        elif failure == 'features':
                            self.assertEqual(catalogue['build_identity']['cpu_model'], 'test')
                            catalogue['build_identity']['cpu_features'] = ['64bit', 'avx']
                        elif failure == 'feature-duplicate':
                            catalogue['build_identity']['cpu_features'].append('avx2')
                        elif failure == 'missing-build':
                            catalogue.pop('build_identity')
                        elif failure == 'workload':
                            catalogue['workload_modes']['evaluation'] = 'different'
                        elif failure == 'workload-object':
                            catalogue['workload_modes'] = ['test-static-v1']
                        elif failure == 'unsupported':
                            catalogue['configs'] = []
                        else:
                            catalogue.pop('sampling_configs')
                    return SimpleNamespace(returncode=0, stdout=json.dumps(catalogue), stderr='')
                with patch.object(bench.subprocess, 'run', side_effect=run), self.assertRaises(SystemExit):
                    bench.main(['--out', str(out), '--binary-a', str(a), '--binary-b', str(b), '--workers', '1'])
                self.assertEqual(len(calls), 2)
                self.assertFalse((out / 'samples.jsonl').exists())
                self.assertFalse((out / 'comparison.json').exists())

    def test_comparison_ignores_cpu_feature_order_without_rewriting_identities(self):
        base = self.catalogue()['build_identity']['cpu_features']
        # Catalogue orders differ across variants, and each variant's observations reverse its catalogue order.
        catalogues = dict(A=base, B=base[::-1])
        observations = {variant: features[::-1] for variant, features in catalogues.items()}
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            a, b, out = root / 'a', root / 'b', root / 'out'
            a.write_bytes(b'a')
            b.write_bytes(b'b')
            def run(command, **kwargs):
                variant = Path(command[0]).name
                if command[-1] == '--list-evaluators':
                    record, features, prefix = self.catalogue(), catalogues[variant], ''
                else:
                    record, features, prefix = self.native(self.decode_command(command)), observations[variant], 'BENCH '
                record['build_identity'] = dict(record['build_identity'], cpu_features=list(features))
                return SimpleNamespace(returncode=0, stdout=prefix + json.dumps(record), stderr='')
            options = ['--out', str(out), '--binary-a', str(a), '--binary-b', str(b), '--workers', '1',
                       '--scenes', 'plate', '--patterns', 'hard', '--jitter', '0', '--occupancy', '1',
                       '--neighbors', '9', '--frames', '2', '--repeats', '2']
            with patch.object(bench.subprocess, 'run', side_effect=run):
                self.assertEqual(bench.main(options), 0)
            # Equivalent feature sets complete; catalogue and observation metadata keep native order.
            metadata = json.loads((out / 'metadata.json').read_text())
            for variant in 'AB':
                spec = metadata['variants'][variant]
                self.assertEqual(catalogues[variant], spec['catalogue']['build_identity']['cpu_features'])
                self.assertEqual(catalogues[variant], spec['build_identity']['cpu_features'])
            samples = read_samples(out)
            self.assertEqual(len(samples), 4)
            for row in samples:
                self.assertEqual(observations[row['variant']], row['native']['build_identity']['cpu_features'])


    def test_supervised_collection_validates_once_and_caches_routes(self):
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory)
            args = self.args('--workers', '2', '--scenes', 'plate', 'sphere', '--patterns', 'hard',
                             '--jitter', '0', '--occupancy', '1', '--neighbors', '9', '--repeats', '8',
                             '--a', 'texture', '--texture', 'unused.bmp', '--require-equal-output')
            metadata = bench.design(args)
            metadata.update(timeout_seconds=10)
            templates = {}
            for variant in 'AB':
                catalogue = self.catalogue()
                metadata['variants'][variant] = dict(file='fixture-' + variant, sha256=variant * 64,
                    evaluator=args.a if variant == 'A' else args.b, catalogue=catalogue,
                    build_identity=catalogue['build_identity'], workload_modes=catalogue['workload_modes'])
                for case in metadata['configurations']:
                    config = bench.case_config(metadata, case, variant)
                    templates[case['scene'], config['evaluator']] = self.native(config)

            def run(command, *_):
                config = self.decode_command(command)
                native = templates[config['scene'], config['evaluator']]
                return SimpleNamespace(stdout='BENCH ' + json.dumps(native), stderr='')
            total = len(metadata['configurations']) * metadata['repeats'] * 2
            checked = []
            def validate(native, config):
                # A reader must see the raw observation before validation can reject it.
                checked.append(native)
                self.assertEqual(len(read_samples(out)), len(checked))
                original_validate(native, config)
            original_validate = bench.validate_native
            with patch.object(bench, 'run_logged', side_effect=run), \
                    patch.object(bench, 'validate_native', side_effect=validate) as native_check, \
                    patch.object(bench, 'catalogue_sampling_routes', wraps=bench.catalogue_sampling_routes) as routes, \
                    patch.object(bench, 'generation_config', wraps=bench.generation_config) as generations:
                groups, outputs = bench.run_comparison(out, metadata)
                self.assertEqual(native_check.call_count, total)
                self.assertEqual(routes.call_count, 2)
                self.assertEqual(generations.call_count, len(metadata['configurations']) * 2)
                with patch.object(bench, 'validate_native', side_effect=AssertionError('report revalidated observations')):
                    bench.report(out, metadata, groups, outputs)
            rows = read_samples(out)
            self.assertEqual(len(rows), total)
            self.assertEqual([(r['case_id'], r['sweep'], r['position'], r['variant']) for r in rows],
                             [(i, s, p, v) for s in (0, 1) for i in range(len(metadata['configurations']))
                              for p, v in enumerate(metadata['schedules'][s])])
            validator = bench.SampleValidator(metadata)
            validator.add(rows[0])
            with self.assertRaisesRegex(ValueError, 'duplicate sample position'):
                validator.add(rows[0])
            with self.assertRaisesRegex(ValueError, 'invalid sample position'):
                validator.add(dict(rows[1], position=-1))
            with self.assertRaisesRegex(ValueError, 'sample order differs'):
                validator.add(dict(rows[1], variant='A'))
            with self.assertRaisesRegex(ValueError, 'invalid sample location'):
                validator.add(dict(rows[1], sweep=2))
            rows[1]['native']['combined_ns'] = 999
            with self.assertRaisesRegex(ValueError, 'invalid combined timing'):
                validator.add(rows[1])
            with self.assertRaises(FileExistsError):
                bench.run_comparison(out, metadata)


    def test_f32_echo_validation_uses_exact_selected_precision(self):
        config = dict(mode='evaluation', evaluator='texture', width=32, height=24, frames=2,
                      radius=.425, jitter=.08)
        native = dict(self.native(config), precision='f32')
        bench.validate_native(native, config)
        native['radius'] = bench.struct.unpack('f', bench.struct.pack('f', .425))[0]
        bench.validate_native(native, config)
        native['radius'] = .426
        with self.assertRaises(ValueError):
            bench.validate_native(native, config)

    def test_f32_echo_overflow_is_a_validation_error(self):
        config = dict(mode='evaluation', evaluator='texture', width=32, height=24, frames=2, radius=.425)
        native = dict(self.native(config), precision='f32')
        for value in (-1e40, 1e40):
            for requested, actual in ((value, .425), (.425, value), (value, value)):
                with self.subTest(requested=requested, actual=actual):
                    with self.assertRaisesRegex(ValueError, 'native config echo outside f32 range: radius'):
                        bench.validate_native(dict(native, radius=actual), dict(config, radius=requested))
            # The same finite value is representable in f64.
            bench.validate_native(dict(native, precision='f64', radius=value), dict(config, radius=value))

    def test_f32_echo_overflow_exits_cleanly_and_keeps_observation(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            binary, out = root / 'native', root / 'result'
            binary.write_bytes(b'fixture')
            def run(command, **kwargs):
                if command[-1] == '--list-evaluators':
                    catalogue = self.catalogue()
                    catalogue['build_identity']['precision'] = 'f32'
                    return SimpleNamespace(returncode=0, stdout=json.dumps(catalogue), stderr='')
                native = self.native(self.decode_command(command))
                native['precision'] = native['build_identity']['precision'] = 'f32'
                return SimpleNamespace(returncode=0, stdout='BENCH ' + json.dumps(native), stderr='')
            with patch.object(bench.subprocess, 'run', side_effect=run), patch('sys.stderr', new_callable=io.StringIO) as stderr:
                with self.assertRaises(SystemExit) as error:
                    bench.main(['--out', str(out), '--binary', str(binary), '--workers', '1',
                                '--scenes', 'plate', '--patterns', 'hard', '--neighbors', '9',
                                '--jitter', '0', '--occupancy', '1', '--repeats', '2',
                                '--perlin-threshold', '1e40'])
            self.assertEqual(error.exception.code, 1)
            self.assertIn('native config echo outside f32 range: perlin_threshold', stderr.getvalue())
            self.assertIn(str(out / 'logs/sweep-0-case-0-position-0-A'), stderr.getvalue())
            self.assertNotIn('Traceback', stderr.getvalue())
            self.assertEqual(len(read_samples(out)), 1)
            self.assertFalse((out / 'comparison.json').exists())

    def test_failure_and_timeout_keep_complete_raw_logs(self):
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory)
            failure = SimpleNamespace(returncode=7, stdout='complete stdout\nBENCH {"raw": true}\n', stderr='complete stderr\n')
            with patch.object(bench.subprocess, 'run', return_value=failure), \
                    patch('sys.stdout', new_callable=io.StringIO) as console, \
                    patch('sys.stderr', new_callable=io.StringIO) as errors, \
                    self.assertRaisesRegex(ValueError, 'command failed \\(7\\); full logs:'):
                bench.run_logged(['fixture', 'one two'], out, 'failure')
            self.assertEqual(console.getvalue(), '')
            self.assertEqual(errors.getvalue(), '')
            self.assertEqual((out / 'logs/failure.stdout').read_text(), failure.stdout)
            self.assertEqual((out / 'logs/failure.stderr').read_text(), failure.stderr)
            timeout = bench.subprocess.TimeoutExpired(['fixture'], 1, output=b'partial stdout', stderr=b'partial stderr')
            with patch.object(bench.subprocess, 'run', side_effect=timeout), self.assertRaisesRegex(ValueError, 'timed out.*full logs:'):
                bench.run_logged(['fixture'], out, 'timeout', 1)
            self.assertEqual((out / 'logs/timeout.stdout').read_text(), 'partial stdout')
            self.assertEqual((out / 'logs/timeout.stderr').read_text(), 'partial stderr')
            self.assertEqual(json.loads((out / 'logs/timeout.command.json').read_text())['timeout_seconds'], 1)
            with patch.object(bench.subprocess, 'run', side_effect=OSError('missing executable')), \
                    self.assertRaisesRegex(OSError, 'missing executable; full logs:'):
                bench.run_logged(['missing-fixture'], out, 'launch-error')
            self.assertEqual((out / 'logs/launch-error.stdout').read_text(), '')
            self.assertEqual((out / 'logs/launch-error.stderr').read_text(), '')
            self.assertEqual(json.loads((out / 'logs/launch-error.command.json').read_text())['error'], 'missing executable')

    def test_success_retains_full_output_without_console_echo(self):
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory)
            success = SimpleNamespace(returncode=0, stdout='BENCH {"complete": true}\n', stderr='diagnostic\n')
            with patch.object(bench.subprocess, 'run', return_value=success), \
                    patch('sys.stdout', new_callable=io.StringIO) as console, \
                    patch('sys.stderr', new_callable=io.StringIO) as errors:
                self.assertIs(bench.run_logged(['fixture'], out, 'success'), success)
            self.assertEqual(console.getvalue(), '')
            self.assertEqual(errors.getvalue(), '')
            self.assertEqual((out / 'logs/success.stdout').read_text(), success.stdout)
            self.assertEqual((out / 'logs/success.stderr').read_text(), success.stderr)

    def test_help_and_no_resume_entry_point(self):
        help_text = bench.parser().format_help()
        self.assertIn('use classified-binned', help_text)
        self.assertIn('no resume', help_text)
        self.assertNotIn('use classified-indexed', help_text)
        with patch('sys.stderr', new_callable=io.StringIO) as stderr, self.assertRaises(SystemExit):
            bench.main(['--out', 'unused', '--resume'])
        self.assertIn('unrecognized arguments: --resume', stderr.getvalue())

    def test_schedules(self):
        for repeats in range(2, 42, 2):
            first, second = bench.schedules(repeats)
            self.assertEqual(len(first), repeats)
            self.assertEqual(first.count('A'), repeats // 2)
            self.assertTrue(all(a != b for a, b in zip(first, second)))
        self.assertEqual(bench.schedules(12), ['ABBAABBAABBA', 'BAABBAABBAAB'])
        self.assertEqual(bench.schedules(16), ['ABBAABBAABBAABBA', 'BAABBAABBAABBAAB'])
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
                     optimize='ReleaseFast', strip=True, zig_version='0.16.0', target_arch='x86_64', cpu_model='test',
                     cpu_features=['64bit', 'avx', 'avx2'])
        samples = [dict(evaluator=evaluator, pattern=pattern, neighbors=neighbors, soft_edges=soft)
                   for evaluator in ('cell-hash', 'list-indexed', 'cell-binned')
                   for pattern in ('disk', 'gaussian', 'perlin')
                   for neighbors in ((None,) if pattern == 'perlin' else (1, 4, 9))
                   for soft in ((False, True) if pattern == 'disk' else (None,))]
        samples.extend(dict(evaluator=evaluator, pattern='disk', neighbors=9, soft_edges=False)
                       for evaluator in ('classified-indexed', 'classified-binned'))
        return dict(evaluators=['texture', 'cell-hash', 'list-indexed', 'cell-binned',
                                'classified-indexed', 'classified-binned'], overrides_enabled=True,
                    configs=[dict(row, sampling_index=i, sampling=row) for i, row in enumerate(samples)],
                    sampling_configs=samples, build_identity=build,
                    workload_modes={'evaluation': 'test-static-v1', 'full-render': 'test-production-v2'})

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
        return dict(config, resource_ns=1, render_ns=2, combined_ns=3, checksum=7,
                    shaded_samples=10 if evaluation else 0, evaluation_counters_available=evaluation,
                    image_samples=0 if evaluation else config['width'] * config['height'] * config['frames'],
                    precision='f64', simd='on', workload_mode=catalogue['workload_modes'][config['mode']],
                    build_identity=catalogue['build_identity'], prepared_identity=identity,
                    **dict.fromkeys(bench.RESOURCE_FIELDS))

    def test_native_contract(self):
        for mode in ('evaluation', 'full-render'):
            config = dict(mode=mode, evaluator='texture', width=32, height=24, frames=2,
                          texture='/custom.bmp', texture_filter='cubic_catmull_rom', neighbors=4, radius=.4)
            native = self.native(config)
            bench.validate_native(native, config)
            bad = [('mode', 'unexpected-mode'), ('texture', '/wrong.bmp'), ('texture_filter', 'linear'), ('neighbors', 1),
                   ('radius', .6), ('combined_ns', 9), ('render_ns', float('nan')), ('checksum', -1),
                   ('evaluation_counters_available', mode != 'evaluation'), ('image_samples', 1),
                   ('shaded_samples', 0 if mode == 'evaluation' else 10)]
            for key, value in bad:
                with self.assertRaises(ValueError, msg=key):
                    bench.validate_native({**native, key: value}, config)

    def test_output_check_flag_conflict(self):
        with self.assertRaises(SystemExit) as error:
            self.args('--skip-output-checks', '--require-equal-output')
        self.assertEqual(error.exception.code, 2)

    def test_complete_run_and_failure(self):
        for profile, failure in (('tuning', None), ('full', None), ('full-render', None),
                                 ('tuning', 'repeat'), ('tuning', 'equal'), ('tuning', 'record'), ('tuning', 'duplicate-record'), ('tuning', 'json'), ('tuning', 'object'),
                                                                  ('full-render', 'skip'), ('full-render', 'vary')):
            with self.subTest(profile=profile, failure=failure), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                binary, other, texture = root / 'native', root / 'other', root / 'asset.bmp'
                binary.write_bytes(b'original A')
                other.write_bytes(b'original B')
                texture.write_bytes(b'original texture')
                out, calls = root / 'comparison', []

                def run(command, **kwargs):
                    if command[-1] == '--list-evaluators':
                        return SimpleNamespace(returncode=0, stdout=json.dumps(self.catalogue()), stderr='')
                    values = dict(zip(command[1::2], command[2::2]))
                    config = {k[2:].replace('-', '_'): v for k, v in values.items()}
                    for key in ('threads', 'width', 'height', 'frames', 'cells_u', 'cells_v', 'seed', 'neighbors'):
                        config[key] = int(config[key])
                    for key in ('jitter', 'occupancy', 'radius', 'softness'):
                        config[key] = float(config[key])
                    calls.append(config['evaluator'])
                    self.assertEqual(Path(command[0]).read_bytes(), b'original A' if config['evaluator'] == 'texture' else b'original B')
                    self.assertEqual(Path(config['texture']).read_bytes(), b'original texture')
                    self.assertEqual(config['texture_filter'], 'cubic_catmull_rom')
                    binary.write_bytes(b'rebuilt A')
                    other.write_bytes(b'rebuilt B')
                    texture.write_bytes(b'changed texture')
                    native = self.native(config)
                    native['checksum'] = 1 if config['evaluator'] == 'texture' else 2
                    if failure in ('skip', 'vary'):
                        native['checksum'] = len(calls)
                    if failure == 'repeat' and len(calls) == 4:
                        native['checksum'] = 9
                    text = '' if failure == 'record' and len(calls) == 2 else 'BENCH ' + json.dumps(native)
                    if failure == 'duplicate-record' and len(calls) == 2:
                        text += '\n' + text
                    if failure == 'json' and len(calls) == 2:
                        text = 'BENCH invalid json'
                    if failure == 'object' and len(calls) == 2:
                        text = 'BENCH []'
                    return SimpleNamespace(returncode=0, stdout=text, stderr='')

                options = ['--out', str(out), '--profile', profile, '--binary', str(binary), '--binary-b', str(other),
                           '--a', 'texture', '--b', 'list-indexed', '--texture', str(texture), '--workers', '1', '--scenes', 'plate',
                           '--patterns', 'soft', '--jitter', '.08', '--occupancy', '.7', '--neighbors', '4',
                           '--width', '32', '--height', '24', '--frames', '2', '--repeats', '2']
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
                        self.assertEqual(calls, ['texture', 'list-indexed', 'list-indexed', 'texture'])
                        records = json.loads((out / 'comparison.json').read_text())
                        self.assertEqual(sum('p' in r for r in records), 1 if profile == 'tuning' else 2)
                        self.assertTrue(all(not r['output_equal'] for r in records))
                        metadata = json.loads((out / 'metadata.json').read_text())
                        self.assertEqual(metadata['runner_sha256'], hashlib.sha256(Path(bench.__file__).read_bytes()).hexdigest())
                        self.assertEqual(len(metadata['variants']['A']['sha256']), 64)
                        self.assertEqual(metadata['skip_output_checks'], failure == 'skip')
                        self.assertEqual(set(metadata['resource_metric_semantics']), set(bench.RESOURCE_FIELDS))
                        self.assertIn('cubic_catmull_rom', (out / 'comparison.md').read_text())
                        if failure == 'skip':
                            samples = [json.loads(line) for line in (out / 'samples.jsonl').read_text().splitlines()]
                            for variant in 'AB':
                                self.assertEqual(len({r['native']['checksum'] for r in samples if r['variant'] == variant}), 2)
                            self.assertIn('no image consistency guarantee', (out / 'comparison.md').read_text())
                self.assertTrue((out / 'samples.jsonl').read_text())
                with self.assertRaises(SystemExit):
                    bench.main(options)


class NativeBenchmarkTests(unittest.TestCase):
    def test_classified_binned_catalogue_and_records_through_runner(self):
        if 'RILEY_SPECKLE_BENCH_BINARY' not in os.environ:
            self.skipTest('set RILEY_SPECKLE_BENCH_BINARY to a stripped ReleaseFast all-evaluator native build')
        self.assertTrue(os.environ['RILEY_SPECKLE_BENCH_BINARY'], 'native binary path must not be empty')
        binary = Path(os.environ['RILEY_SPECKLE_BENCH_BINARY']).resolve()
        self.assertTrue(binary.is_file(), f'native binary does not exist: {binary}')
        # No subprocess mocks: freeze and execute the supplied native binary, then
        # independently inspect the same catalogue/observations accepted by the runner.
        with tempfile.TemporaryDirectory() as directory:
            for profile in ('full', 'full-render'):
                with self.subTest(profile=profile):
                    out = Path(directory) / profile
                    self.assertEqual(bench.main([
                        '--out', str(out), '--binary', str(binary), '--profile', profile,
                        '--a', 'cell-binned', '--b', 'classified-binned', '--workers', '1',
                        '--scenes', 'plate', 'sphere', '--patterns', 'hard', '--neighbors', '9',
                        '--jitter', '0', '--occupancy', '1', '--radius', '.425',
                        '--width', '32', '--height', '24', '--frames', '2',
                        '--cells-plate', '8', '4', '--cells-sphere', '8', '4',
                        '--repeats', '2', '--metrics', 'render', '--require-equal-output']), 0)
                    metadata = json.loads((out / 'metadata.json').read_text())
                    catalogue = metadata['variants']['B']['catalogue']
                    self.assertIn('classified-binned', catalogue['evaluators'])
                    generation = dict(evaluator='classified-binned', pattern='disk', neighbors=9, soft_edges=False)
                    route = bench.catalogue_sampling_routes(catalogue)[tuple(generation.values())]
                    self.assertEqual(route['sampling']['evaluator'], 'classified-binned')
                    for variant in 'AB':
                        for case in metadata['configurations']:
                            bench.generation_config(catalogue, bench.case_config(metadata, case, variant))
                    # Also check the actual catalogue, rather than only the mock,
                    # supports the unmodified profile matrices and current default pair.
                    defaults = bench.parser().parse_args(['--out', 'unused'])
                    for default_profile in ('tuning', 'full', 'full-render'):
                        matrix = bench.design(bench.parser().parse_args([
                            '--out', 'unused', '--profile', default_profile, '--workers', '1']))
                        for case in matrix['configurations']:
                            for evaluator in (defaults.a, defaults.b):
                                bench.generation_config(catalogue, dict(case, evaluator=evaluator))
                    rows = read_samples(out)
                    self.assertEqual(len(rows), 8)
                    self.assertEqual({row['native']['scene'] for row in rows}, {'plate', 'sphere'})
                    for row in rows:
                        native = row['native']
                        self.assertNotIn('peak_preparation_bytes', native)
                        self.assertNotIn('active_owners', native)
                        self.assertEqual(native['workload_mode'], catalogue['workload_modes'][metadata['mode']])
                        if profile == 'full' and row['variant'] == 'B':
                            identity = native['prepared_identity']
                            self.assertEqual(identity['generation_evaluator'], 'classified-binned')
                            self.assertEqual(identity['sampling_evaluator'], 'classified-binned')
                            self.assertEqual(identity['sampling_index'], route['sampling_index'])
                            self.assertEqual(identity['backing'], 'classified_binned')
                            self.assertGreater(native['resource_bytes'], 0)
                            self.assertGreater(native['duplicated_disk_records'], 0)
                            self.assertLessEqual(native['duplicated_disk_records'], native['record_capacity'])
                        if profile == 'full-render':
                            self.assertIsNone(native['prepared_identity'])
                            self.assertTrue(all(native[field] is None for field in bench.RESOURCE_FIELDS))
                    reports = json.loads((out / 'comparison.json').read_text())
                    self.assertEqual(len(reports), 6)
                    self.assertTrue(all(row['output_equal'] for row in reports))
                    primary = [row for row in reports if 'p' in row]
                    self.assertEqual(len(primary), 2)
                    self.assertTrue(all(row['metric'] == 'render_ns' for row in primary))
                    print(f'Native smoke passed: {profile}, 2 scenes, {len(rows)} real observations', flush=True)


if __name__ == '__main__':
    unittest.main()
