"""Smoke-test the CLI demos shipped by the current Riley wheel."""

import argparse
from collections.abc import Iterable
from importlib.metadata import distribution
from pathlib import Path
from pkgutil import iter_modules
import re
import subprocess
import sys
import tempfile
import tomllib


def numbered_demos(paths: Iterable[str]) -> set[str]:
    return {
        module.name for module in iter_modules(paths)
        if not module.ispkg and re.fullmatch(r"demo[0-9]{2}[a-z]?_.+", module.name)
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--procedural-only", action="store_true", help="Only render demos with BMP checks."
    )
    args = parser.parse_args()

    script_dir = Path(__file__).resolve().parent
    checkout = script_dir.parent
    with (checkout / "pyproject.toml").open("rb") as project:
        current_version = tomllib.load(project)["project"]["version"]
    installed = distribution("riley-raster")
    installed_version = installed.version
    if installed_version != current_version:
        raise RuntimeError(f"Expected riley-raster {current_version}, got {installed_version}")
    if not installed.read_text("RECORD"):
        raise RuntimeError("Installed riley-raster has a missing or empty RECORD; install the wheel")

    import riley

    module_path = Path(riley.__file__).resolve() if riley.__file__ else None
    if module_path is None or not any(
        Path(installed.locate_file(file)).resolve() == module_path
        for file in installed.files or ()
    ):
        raise RuntimeError(
            f"Imported riley from {module_path}, which is not listed in the installed "
            "riley-raster RECORD; install the wheel and remove editable or shadowing imports"
        )

    from riley import pydemos
    from riley.__main__ import _DEMO_FUNCS, _PROCEDURAL_DEMOS

    # Isolated Python leaves the script directory off sys.path.
    sys.path.insert(0, str(script_dir))
    from smoke_procedural_demos import PROCEDURAL_CASES, run_procedural_demo

    print(f"Installed riley-raster {installed_version}: {riley.__file__}", flush=True)

    if _PROCEDURAL_DEMOS != PROCEDURAL_CASES.keys() or not _PROCEDURAL_DEMOS <= _DEMO_FUNCS.keys():
        raise RuntimeError(
            f"Procedural smoke cases {sorted(PROCEDURAL_CASES)} do not match the installed CLI "
            f"procedural demos {sorted(_PROCEDURAL_DEMOS)} and its demo registry"
        )

    expected = numbered_demos([str(checkout / "src" / "riley" / "pydemos")])
    shipped = numbered_demos(pydemos.__path__)
    for label, names in (
        ("Installed CLI registry", _DEMO_FUNCS.keys()),
        ("Installed demo modules", shipped),
    ):
        if names != expected:
            raise RuntimeError(
                f"{label} does not match checkout: missing {sorted(expected - names)}, "
                f"unexpected {sorted(names - expected)}"
            )
    wrong_targets = sorted(
        name for name, target in _DEMO_FUNCS.items() if target != f"{pydemos.__name__}.{name}"
    )
    if wrong_targets:
        raise RuntimeError(f"Installed CLI demos target the wrong modules: {wrong_targets}")

    demos = _PROCEDURAL_DEMOS if args.procedural_only else _DEMO_FUNCS
    with tempfile.TemporaryDirectory(prefix="riley-wheel-smoke-") as tmp:
        work_dir = Path(tmp)
        for demo in sorted(demos):
            print(f"Running python -m riley {demo}", flush=True)
            if demo in PROCEDURAL_CASES:
                run_procedural_demo(demo, work_dir)
            else:
                subprocess.run([sys.executable, "-I", "-m", "riley", demo], cwd=work_dir, check=True)


if __name__ == "__main__":
    main()
