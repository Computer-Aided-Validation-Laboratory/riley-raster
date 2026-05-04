# Generate Single Element Test Cases
from pathlib import Path
from dataclasses import dataclass
import numpy as np

def save_mesh(save_name: str, mesh_dict: dict[str,np.ndarray]) -> None:
    save_dir = Path.cwd() / save_name
    if not save_dir.is_dir():
        save_dir.mkdir(parents=True,exist_ok=True)

    np.savetxt(save_dir/"coords.csv",mesh_dict["coords"],delimiter=",")
    np.savetxt(save_dir/"connectivity.csv",mesh_dict["connect"],delimiter=",")
    np.savetxt(save_dir/"field_disp_x.csv",mesh_dict["disp_x"],delimiter=",")
    np.savetxt(save_dir/"field_disp_y.csv",mesh_dict["disp_y"],delimiter=",")
    np.savetxt(save_dir/"field_disp_z.csv",mesh_dict["disp_z"],delimiter=",")

def main() -> None:
    print(80*"=")
    print("Generate Single Element Render Test Meshes")
    print(80*"=")

    # Characteristic Dimensions
    L: float = 10.0 # Side length
    H: float = 10.0  # #np.sqrt(3)*L/2 # Height of equilateral triangle
    D: float = 1.0 # Midside deformation for concave/convex elements

    #---------------------------------------------------------------------------
    lin_tri = {}
    # shape = (num_nodes,coord[x,y,z])
    lin_tri["coords"] = np.array([[0,0,0],
                                  [L,0,0],
                                  [L,H,0],
                                  [0,H,0]],dtype=np.float64)
    # shape = (num_elems,nodes_per_elem)
    lin_tri["connect"] = np.array([[0,1,3],
                                   [3,1,2],],dtype=np.uintp) 

    # shape = (num_nodes, field_val)
    lin_tri["disp_x"] = np.array([[0,-1],
                                  [0,1],
                                  [0,1],
                                  [0,-1],],dtype=np.float64)
    lin_tri["disp_y"] = np.array([[0,-1],
                                  [0,-1],
                                  [0,1],
                                  [0,1]],dtype=np.float64)
    lin_tri["disp_z"] = np.array([[0,-1],
                                  [0,0],
                                  [0,1],
                                  [0,0]],dtype=np.float64)
    #---------------------------------------------------------------------------
    quad_tri = {}
    # shape = (num_nodes,coord[x,y,z])
    quad_tri["coords"] = np.array([[0,0,0],
                                   [L,0,0],
                                   [L,H,0],
                                   [0,H,0]],dtype=np.float64)
    # shape = (num_elems,nodes_per_elem)
    quad_tri["connect"] = np.array([[0,1,3,4,8,7],
                                    [3,1,2,8,5,6],],dtype=np.uintp) 

    # shape = (num_nodes, field_val)
    quad_tri["disp_x"] = np.array([[0,-1],
                                   [0,1],
                                   [0,1],
                                   [0,-1],
                                   [0,0],
                                   [0,1],
                                   [0,0],
                                   [0,-1],
                                   [0,0],],dtype=np.float64)
    quad_tri["disp_y"] = np.array([[0,-1],
                                   [0,-1],
                                   [0,1],
                                   [0,1],
                                   [0,-1],
                                   [0,0],
                                   [0,1],
                                   [0,0],
                                   [0,0],],dtype=np.float64)
    quad_tri["disp_z"] = np.array([[0,-1],
                                   [0,0],
                                   [0,1],
                                   [0,0],
                                   [0,0],
                                   [0,0],
                                   [0,0],
                                   [0,0],
                                   [0,0],],dtype=np.float64)
    #---------------------------------------------------------------------------

    print("Saving meshes...")
    save_mesh("fill_lin_tri",lin_tri)
    save_mesh("fill_quad_tri",quad_tri)

    print("Finished.")

    


if __name__ == "__main__":
    main()
