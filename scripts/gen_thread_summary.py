import os
import re
import statistics

def parse_md(file_path):
    results = {}
    with open(file_path, 'r') as f:
        lines = f.readlines()
    
    # Simple regex to find case name and relevant columns
    # | Case | ... | MPx/s | ... | MElems/s | ... |
    # Column indices vary, so we find them from the header
    header_idx = -1
    for i, line in enumerate(lines):
        if '| Case' in line:
            header_idx = i
            break
            
    if header_idx == -1: return results

    headers = [h.strip() for h in lines[header_idx].split('|')]
    mpx_col = -1
    melem_col = -1
    for i, h in enumerate(headers):
        if 'MPx/s' in h: mpx_col = i
        if 'MElems/s' in h: melem_col = i
            
    for line in lines[header_idx+2:]:
        if '|' not in line: continue
        cols = [c.strip() for c in line.split('|')]
        if len(cols) < max(mpx_col, melem_col): continue
        
        case_name = cols[1]
        try:
            mpx = float(cols[mpx_col])
            melem = float(cols[melem_col])
            results[case_name] = {'mpx': mpx, 'melem': melem}
        except ValueError:
            continue
            
    return results

def aggregate_bench(bench_name):
    base_path = f'perf/threading_v0/{bench_name}'
    if not os.path.exists(base_path): return None
    
    threads = ['t1', 't2', 't4', 't8']
    summary = {} # case -> {t1: avg, t2: avg, ...}
    
    for t in threads:
        t_path = os.path.join(base_path, t)
        if not os.path.exists(t_path): continue
        
        case_runs = {} # case -> [val1, val2, ...]
        files = [f for f in os.listdir(t_path) if f.endswith('.md')]
        for f in files:
            run_data = parse_md(os.path.join(t_path, f))
            for case, data in run_data.items():
                if case not in case_runs: case_runs[case] = {'mpx': [], 'melem': []}
                case_runs[case]['mpx'].append(data['mpx'])
                case_runs[case]['melem'].append(data['melem'])
        
        for case, runs in case_runs.items():
            if case not in summary: summary[case] = {}
            summary[case][t] = {
                'mpx': statistics.mean(runs['mpx']) if runs['mpx'] else 0,
                'melem': statistics.mean(runs['melem']) if runs['melem'] else 0
            }
            
    return summary

def write_summary(bench_name, metric, cases_to_include=None):
    data = aggregate_bench(bench_name)
    if not data: return
    
    output_file = f'perf/threading_v0/{bench_name}_{metric}_summary.md'
    metric_label = "MPx/s" if metric == 'mpx' else "MElem/s"
    
    with open(output_file, 'w') as f:
        f.write(f'# {bench_name.capitalize()} {metric_label} Scaling Summary\n\n')
        f.write('| Case | T1 (Base) | T2 | Scaling T2 | T4 | Scaling T4 | T8 | Scaling T8 |\n')
        f.write('| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |\n')
        
        sorted_cases = sorted(data.keys())
        for case in sorted_cases:
            if cases_to_include and case not in cases_to_include: continue
            
            row = [case]
            t1_val = data[case].get('t1', {}).get(metric, 0)
            row.append(f'{t1_val:.2f}')
            
            for t in ['t2', 't4', 't8']:
                val = data[case].get(t, {}).get(metric, 0)
                scaling = val / t1_val if t1_val > 0 else 0
                row.append(f'{val:.2f}')
                row.append(f'{scaling:.2f}x')
            
            f.write('| ' + ' | '.join(row) + ' |\n')

# Main execution logic can be added here or run as a standalone script
if __name__ == "__main__":
    # Summaries requested:
    # 1. fullraster MPx/s
    # 2. sphere2000 MPx/s
    # 3. geom MElem/s
    # 4. sphere2000 MElem/s
    write_summary('fullraster', 'mpx')
    write_summary('sphere2000', 'mpx')
    write_summary('geom', 'melem')
    write_summary('sphere2000', 'melem')
