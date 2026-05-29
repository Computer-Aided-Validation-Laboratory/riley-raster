import numpy as np
from pathlib import Path
import gendata

def main():
    base_dir = "data/simple"
    U_RANGE = (0.4, 0.6)
    V_RANGE = (0.4, 0.6)
    
    cases = [
        "tri3_twoelems", "tri6_twoelems", 
        "quad4_twoelems", "quad8_twoelems", "quad9_twoelems"
    ]
    
    for case in cases:
        case_dir = Path(base_dir) / case
        if not case_dir.exists():
            continue
        coords = np.loadtxt(case_dir / "coords.csv", delimiter=",")
        uvs = gendata.compute_uvs(coords, U_RANGE, V_RANGE)
        gendata.save_uvs(base_dir, case, uvs)
        print(f"Generated uvs.csv for {case}")

if __name__ == "__main__":
    main()
