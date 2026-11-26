"""Check current-wheel CLI coverage and strict procedural BMP validation."""

import os
from pathlib import Path
import shutil
import subprocess
import sys
import venv

from PIL import Image
import pytest

from scripts import smoke_procedural_demos


PROCEDURAL_DEMOS = tuple(smoke_procedural_demos.PROCEDURAL_CASES)
OTHER_DEMOS = ("demo03_fixture", "demo03_fixture_from_exodus")
ALL_DEMOS = (*PROCEDURAL_DEMOS, *OTHER_DEMOS)
SWAPPED_DEMOS = (*ALL_DEMOS[:-1], "demo99_replacement")


def write_demo_package(path, demos):
    path.mkdir(parents=True)
    for name in (*demos, "demo_rabbits_common", "_procedural", "__init__"):
        (path / f"{name}.py").touch()


@pytest.fixture
def smoke_install(tmp_path):
    env_dir = tmp_path / "venv"
    venv.create(env_dir)
    python = env_dir / ("Scripts/python.exe" if os.name == "nt" else "bin/python")
    site_packages = Path(subprocess.check_output(
        [str(python), "-I", "-c", "import sysconfig; print(sysconfig.get_path('purelib'))"],
        text=True,
    ).strip())

    scripts = tmp_path / "checkout" / "scripts"
    scripts.mkdir(parents=True)
    shutil.copy(Path(__file__).resolve().parents[1] / "smoke_pypi_demos.py", scripts)
    (scripts.parent / "pyproject.toml").write_text('[project]\nversion = "3.2.1"\n')
    write_demo_package(scripts.parent / "src" / "riley" / "pydemos", ALL_DEMOS)
    (scripts / "smoke_procedural_demos.py").write_text(f"""
import subprocess
import sys
PROCEDURAL_CASES = dict.fromkeys({PROCEDURAL_DEMOS!r})

def run_procedural_demo(demo, work_dir):
    subprocess.run([sys.executable, '-I', '-m', 'riley', demo, '--strict'],
                   cwd=work_dir, check=True)
""")

    def run(*flags, installed="3.2.1", demos=ALL_DEMOS, shipped=ALL_DEMOS,
            procedural=PROCEDURAL_DEMOS, targets=None, fail=None, record="wheel"):
        external = record in ("editable", "mismatched")
        package_dir = tmp_path / "external" if external else site_packages
        package = package_dir / "riley"
        write_demo_package(package / "pydemos", shipped)
        (package / "__init__.py").touch()
        registry = {name: f"riley.pydemos.{name}" for name in demos}
        registry.update(targets or {})
        (package / "__main__.py").write_text(f"""
from pathlib import Path
import sys
_DEMO_FUNCS = {registry!r}
_PROCEDURAL_DEMOS = set({procedural!r})
if __name__ == '__main__':
    demo, *args = sys.argv[1:]
    assert demo in _DEMO_FUNCS
    assert args == (['--strict'] if demo in _PROCEDURAL_DEMOS else [])
    assert Path.cwd().name.startswith('riley-wheel-smoke-')
    if demo == {fail!r}:
        raise SystemExit('failed demo: ' + demo)
    print('ran ' + demo)
""")

        metadata = site_packages / f"riley_raster-{installed}.dist-info"
        metadata.mkdir()
        (metadata / "METADATA").write_text(f"Name: riley-raster\nVersion: {installed}\n")
        if external:
            (site_packages / "external.pth").write_text(f"{package_dir}\n")
        if record == "editable":
            (metadata / "RECORD").write_text("external.pth,,\n")
        elif record in ("wheel", "mismatched"):
            (metadata / "RECORD").write_text("riley/__init__.py,,\n")
        elif record == "missing":
            # Distribution.files can fall back to SOURCES.txt without a wheel RECORD.
            (metadata / "SOURCES.txt").write_text("riley/__init__.py\n")
        return subprocess.run(
            [str(python), "-I", str(scripts / "smoke_pypi_demos.py"), *flags],
            cwd=tmp_path,
            capture_output=True,
            text=True,
            timeout=15,
        )

    return run


@pytest.mark.parametrize(("flags", "demos"), [((), ALL_DEMOS), (("--procedural-only",), PROCEDURAL_DEMOS)])
def test_runs_registered_cli_demos_once(smoke_install, flags, demos):
    result = smoke_install(*flags)
    assert result.returncode == 0, result.stderr
    assert [line for line in result.stdout.splitlines() if line.startswith("ran ")] == [
        f"ran {demo}" for demo in sorted(demos)
    ]


