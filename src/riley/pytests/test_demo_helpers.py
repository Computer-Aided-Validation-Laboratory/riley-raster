from __future__ import annotations

import importlib
import sys
from pathlib import Path

import numpy as np
import pytest
from PIL import Image

from riley.__main__ import _DEMO_FUNCS, main as launch
from riley.pydemos import demo_rabbits_common as common


pytest_plugins = ("pytester",)


@pytest.mark.parametrize("channels", (1, 3))
def test_rabbit_uv_field_has_one_frame_and_expected_channels(
    channels: int,
) -> None:
    uvs = np.array([[0.2, 0.6], [0.0, 1.0]])
    field = common.build_uv_field(uvs, channels)
    assert field.shape == (2, 1, channels)
    assert field.dtype == np.float64
    assert field.flags.c_contiguous
    if channels == 1:
        expected = [[0.4], [0.5]]
    else:
        expected = [[0.2, 0.6, 0.4], [0.0, 1.0, 0.5]]
    np.testing.assert_allclose(field[:, 0, :], expected)


def test_numbered_demo_cli_modules_are_importable() -> None:
    expected = (
        "demo00_quickstart",
        "demo00b_procedural_quickstart",
        "demo01_sphere",
        "demo01b_procedural_sphere",
        "demo02a_rabbits_mono",
        "demo02b_rabbits_rgb",
        "demo02c_rabbits_fields",
        "demo02d_rabbit_procedural",
        "demo03_dicuq",
        "demo03_dicuq_from_exodus",
        "demo04_stereocal",
        "demo05_cameramodels",
        "demo06_featurezoo",
        "demo07_shaderpipe_quickstart",
        "demo08_shaderpipe_gallery",
        "demo09_diciruq",
        "demo10_sphere_lit",
    )
    assert tuple(_DEMO_FUNCS) == expected
    for name in expected:
        module = importlib.import_module(_DEMO_FUNCS[name])
        assert callable(module.main)


def test_procedural_demo_launcher_forwards_options_and_help(
    monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str],
) -> None:
    monkeypatch.setattr(
        sys, "argv", ["riley", "demo00b_procedural_quickstart", "--width", "0"],
    )
    with pytest.raises(SystemExit) as exc:
        launch()
    assert exc.value.code == 2
    assert "positive integers" in capsys.readouterr().err

    monkeypatch.setattr(sys, "argv", ["riley", "demo00b_procedural_quickstart", "--help"])
    with pytest.raises(SystemExit) as exc:
        launch()
    assert exc.value.code == 0
    assert "--pattern {disk,gaussian,perlin}" in capsys.readouterr().out


@pytest.mark.parametrize(("args", "exit_code", "message"), (
    (["--help"], 0, "usage: python -m riley demo00_quickstart"),
    (["--he"], 2, "unrecognized arguments: --he"),
    (["extra"], 2, "unrecognized arguments: extra"),
))
def test_optionless_demo_validates_args_before_import(
    args: list[str], exit_code: int, message: str,
    monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str],
) -> None:
    monkeypatch.setattr(sys, "argv", ["riley", "demo00_quickstart", *args])
    monkeypatch.setattr(importlib, "import_module", lambda name: pytest.fail(f"imported {name}"))
    with pytest.raises(SystemExit) as exc:
        launch()
    assert exc.value.code == exit_code
    captured = capsys.readouterr()
    assert message in (captured.err if exit_code else captured.out)


def test_launcher_forwards_pytest_args(monkeypatch: pytest.MonkeyPatch) -> None:
    def run_pytest(args: list[str]) -> int:
        assert args == ["-s", "--pyargs", "riley.pytests", "-k", "demo", "--help"]
        return 5

    monkeypatch.setattr(sys, "argv", ["riley", "test", "-k", "demo", "--help"])
    monkeypatch.setattr(pytest, "main", run_pytest)
    with pytest.raises(SystemExit) as exc:
        launch()
    assert exc.value.code == 5


@pytest.mark.parametrize(("name", "files"), (
    ("demo00b_procedural_quickstart", ("disk.bmp",)),
    ("demo01b_procedural_sphere", tuple(f"cam0_frame{frame}_field0.bmp" for frame in range(3))),
    ("demo02d_rabbit_procedural", ("cam0_frame0_field0.bmp",)),
))
def test_procedural_demo_cache_requires_default_outputs(
    tmp_path: Path, name: str, files: tuple[str, ...],
) -> None:
    from riley.pytests.test_riley import _has_expected_demo_renders

    cache = tmp_path / name
    cache.mkdir()
    for file in files:
        assert not _has_expected_demo_renders(cache, None)
        (cache / file).touch()
    assert _has_expected_demo_renders(cache, None)
    extra = cache / "unexpected.bmp"
    extra.touch()
    assert not _has_expected_demo_renders(cache, None)
    extra.unlink()
    (cache / files[-1]).unlink()
    (cache / files[-1]).mkdir()
    assert not _has_expected_demo_renders(cache, None)


