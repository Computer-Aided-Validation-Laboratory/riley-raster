import os
import csv

def check_winding(dir_path):
    coords_path = os.path.join(dir_path, "coords.csv")
    connectivity_path = os.path.join(dir_path, "connectivity.csv")
    
    if not os.path.exists(coords_path) or not os.path.exists(connectivity_path):
        return None
    
    coords = []
    with open(coords_path, 'r') as f:
        reader = csv.reader(f)
        for row in reader:
            if row:
                coords.append([float(x) for x in row])
                
    connectivity = []
    with open(connectivity_path, 'r') as f:
        reader = csv.reader(f)
        for row in reader:
            if row:
                connectivity.append([int(x) for x in row])
                
    windings = []
    for i, elem in enumerate(connectivity):
        # Use first three vertices to determine winding
        v0 = coords[elem[0]]
        v1 = coords[elem[1]]
        v2 = coords[elem[2]]
        
        # Signed area (2D cross product of v01 and v02)
        area = (v1[0] - v0[0]) * (v2[1] - v0[1]) - (v1[1] - v0[1]) * (v2[0] - v0[0])
        
        if dir_path == "data-simple/tri3_twoelems" and i == 0:
            print(f"DEBUG {dir_path} elem 0:")
            print(f"  v0: {v0}")
            print(f"  v1: {v1}")
            print(f"  v2: {v2}")
            print(f"  area: {area}")

        if area > 1e-10:
            windings.append("CCW")
        elif area < -1e-10:
            windings.append("CW")
        else:
            windings.append("Collinear")
            
    return windings

dirs = [
    "data-simple/tri3_twoelems", "data-simple/quad8_twoelems", "data-simple/quad4_twoelems",
    "data-simple/tri6_fullscreen", "data-simple/tri3_single", "data-simple/tri6_twoelems",
    "data-simple/quad4_fullscreen", "data-simple/quad4_single", "data-simple/quad8_fullscreen",
    "data-simple/quad9_fullscreen", "data-simple/tri3_fullscreen", "data-simple/quad9_single",
    "data-simple/quad9_twoelems", "data-simple/quad8_single", "data-simple/tri6_single",
    "data-small/tri6_fullscreen", "data-small/tri3_single", "data-small/quad4_fullscreen",
    "data-small/quad4_single", "data-small/quad8_fullscreen", "data-small/quad9_fullscreen",
    "data-small/tri3_fullscreen", "data-small/quad9_single", "data-small/quad8_single",
    "data-small/tri6_single"
]

results = {}
for d in dirs:
    res = check_winding(d)
    if res:
        results[d] = res

for d, res in results.items():
    print(f"{d}: {res}")
