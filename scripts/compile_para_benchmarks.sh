#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"

buildconfig_path="${repo_root}/src/zraster/zig/buildconfig.zig"
buildconfig_backup="$(mktemp)"
bench_names=(
    "bench_dicuq"
    "bench_fullraster"
    "bench_geom"
    "bench_sphere2000"
    "bench_sphere2000zoom"
)

restore_buildconfig() {
    if [[ -f "${buildconfig_backup}" ]]; then
        cp "${buildconfig_backup}" "${buildconfig_path}"
        rm -f "${buildconfig_backup}"
    fi
}

trap restore_buildconfig EXIT

cp "${buildconfig_path}" "${buildconfig_backup}"
mkdir -p "${repo_root}/bin"

set_simd_mode() {
    local simd_mode="$1"

    python3 - <<'PY' "${buildconfig_path}" "${simd_mode}"
import pathlib
import re
import sys

buildconfig_path = pathlib.Path(sys.argv[1])
simd_mode = sys.argv[2]
text = buildconfig_path.read_text()
pattern = re.compile(
    r"(^\s*simd:\s*SimdMode\s*=\s*)\.(on|off)(,\s*$)",
    re.MULTILINE,
)
text_updated, replace_count = pattern.subn(
    r"\1." + simd_mode + r"\3",
    text,
    count=1,
)
if replace_count != 1:
    raise SystemExit("Failed to update buildconfig simd mode.")
buildconfig_path.write_text(text_updated)
PY
}

compile_mode_parallel() {
    local simd_mode="$1"
    local suffix="$2"
    local pids=()
    local bench_name

    set_simd_mode "${simd_mode}"

    for bench_name in "${bench_names[@]}"; do
        echo "Compiling ${bench_name}_${suffix}..."
        zig build-exe \
            -lc \
            -O ReleaseFast \
            "${repo_root}/src/${bench_name}.zig" \
            -femit-bin="${repo_root}/bin/${bench_name}_${suffix}" &
        pids+=("$!")
    done

    local status=0
    local pid
    for pid in "${pids[@]}"; do
        if ! wait "${pid}"; then
            status=1
        fi
    done

    if [[ "${status}" -ne 0 ]]; then
        echo "One or more ${suffix} benchmark compilations failed." >&2
        return "${status}"
    fi
}

compile_mode_parallel "off" "scalar"
compile_mode_parallel "on" "simd"

echo "Benchmark executables written to ${repo_root}/bin/"