@pytest.mark.parametrize(("zig_frames", "py_frames", "failing_side"), (
    ((), (), "zig"),
    ((0,), (0,), "zig"),
    ((0, 1, 2, 3), (0, 1, 2, 3), "zig"),
    ((0, 1, 2), (0, 1, 3), "python"),
))
def test_procedural_compare_requires_exact_render_names(
    tmp_path: Path, zig_frames: tuple[int, ...], py_frames: tuple[int, ...],
    failing_side: str,
) -> None:
    from riley.pytests.test_riley import _compare_render_dirs

    zig_dir = tmp_path / "out" / "demo01b_procedural_sphere"
    py_dir = tmp_path / "out_riley_py" / zig_dir.name
    for directory, frames in ((zig_dir, zig_frames), (py_dir, py_frames)):
        directory.mkdir(parents=True)
        for frame in frames:
            Image.new("L", (2, 2)).save(directory / f"cam0_frame{frame}_field0.bmp")

    with pytest.raises(AssertionError, match=f"unexpected {failing_side} procedural render names"):
        _compare_render_dirs(zig_dir, py_dir)


def test_procedural_compare_rejects_matching_blank_images(tmp_path: Path) -> None:
    from riley.pytests.test_riley import _compare_render_dirs

    zig_dir = tmp_path / "out" / "demo00b_procedural_quickstart"
    py_dir = tmp_path / "out_riley_py" / zig_dir.name
    for directory in (zig_dir, py_dir):
        directory.mkdir(parents=True)
        Image.new("L", (2, 2), color=128).save(directory / "disk.bmp")

    with pytest.raises(AssertionError, match="procedural render lacks contrast"):
        _compare_render_dirs(zig_dir, py_dir)


@pytest.mark.parametrize(
    ("platform_tag", "target"),
    (
        ("win32", "x86-windows-msvc"),
        ("win-amd64", "x86_64-windows-msvc"),
        ("win_amd64", "x86_64-windows-msvc"),
        ("win-arm64", "aarch64-windows-msvc"),
        ("win_arm64", "aarch64-windows-msvc"),
    ),
)
def test_zig_parity_windows_target_matches_python_platform(
    platform_tag: str, target: str, monkeypatch: pytest.MonkeyPatch,
) -> None:
    from riley import _zig_toolchain as toolchain
    from riley.pytests import test_riley as parity

    monkeypatch.setattr(parity.platform, "system", lambda: "Windows")
    monkeypatch.setattr(parity.platform, "machine", lambda: "AMD64")
    monkeypatch.setattr(toolchain.sysconfig, "get_platform", lambda: platform_tag)
    runner = [sys.executable, "-m", "ziglang"]
    assert parity._get_zig_run_cmd(runner) == [
        *runner, "build", "run-all-demos", "-Doptimize=ReleaseFast",
        "-Dprecision=f64", "-Dsimd=on", f"-Dtarget={target}",
    ]


def test_zig_parity_non_windows_keeps_native_target(monkeypatch: pytest.MonkeyPatch) -> None:
    from riley.pytests import test_riley as parity

    monkeypatch.setattr(parity.platform, "system", lambda: "Linux")
    assert parity._get_zig_run_cmd(["zig"], "run-demo00b_procedural_quickstart") == [
        "zig", "build", "run-demo00b_procedural_quickstart", "-Doptimize=ReleaseFast",
        "-Dprecision=f64", "-Dsimd=on",
    ]


def test_zig_parity_does_not_probe_without_checkout(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch,
) -> None:
    from riley.pytests import test_riley as parity

    monkeypatch.setattr(parity, "PROJECT_ROOT", tmp_path)
    monkeypatch.setattr(parity, "select_zig_runner", lambda: pytest.fail("unexpected probe"))
    parity.ensure_zig_demo_renders.__wrapped__()


