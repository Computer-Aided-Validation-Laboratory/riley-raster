import subprocess
import sys
import shutil
import platform
import importlib.util
from pathlib import Path
from setuptools import setup, Extension
from setuptools.command.build_py import build_py
from setuptools.command.build_ext import build_ext
from setuptools.command.egg_info import egg_info
from Cython.Build import cythonize
import numpy

DIST_NAME = "riley-raster"
PROJECT_ROOT = Path(__file__).resolve().parent

# -----------------------------------------------------------------------------
# Platform-specific utilities


def get_platform_info() -> dict[str, str]:
    """Get platform-specific file extensions and settings."""
    system = platform.system().lower()

    if system == "windows":
        return {
            "lib_ext": ".dll",
            "lib_prefix": "",
            "runtime_lib_dir": "",  # Windows doesn't use RPATH
        }
    elif system == "darwin":  # macOS
        return {
            "lib_ext": ".dylib",
            "lib_prefix": "lib",
            "runtime_lib_dir": "@loader_path",
        }
    else:  # Linux and other Unix-like
        return {
            "lib_ext": ".so",
            "lib_prefix": "lib",
            "runtime_lib_dir": "$ORIGIN",
        }


PLATFORM_INFO = get_platform_info()


def lib_link_name(lib_name: str) -> str:
    """Return platform linkable shared library name (e.g. libc_riley.so)."""
    return f"{PLATFORM_INFO['lib_prefix']}{lib_name}{PLATFORM_INFO['lib_ext']}"


# -----------------------------------------------------------------------------
# Generated package data sync


def ensure_python_package_data() -> None:
    sync_script_path = (
        PROJECT_ROOT / "scripts" / "sync_python_package_data.py"
    )
    spec = importlib.util.spec_from_file_location(
        "riley_sync_python_package_data",
        sync_script_path,
    )
    if spec is None or spec.loader is None:
        raise RuntimeError(
            f"Could not load sync script: {sync_script_path}",
        )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.sync_python_package_data()


class RileyEggInfo(egg_info):

    def run(self):
        ensure_python_package_data()
        super().run()


class RileyBuildPy(build_py):

    def run(self):
        ensure_python_package_data()
        super().run()


# -----------------------------------------------------------------------------
# Custom Multi-Build


