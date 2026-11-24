"""Regression tests for the multi-root benchmark runner."""

from contextlib import redirect_stdout
import io
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from scripts import bench_multiroot as bench


class MultiRootBenchmarkTests(unittest.TestCase):
    def test_experiment_one_writes_matching_timestamped_summary(self):
        def run_case(_args, backend, _name, mode, scene, **options):
            return [dict.fromkeys(bench.FIELDS, '1') | dict(
                backend=backend, mode=mode, scene=scene,
                one_root_edge_mode=options.get('one_root_edge_mode', 'on_the_fly'),
                multi_root_edge_mode=options.get('multi_root_edge_mode', 'on_the_fly'),
                buffer_mode=options.get('buffer_mode', 'tile_local'))]

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            out_root = root / 'runs'
            timestamp = '2026-11-24_12-00-00'
            with (patch.object(bench, 'ROOT', root),
                  patch.object(bench, 'timestamp_string', return_value=timestamp) as clock,
                  patch.object(bench, 'run_case', side_effect=run_case),
                  patch('sys.argv', ['bench_multiroot', '--skip-build', '--out-root', str(out_root)]),
                  redirect_stdout(io.StringIO())):
                bench.main()
            clock.assert_called_once_with()
            per_run = out_root / timestamp / 'summary_stats_multiroot.csv'
            aggregate = root / 'out' / f'summary_bench_multiroot_median_{timestamp}.csv'
            self.assertEqual(per_run.read_bytes(), aggregate.read_bytes())