def test_zig_parity_skips_with_pinned_compiler_diagnostic(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from riley import _zig_toolchain as toolchain
    from riley.pytests import test_riley as parity

    monkeypatch.setattr(parity, "_repo_assets_available", lambda: True)
    monkeypatch.setattr(toolchain.shutil, "which", lambda _: "zig")
    monkeypatch.setattr(toolchain.subprocess, "check_output", lambda *a, **kw: "0.15.2\n")
    monkeypatch.setattr(toolchain, "find_spec", lambda _: None)
    with pytest.raises(pytest.skip.Exception) as skipped:
        parity.ensure_zig_demo_renders.__wrapped__()
    assert f"Riley requires Zig {toolchain.REQUIRED_ZIG_VERSION}" in str(skipped.value)
    assert "0.15.2" in str(skipped.value)
    assert "ziglang is not installed" in str(skipped.value)


def test_missing_zig_skips_only_parity_tests(
    pytester: pytest.Pytester, monkeypatch: pytest.MonkeyPatch,
) -> None:
    from riley.pytests import test_riley as parity

    def missing_zig() -> list[str]:
        raise parity.ZigUnavailableError("pinned Zig unavailable")

    def render_stereocal(label: str, cmd: list[str], env: dict[str, str]) -> None:
        case_name, python_cmd, py_dir, frames_num = parity.CALIBRATION_DEMO_CASE
        assert label == f"python render {case_name}"
        assert cmd == python_cmd
        output = pytester.path / py_dir
        output.mkdir(parents=True)
        for camera in range(2):
            for frame in range(frames_num):
                (output / f"cam{camera}_frame{frame}_field0.bmp").touch()

    monkeypatch.setattr(parity, "PROJECT_ROOT", pytester.path)
    monkeypatch.setattr(parity, "_repo_assets_available", lambda: True)
    monkeypatch.setattr(parity, "select_zig_runner", missing_zig)
    monkeypatch.setattr(parity, "_run_command", render_stereocal)

    result = pytester.runpytest_inprocess(str(Path(parity.__file__).resolve()), "-q", "-rs")
    result.assert_outcomes(passed=2, skipped=len(parity.ALL_DEMO_CASES))
    assert "Cannot render Zig demos for parity: pinned Zig unavailable" in result.stdout.str()


def test_zig_parity_propagates_unexpected_selection_error(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from riley.pytests import test_riley as parity

    def broken_selector() -> list[str]:
        raise RuntimeError("unexpected probe error")

    monkeypatch.setattr(parity, "_repo_assets_available", lambda: True)
    monkeypatch.setattr(parity, "select_zig_runner", broken_selector)
    with pytest.raises(RuntimeError, match="unexpected probe error"):
        parity.ensure_zig_demo_renders.__wrapped__()


def test_zig_demo_cache_hash_tracks_full_command_and_inputs(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch,
) -> None:
    from riley.pytests import test_riley as parity

    monkeypatch.setattr(parity, "PROJECT_ROOT", tmp_path)
    monkeypatch.setattr(parity.platform, "system", lambda: "Linux")
    inputs = ("build.zig", "build.zig.zon", "src/demo.zig", "data/mesh", "texture/image")
    for name in inputs:
        path = tmp_path / name
        path.parent.mkdir(exist_ok=True)
        path.write_bytes(b"original")

    full_cmd = parity._get_zig_run_cmd(["zig"])
    original_sha = parity._compute_zig_demo_sources_sha(full_cmd)
    for cmd in (
        parity._get_zig_run_cmd([sys.executable, "-m", "ziglang"]),
        [*full_cmd, "-Dtarget=x86_64-windows-msvc"],
        [arg.replace("-Dsimd=on", "-Dsimd=off") for arg in full_cmd],
    ):
        assert parity._compute_zig_demo_sources_sha(cmd) != original_sha
    for name in inputs:
        path = tmp_path / name
        path.write_bytes(b"changed")
        assert parity._compute_zig_demo_sources_sha(full_cmd) != original_sha, name
        path.write_bytes(b"original")
    monkeypatch.setattr(parity, "REQUIRED_ZIG_VERSION", "different-version")
    assert parity._compute_zig_demo_sources_sha(full_cmd) != original_sha


@pytest.mark.parametrize("complete", (False, True))
def test_zig_full_refresh_only_stamps_complete_procedural_renders(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, complete: bool,
) -> None:
    from riley.pytests import test_riley as parity

    monkeypatch.setattr(parity, "PROJECT_ROOT", tmp_path)
    monkeypatch.setenv("RILEY_FORCE_ZIG_RENDER", "1")
    stamp = tmp_path / "out" / ".zig_demos.sha256"
    stamp.parent.mkdir()
    stamp.write_text("stale\n", encoding="utf-8")
    zig_runner = [sys.executable, "-m", "ziglang"]
    full_cmd = parity._get_zig_run_cmd(zig_runner)
    monkeypatch.setattr(parity, "_repo_assets_available", lambda: True)
    monkeypatch.setattr(parity, "select_zig_runner", lambda: zig_runner)

    def render(label: str, cmd: list[str], env: dict[str, str]) -> None:
        assert cmd == full_cmd
        for name, files in parity._PROCEDURAL_DEMO_RENDERS.items():
            directory = stamp.parent / name
            directory.mkdir()
            for file in files:
                if complete or file.name != "cam0_frame2_field0.bmp":
                    (directory / file).touch()

    monkeypatch.setattr(parity, "_run_command", render)
    parity.ensure_zig_demo_renders.__wrapped__()
    if complete:
        assert stamp.read_text(encoding="utf-8").strip() == parity._compute_zig_demo_sources_sha(full_cmd)
    else:
        assert not stamp.exists()


def test_current_zig_cache_repairs_only_invalid_procedural_demo(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch,
) -> None:
    from riley.pytests import test_riley as parity

    monkeypatch.setattr(parity, "PROJECT_ROOT", tmp_path)
    monkeypatch.delenv("RILEY_FORCE_ZIG_RENDER", raising=False)
    zig_runner = [str(tmp_path / "zig")]
    full_cmd = parity._get_zig_run_cmd(zig_runner)
    full_sha = parity._compute_zig_demo_sources_sha(full_cmd)
    out = tmp_path / "out"
    quickstart_case = next(case for case in parity.DEMO_CASES if case[0] == "quickstart")
    monkeypatch.setattr(parity, "DEMO_CASES", (quickstart_case,))
    quickstart = tmp_path / quickstart_case[2] / "render.bmp"
    quickstart.parent.mkdir(parents=True)
    quickstart.touch()
    for name, files in parity._PROCEDURAL_DEMO_RENDERS.items():
        directory = out / name
        directory.mkdir()
        for file in files:
            (directory / file).touch()
    stamp = out / ".zig_demos.sha256"
    stamp.write_text(f"{full_sha}\n", encoding="utf-8")
    sphere = out / "demo01b_procedural_sphere"
    (sphere / "extra.bmp").touch()
    commands = []

    def render(label: str, cmd: list[str], env: dict[str, str]) -> None:
        commands.append(cmd)
        assert cmd[:3] == [*zig_runner, "build", "demo01b-procedural-sphere"]
        assert not sphere.exists()
        assert quickstart.is_file()
        sphere.mkdir()
        for frame in range(3):
            (sphere / f"cam0_frame{frame}_field0.bmp").touch()

    monkeypatch.setattr(parity, "_run_command", render)
    parity._refresh_zig_demo_renders(zig_runner)
    parity._refresh_zig_demo_renders(zig_runner)
    assert len(commands) == 1
    assert stamp.read_text(encoding="utf-8") == f"{full_sha}\n"


def test_cameramodel_cache_rejects_partial_matrices(tmp_path: Path) -> None:
    from riley.pytests.test_riley import _has_cameramodel_renders

    distorts = (
        "none",
        "brown_conrady",
        "brown_conrady_ext",
        "polynomial",
        "brown_conrady_polynomial",
        "brown_conrady_ext_polynomial",
    )
    psfs = (
        "pixel_box",
        "gaussian_separable",
        "gaussian_nonseparable",
        "anisotropic_separable",
        "anisotropic_rotated",
    )
    modes = ("tile_local", "global_subpx_full", "global_subpx_stripe")
    assert not _has_cameramodel_renders(tmp_path)
    for distort in distorts:
        for psf in psfs:
            for mode in modes:
                assert not _has_cameramodel_renders(tmp_path)
                path = (
                    tmp_path
                    / distort
                    / psf
                    / mode
                    / "cam0_frame0_field0.bmp"
                )
                path.parent.mkdir(parents=True, exist_ok=True)
                path.touch()
    assert _has_cameramodel_renders(tmp_path)


@pytest.mark.parametrize("channels", (1, 3))
def test_rabbit_coverage_rejects_blank_and_nearly_blank_images(
    tmp_path: Path, channels: int
) -> None:
    from riley.pytests.test_riley import _verify_rabbit_coverage

    shape = (20, 20) if channels == 1 else (20, 20, channels)
    image = np.full(shape, 128, dtype=np.uint8)
    image_path = tmp_path / "cam0_frame0_field0.bmp"
    Image.fromarray(image).save(image_path)
    with pytest.raises(AssertionError, match="rabbit foreground coverage"):
        _verify_rabbit_coverage(tmp_path)

    image[0, 0] = 0
    Image.fromarray(image).save(image_path)
    with pytest.raises(AssertionError, match="rabbit foreground coverage"):
        _verify_rabbit_coverage(tmp_path)

    image[5:15, 5:15] = 0
    Image.fromarray(image).save(image_path)
    _verify_rabbit_coverage(tmp_path)


def test_rabbit_coverage_rejects_missing_images(tmp_path: Path) -> None:
    from riley.pytests.test_riley import _verify_rabbit_coverage

    with pytest.raises(AssertionError, match="no rabbit renders"):
        _verify_rabbit_coverage(tmp_path)
