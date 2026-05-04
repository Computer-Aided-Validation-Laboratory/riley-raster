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
    H: float = np.sqrt(3)*L/2 # Height of equilateral triangle
    D: float = 1.0 # Midside deformation for concave/convex elements

    #---------------------------------------------------------------------------
    lin_tri = {}
    # shape = (num_nodes,coord[x,y,z])
    lin_tri["coords"] = np.array([[0,0,0],
                               [L,0,0],
                               [L/2,H,0],],dtype=np.float64)
    # shape = (num_elems,nodes_per_elem)
    lin_tri["connect"] = np.array([[0,1,2]],dtype=np.uintp) 

    # shape = (num_nodes, field_val)
    lin_tri["disp_x"] = np.array([[0,-1],
                                  [0,1],
                                  [0,-1]],dtype=np.float64)
    lin_tri["disp_y"] = np.array([[0,-1],
                                  [0,-1],
                                  [0,1]],dtype=np.float64)
    lin_tri["disp_z"] = np.array([[0,1],
                                  [0,-1],
                                  [0,-1]],dtype=np.float64)
    #---------------------------------------------------------------------------
    quad_tri = {}
    # shape = (num_nodes,coord[x,y,z])
    quad_tri["coords"] = np.array([[0,0,0],
                                  [L,0,0],
                                  [L/2,H,0],
                                  [L/2,0,0],
                                  [3*L/4,H/2,0],
                                  [L/4,H/2,0]],dtype=np.float64)

    # shape = (num_elems,nodes_per_elem)
    quad_tri["connect"] = np.array([[0,1,2,3,4,5]],dtype=np.uintp) 

    # shape = (num_nodes, field_val)
    quad_tri["disp_x"] = np.array([[0,-1],
                                   [0,1],
                                   [0,-1],
                                   [0,0],
                                   [0,0],
                                   [0,0]],dtype=np.float64)
    quad_tri["disp_y"] = np.array([[0,-1],
                                   [0,-1],
                                   [0,1],
                                   [0,0],
                                   [0,0],
                                   [0,0]],dtype=np.float64)
    quad_tri["disp_z"] = np.array([[0,1],
                                   [0,-1],
                                   [0,-1],
                                   [0,0],
                                   [0,0],
                                   [0,0]],dtype=np.float64)
    #---------------------------------------------------------------------------
    # Concave = midside nodes inwards
    quad_tri_conc = {}
    # shape = (num_nodes,coord[x,y,z])
    quad_tri_conc["coords"] = np.array([[0,0,0],
                                  [L,0,0],
                                  [L/2,H,0],
                                  [L/2,D,0],
                                  [3*L/4-D,H/2-D,0],
                                  [L/4+D,H/2-D,0]],dtype=np.float64)

    # shape = (num_elems,nodes_per_elem)
    quad_tri_conc["connect"] = np.array([[0,1,2,3,4,5]],dtype=np.uintp) 

    # shape = (num_nodes, field_val)
    quad_tri_conc["disp_x"] = np.array([[0,-1],
                                   [0,1],
                                   [0,-1],
                                   [0,0],
                                   [0,0],
                                   [0,0]],dtype=np.float64)
    quad_tri_conc["disp_y"] = np.array([[0,-1],
                                   [0,-1],
                                   [0,1],
                                   [0,0],
                                   [0,0],
                                   [0,0]],dtype=np.float64)
    quad_tri_conc["disp_z"] = np.array([[0,1],
                                   [0,-1],
                                   [0,-1],
                                   [0,0],
                                   [0,0],
                                   [0,0]],dtype=np.float64)

    #---------------------------------------------------------------------------
    # Convex = midside nodes outwards
    quad_tri_conv = {}
    # shape = (num_nodes,coord[x,y,z])
    quad_tri_conv["coords"] = np.array([[0,0,0],
                                  [L,0,0],
                                  [L/2,H,0],
                                  [L/2,-D,0],
                                  [3*L/4+D,H/2+D,0],
                                  [L/4-D,H/2+D,0]],dtype=np.float64)

    # shape = (num_elems,nodes_per_elem)
    quad_tri_conv["connect"] = np.array([[0,1,2,3,4,5]],dtype=np.uintp) 

    # shape = (num_nodes, field_val)
    quad_tri_conv["disp_x"] = np.array([[0,-1],
                                   [0,1],
                                   [0,-1],
                                   [0,0],
                                   [0,0],
                                   [0,0]],dtype=np.float64)
    quad_tri_conv["disp_y"] = np.array([[0,-1],
                                   [0,-1],
                                   [0,1],
                                   [0,0],
                                   [0,0],
                                   [0,0]],dtype=np.float64)
    quad_tri_conv["disp_z"] = np.array([[0,1],
                                   [0,-1],
                                   [0,-1],
                                   [0,0],
                                   [0,0],
                                   [0,0]],dtype=np.float64)
    #---------------------------------------------------------------------------
    # Def = Concave+Convex = midside nodes in or outwards
    # Top midsides pulled in, bottom midside pulled out.
    quad_tri_def = {}
    # shape = (num_nodes,coord[x,y,z])
    quad_tri_def["coords"] = np.array([[0,0,0],
                                  [L,0,0],
                                  [L/2,H,0],
                                  [L/2,-D,0],
                                  [3*L/4-D,H/2-D,0],
                                  [L/4+D,H/2-D,0]],dtype=np.float64)

    # shape = (num_elems,nodes_per_elem)
    quad_tri_def["connect"] = np.array([[0,1,2,3,4,5]],dtype=np.uintp) 

    # shape = (num_nodes, field_val)
    quad_tri_def["disp_x"] = np.array([[0,-1],
                                   [0,1],
                                   [0,-1],
                                   [0,0],
                                   [0,0],
                                   [0,0]],dtype=np.float64)
    quad_tri_def["disp_y"] = np.array([[0,-1],
                                   [0,-1],
                                   [0,1],
                                   [0,0],
                                   [0,0],
                                   [0,0]],dtype=np.float64)
    quad_tri_def["disp_z"] = np.array([[0,1],
                                   [0,-1],
                                   [0,-1],
                                   [0,0],
                                   [0,0],
                                   [0,0]],dtype=np.float64)
    #---------------------------------------------------------------------------

    print("Saving meshes...")
    save_mesh("lin_tri",lin_tri)
    save_mesh("quad_tri",quad_tri)
    save_mesh("quad_tri_concave",quad_tri_conc)
    save_mesh("quad_tri_convex",quad_tri_conv)
    save_mesh("quad_tri_def",quad_tri_def)


    print("Finished.")

    


if __name__ == "__main__":
    main()
