import numpy as np
from pathlib import Path
from proj_uvs import compute_uvs

def main():
    # User Configurable Parameters
    U_RANGE = (0.45, 0.55)
    V_RANGE = (0.45, 0.55)
    
    cases = ["tri3_fullscreen", "tri6_fullscreen", "quad4_fullscreen", "quad8_fullscreen", "quad9_fullscreen"]
    
    base_dir = Path("data-small")
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
