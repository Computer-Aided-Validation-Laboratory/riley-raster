import subprocess
import re
import statistics
import sys

def run_bench(mode):
    cmd = ["zig", "run", "-lc"]
    if mode == "ReleaseSafe":
        cmd.append("-O")
        cmd.append("ReleaseSafe")
    elif mode == "ReleaseFast":
        cmd.append("-O")
        cmd.append("ReleaseFast")
    
    cmd.append("src/bench_fullscreen.zig")
    
    print(f"Running {mode} benchmark...")
    try:
        # Increase timeout if it's stalling, but let's hope it finishes
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=600)
        if result.returncode != 0:
            print(f"Error running {mode}: {result.stderr}")
            return None
        return result.stderr # Reports go to stderr
    except subprocess.TimeoutExpired:
        print(f"Timeout expired for {mode}")
        return None

def parse_output(output):
    # Regex to find MOps/second = X.XX
    mops_pattern = re.compile(r"MOps/second\s+=\s+(\d+\.\d+)")
    matches = mops_pattern.findall(output)
    if not matches:
        return []
    return [float(m) for m in matches]

def main():
    modes = ["Debug", "ReleaseSafe", "ReleaseFast"]
    runs = 5
    
    results = {}
    
    # Mesh types and shading types in order from bench_fullscreen.zig
    # tri3 (flat, tex), tri6 (flat, tex), quad4ibi (flat, tex), quad8 (flat, tex), quad9 (flat, tex)
    case_names = [
        "tri3_flat", "tri3_tex",
        "tri6_flat", "tri6_tex",
        "quad4ibi_flat", "quad4ibi_tex",
        "quad8_flat", "quad8_tex",
        "quad9_flat", "quad9_tex"
    ]

    for mode in modes:
        mode_data = [[] for _ in range(len(case_names))]
        for i in range(runs):
            print(f"Run {i+1}/{runs} for {mode}...")
            output = run_bench(mode)
            if output:
                mops = parse_output(output)
                # We expect 10 values (5 elements * 2 shading)
                # But runTestInternal might call it more than once? 
                # In bench_fullscreen.zig it calls it twice per mesh type.
                # Let's check how many matches we got.
                if len(mops) >= 10:
                    for j in range(10):
                        mode_data[j].append(mops[j])
            else:
                print(f"Skipping run {i+1} due to error/timeout")
        
        averages = []
        for j in range(len(case_names)):
            if mode_data[j]:
                averages.append(statistics.mean(mode_data[j]))
            else:
                averages.append(0.0)
        results[mode] = averages

    # Write to bench_runtimeinterp.md
    with open("bench_runtimeinterp.md", "w") as f:
        f.write("# Runtime Interpolation Benchmark (De-monomorphized)\n\n")
        f.write("| Case | Debug (MOps/s) | ReleaseSafe (MOps/s) | ReleaseFast (MOps/s) |\n")
        f.write("| :--- | :---: | :---: | :---: |\n")
        for j, name in enumerate(case_names):
            d = results["Debug"][j]
            rs = results["ReleaseSafe"][j]
            rf = results["ReleaseFast"][j]
            f.write(f"| {name} | {d:.2f} | {rs:.2f} | {rf:.2f} |\n")

if __name__ == "__main__":
    main()
