import numpy as np
from pathlib import Path
from proj_uvs import compute_uvs

def main():
    # User Configurable Parameters
    U_RANGE = (0.4, 0.6)
    V_RANGE = (0.4, 0.6)
    
    cases = ["tri3_single", "tri6_single", "quad4_single", "quad8_single", "quad9_single"]
    
    base_dir = Path("data-simple")
    for case in cases:
        case_dir = base_dir / case
        if not case_dir.exists():
            print(f"Skipping {case}, directory not found.")
            continue
        
        coords = np.loadtxt(case_dir / "coords.csv", delimiter=",")
        uvs = compute_uvs(coords, U_RANGE, V_RANGE)
        np.savetxt(case_dir / "uvs.csv", uvs, delimiter=",")
        print(f"Generated uvs.csv for {case}")

if __name__ == "__main__":
    main()