class MultiBuildExt(build_ext):

    def build_zig_library(self, out_dir: Path) -> None:
        """Compile the core Zig library to a stripped shared object."""
        if not out_dir.is_dir():
            out_dir.mkdir(exist_ok=True, parents=True)

        zig_source = PROJECT_ROOT / "src" / "riley" / "zig" / "c-riley.zig"
        zig_lib_output = out_dir / lib_link_name("c_riley")

        print(80 * "-")
        print("Zig: Building Shared Library")
        print(f"Source: {zig_source}")
        print(f"Target: {zig_lib_output}")
        print(80 * "-")

        system = platform.system().lower()
        is_windows = system == "windows"
        is_darwin = system == "darwin"
        zig_target_args = []
        zig_soname_args = []
        if is_windows:
            arch = platform.machine().lower()
            if arch in ("amd64", "x86_64"):
                target_triple = "x86_64-windows-msvc"
            elif arch in ("arm64", "aarch64"):
                target_triple = "aarch64-windows-msvc"
            else:
                target_triple = "i386-windows-msvc"
            zig_target_args = ["-target", target_triple]
        elif is_darwin:
            macos_arch = platform.machine().lower()
            if macos_arch in ("arm64", "aarch64"):
                macos_target_arch = "aarch64"
            elif macos_arch in ("x86_64", "amd64"):
                macos_target_arch = "x86_64"
            else:
                raise RuntimeError(
                    f"Unsupported macOS architecture for Zig build: {macos_arch}"
                )
            zig_target_args = ["-target", f"{macos_target_arch}-macos.11.0"]
            zig_soname_args = [
                "-install_name",
                f"@rpath/{lib_link_name('c_riley')}",
            ]
        else:
            zig_soname_args = [f"-fsoname={lib_link_name('c_riley')}"]

        zig_build = [
            "build-lib",
            "-dynamic",
            "-O",
            "ReleaseFast",
            "-lc",
            "-fstrip",
            *zig_soname_args,
            f"-femit-bin={zig_lib_output}",
            *zig_target_args,
            *[f"-I{d}" for d in self.include_dirs],
            str(zig_source),
        ]

        print(f"Zig build command:\nzig {' '.join(zig_build)}\n")

        try:
            subprocess.check_call(
                [sys.executable, "-m", "ziglang"] + zig_build
            )
            print("Zig build successful\n")

            if is_windows:
                # Copy import library to c_riley.lib if named c-riley.lib
                zig_lib_name_win = f"{zig_source.stem}.lib"
                zig_lib_path_win = out_dir / zig_lib_name_win
                target_lib_path_win = out_dir / "c_riley.lib"
                if (
                    zig_lib_path_win.is_file()
                    and zig_lib_path_win != target_lib_path_win
                ):
                    shutil.copy2(zig_lib_path_win, target_lib_path_win)
                    print(
                        f"Copied import library to:\n    {target_lib_path_win}"
                    )

        except subprocess.CalledProcessError as e:
            print(f"Zig build failed: {e}")
            raise

    def run(self):
        ensure_python_package_data()
        print(80 * "=")
        print("MultiBuildExt: run")
        print(80 * "=")

        build_temp_path = Path(self.build_temp)
        if not build_temp_path.is_dir():
            build_temp_path.mkdir(exist_ok=True, parents=True)

        if self.inplace:
            zig_out_dir = PROJECT_ROOT / "src" / "riley" / "cython"
        else:
            build_lib_path = Path(self.build_lib)
            if not build_lib_path.is_dir():
                build_lib_path.mkdir(exist_ok=True, parents=True)
            zig_out_dir = build_lib_path / "riley" / "cython"

        # Build Zig shared library before compiling extensions
        self.build_zig_library(zig_out_dir)

        # For editable installs via modern build frontends (PEP 660)
        src_cython_dir = PROJECT_ROOT / "src" / "riley" / "cython"
        zig_lib_name = lib_link_name("c_riley")
        src_zig_lib = src_cython_dir / zig_lib_name
        built_zig_lib = zig_out_dir / zig_lib_name
        if (
            built_zig_lib.is_file()
            and built_zig_lib != src_zig_lib
            and getattr(self, "editable_mode", False)
        ):
            shutil.copy2(built_zig_lib, src_zig_lib)

        system = platform.system().lower()
        is_windows = system == "windows"
        is_darwin = system == "darwin"
        if not is_windows:
            if PLATFORM_INFO["runtime_lib_dir"] not in self.rpath:
                self.rpath.append(PLATFORM_INFO["runtime_lib_dir"])

        zig_dir_str = str(zig_out_dir.resolve())
        if zig_dir_str not in self.library_dirs:
            self.library_dirs.append(zig_dir_str)

        for ee in self.extensions:
            if zig_dir_str not in ee.library_dirs:
                ee.library_dirs.append(zig_dir_str)
            if not is_windows:
                if (
                    PLATFORM_INFO["runtime_lib_dir"]
                    not in ee.runtime_library_dirs
                ):
                    ee.runtime_library_dirs.append(
                        PLATFORM_INFO["runtime_lib_dir"]
                    )
            if is_darwin:
                if "-Wl,-rpath,@loader_path" not in ee.extra_link_args:
                    ee.extra_link_args.append("-Wl,-rpath,@loader_path")

        super().run()


# -----------------------------------------------------------------------------
# Extensions

H_DIRS = [
    numpy.get_include(),
    str(PROJECT_ROOT / "src"),
    str(PROJECT_ROOT / "src" / "riley" / "cython"),
    str(PROJECT_ROOT / "src" / "riley" / "zig"),
]

system = platform.system().lower()
is_windows = system == "windows"
is_darwin = system == "darwin"

# Configure compiler flags based on OS to support both MSVC and GCC/Clang
if is_windows:
    cython_compile_args = ["/fp:fast", "/O2"]
    cython_link_args = ["msvcrt.lib", "ucrt.lib", "vcruntime.lib", "kernel32.lib",]
    runtime_lib_dirs = []
elif is_darwin:
    cython_compile_args = ["-ffast-math", "-O3"]
    cython_link_args = ["-Wl,-rpath,@loader_path"]
    runtime_lib_dirs = [PLATFORM_INFO["runtime_lib_dir"]]
else:
    cython_compile_args = ["-ffast-math", "-O3"]
    cython_link_args = []
    runtime_lib_dirs = [PLATFORM_INFO["runtime_lib_dir"]]

# Cython extension linking Zig shared library
ext_cython = Extension(
    name="riley.cython.riley",
    sources=["src/riley/cython/riley.py"],
    include_dirs=H_DIRS,
    libraries=["c_riley"],
    library_dirs=[],  # populated by MultiBuildExt.run()
    runtime_library_dirs=runtime_lib_dirs,
    extra_compile_args=cython_compile_args,
    extra_link_args=cython_link_args,
)

ext_modules = cythonize(ext_cython, annotate=True)


# -----------------------------------------------------------------------------
# Setup

setup(
    name=DIST_NAME,
    ext_modules=ext_modules,
    cmdclass={
        "build_ext": MultiBuildExt,
        "build_py": RileyBuildPy,
        "egg_info": RileyEggInfo,
    },
    zip_safe=False,
    package_data={
        "riley.cython": [f"*{PLATFORM_INFO['lib_ext']}"],
    },
    include_package_data=True,
)
