"""Select the Zig toolchain used for packaging and repo parity renders."""

from importlib.util import find_spec
import shutil
import subprocess
import sys
import sysconfig


REQUIRED_ZIG_VERSION = "0.16.0"


class ZigUnavailableError(RuntimeError):
    """Neither PATH nor ziglang provides the pinned compiler."""


def select_zig_runner() -> list[str]:
    """Prefer a matching PATH compiler, then try the interpreter's ziglang."""
    path_zig = shutil.which("zig")
    candidates = [[path_zig]] if path_zig else []
    candidates.append([sys.executable, "-m", "ziglang"])
    details = [] if path_zig else ["zig not found on PATH"]
    failed_probe = None
    for runner in candidates:
        if runner[-1] == "ziglang" and find_spec("ziglang") is None:
            details.append("ziglang is not installed")
            continue
        try:
            version = subprocess.check_output(
                runner + ["version"],
                text=True,
                stderr=subprocess.STDOUT,
                timeout=10,
            ).strip()

        except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired) as exc:
            failed_probe = exc
            details.append(f"{' '.join(runner)}: {exc}")
        else:
            if version == REQUIRED_ZIG_VERSION:
                return runner
            details.append(f"{' '.join(runner)}: version {version!r}")

    message = (
        f"Riley requires Zig {REQUIRED_ZIG_VERSION}. "
        f"Install ziglang=={REQUIRED_ZIG_VERSION} in the Python environment "
        "or put that Zig version on PATH. " + "; ".join(details)
    )
    if failed_probe is not None:
        raise RuntimeError(message) from failed_probe
    raise ZigUnavailableError(message)


def get_windows_target_triple() -> str:
    """Return the Zig target matching the Python interpreter's platform."""
    platform_tag = sysconfig.get_platform().lower()
    if platform_tag == "win32":
        return "x86-windows-msvc"
    if platform_tag in ("win-amd64", "win_amd64"):
        return "x86_64-windows-msvc"
    if platform_tag in ("win-arm64", "win_arm64"):
        return "aarch64-windows-msvc"

    raise RuntimeError(
        f"Unsupported Windows Python platform for Zig build: {platform_tag}"
    )