def test_rejects_non_current_wheel(smoke_install):
    result = smoke_install(installed="3.2.0")
    assert result.returncode != 0
    assert "Expected riley-raster 3.2.1, got 3.2.0" in result.stderr
    assert "Running python -m riley" not in result.stdout


@pytest.mark.parametrize(("record", "message"), [
    ("editable", "which is not listed in the installed riley-raster RECORD"),
    ("mismatched", "which is not listed in the installed riley-raster RECORD"),
    ("missing", "Installed riley-raster has a missing or empty RECORD"),
])
def test_requires_import_from_wheel_record(smoke_install, record, message):
    result = smoke_install(record=record)
    assert result.returncode != 0
    assert message in result.stderr
    assert "Running python -m riley" not in result.stdout


def test_rejects_incomplete_registry(smoke_install):
    result = smoke_install(demos=ALL_DEMOS[:-1])
    assert result.returncode != 0
    assert "Installed CLI registry does not match checkout" in result.stderr
    assert f"missing {[ALL_DEMOS[-1]]}, unexpected []" in result.stderr
    assert "Running python -m riley" not in result.stdout


@pytest.mark.parametrize(("demos", "shipped", "label"), [
    (SWAPPED_DEMOS, ALL_DEMOS, "Installed CLI registry"),
    (ALL_DEMOS, SWAPPED_DEMOS, "Installed demo modules"),
    (SWAPPED_DEMOS, SWAPPED_DEMOS, "Installed CLI registry"),
])
def test_rejects_same_count_demo_replacement(smoke_install, demos, shipped, label):
    result = smoke_install("--procedural-only", demos=demos, shipped=shipped)
    assert result.returncode != 0
    assert f"{label} does not match checkout" in result.stderr
    assert f"missing {[ALL_DEMOS[-1]]}, unexpected {[SWAPPED_DEMOS[-1]]}" in result.stderr
    assert "Running python -m riley" not in result.stdout


def test_rejects_swapped_cli_targets(smoke_install):
    first, second = OTHER_DEMOS
    result = smoke_install(targets={first: f"riley.pydemos.{second}", second: f"riley.pydemos.{first}"})
    assert result.returncode != 0
    assert f"Installed CLI demos target the wrong modules: {sorted(OTHER_DEMOS)}" in result.stderr
    assert "Running python -m riley" not in result.stdout


@pytest.mark.parametrize(("demos", "procedural"), [
    (ALL_DEMOS, PROCEDURAL_DEMOS[:-1]),
    ((*ALL_DEMOS[1:], "demo_replacing_procedural"), PROCEDURAL_DEMOS),
])
def test_rejects_mismatched_procedural_registries(smoke_install, demos, procedural):
    result = smoke_install(demos=demos, procedural=procedural)
    assert result.returncode != 0
    assert "do not match the installed CLI procedural demos" in result.stderr
    assert "Running python -m riley" not in result.stdout


@pytest.mark.parametrize("demo", [PROCEDURAL_DEMOS[0], OTHER_DEMOS[-1]])
def test_demo_failure_fails_smoke(smoke_install, demo):
    result = smoke_install(fail=demo)
    assert result.returncode != 0
    assert f"failed demo: {demo}" in result.stderr


@pytest.mark.parametrize(("defect", "message"), [
    (None, None),
    ("missing", "expected ['disk.bmp'], got []"),
    ("extra", "got ['disk.bmp', 'nested/unexpected.BMP']"),
    ("format", "got PNG"),
    ("dimensions", "got BMP at (64, 48)"),
    ("uniform", "rendered image is uniform"),
])
def test_procedural_smoke_validates_rendered_bmps(monkeypatch, tmp_path, defect, message):
    demo = "demo00b_procedural_quickstart"
    output = tmp_path / demo

    def render(command, *, cwd, check, timeout):
        assert command == [
            sys.executable, "-I", "-m", "riley", demo, "--output", str(output),
            "--width", "128", "--height", "96",
        ]
        assert cwd == tmp_path and check and timeout == 60
        output.mkdir()
        if defect == "missing":
            return
        size = (64, 48) if defect == "dimensions" else (128, 96)
        with Image.new("L", size) as image:
            if defect != "uniform":
                image.putpixel((0, 0), 255)
            image.save(output / "disk.bmp", format="PNG" if defect == "format" else "BMP")
            if defect == "extra":
                (output / "nested").mkdir()
                image.save(output / "nested" / "unexpected.BMP")

    monkeypatch.setattr(smoke_procedural_demos.subprocess, "run", render)
    if message is None:
        smoke_procedural_demos.run_procedural_demo(demo, tmp_path)
    else:
        with pytest.raises(RuntimeError) as error:
            smoke_procedural_demos.run_procedural_demo(demo, tmp_path)
        assert message in str(error.value)
