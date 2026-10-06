#!/usr/bin/env python3
"""Small, independent statistics checks and mocked complete comparisons."""
from itertools import combinations, product
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import bench_speckle as bench


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
                        ('--radius', 'inf'), ('--permutations', '0'), ('--softness', '0'), ('--a', 'texture')):
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

    def native(self, config):
        evaluation = config['mode'] == 'evaluation'
        return dict(config, resource_ns=1, render_ns=2, combined_ns=3, checksum=7,
                    shaded_samples=10 if evaluation else 0, evaluation_counters_available=evaluation,
                    image_samples=0 if evaluation else config['width'] * config['height'] * config['frames'])

    def test_native_contract(self):
        for mode in ('evaluation', 'full-render'):
            config = dict(mode=mode, evaluator='texture', width=32, height=24, frames=2,
                          texture='/custom.bmp', texture_filter='nearest', neighbors=4)
            native = self.native(config)
            bench.validate_native(native, config)
            bad = [('mode', 'old'), ('texture', '/wrong.bmp'), ('texture_filter', 'linear'), ('neighbors', 1),
                   ('combined_ns', 9), ('render_ns', float('nan')), ('checksum', -1),
                   ('evaluation_counters_available', mode != 'evaluation'), ('image_samples', 1),
                   ('shaded_samples', 0 if mode == 'evaluation' else 10)]
            for key, value in bad:
                with self.assertRaises(ValueError, msg=key):
                    bench.validate_native({**native, key: value}, config)

    def test_complete_run_and_failure(self):
        for profile, failure in (('tuning', None), ('full', None), ('full-render', None),
                                 ('tuning', 'repeat'), ('tuning', 'equal'), ('tuning', 'record')):
            with self.subTest(profile=profile, failure=failure), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                binary, other, texture = root / 'native', root / 'other', root / 'asset.bmp'
                binary.write_bytes(b'original A')
                other.write_bytes(b'original B')
                texture.write_bytes(b'original texture')
                out, calls = root / 'comparison', []

                def run(command, **kwargs):
                    values = dict(zip(command[1::2], command[2::2]))
                    config = {k[2:].replace('-', '_'): v for k, v in values.items()}
                    for key in ('threads', 'width', 'height', 'frames', 'cells_u', 'cells_v', 'seed', 'neighbors'):
                        config[key] = int(config[key])
                    for key in ('jitter', 'occupancy', 'radius', 'softness'):
                        config[key] = float(config[key])
                    calls.append(config['evaluator'])
                    self.assertEqual(Path(command[0]).read_bytes(), b'original A' if config['evaluator'] == 'texture' else b'original B')
                    self.assertEqual(Path(config['texture']).read_bytes(), b'original texture')
                    binary.write_bytes(b'rebuilt A')
                    other.write_bytes(b'rebuilt B')
                    texture.write_bytes(b'changed texture')
                    native = self.native(config)
                    native['checksum'] = 1 if config['evaluator'] == 'texture' else 2
                    if failure == 'repeat' and len(calls) == 4:
                        native['checksum'] = 9
                    text = '' if failure == 'record' and len(calls) == 2 else 'BENCH ' + json.dumps(native)
                    return SimpleNamespace(returncode=0, stdout=text, stderr='')

                options = ['--out', str(out), '--profile', profile, '--binary', str(binary), '--binary-b', str(other),
                           '--a', 'texture', '--texture', str(texture), '--workers', '1', '--scenes', 'plate',
                           '--patterns', 'soft', '--jitter', '.08', '--occupancy', '.7', '--neighbors', '4',
                           '--width', '32', '--height', '24', '--frames', '2', '--repeats', '2']
                if failure == 'equal':
                    options.append('--require-equal-output')
                with patch.object(bench.subprocess, 'run', side_effect=run):
                    if failure:
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
                        self.assertEqual(len(metadata['variants']['A']['sha256']), 64)
                self.assertTrue((out / 'samples.jsonl').read_text())
                with self.assertRaises(SystemExit):
                    bench.main(options)


if __name__ == '__main__':
    unittest.main()
