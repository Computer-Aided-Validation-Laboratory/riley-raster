from pathlib import Path
import numpy as np
import pyvale.sensorsim as sens
import pyvale.mooseherder as mh

def main() -> None:
    #---------------------------------------------------------------------------
    # NOTE: exodus connectivity starts at 1 - need to subtract 1!
    #---------------------------------------------------------------------------

    num_meshes = 7
    num_frames = 1
    for mm in range(1,num_meshes):
        mesh_num = mm
        sim_name = f"platehole3d_{mesh_num}mr_{num_frames}f"

        sim_path = Path.cwd()
        sim_file = sim_path / (f"{sim_name}.e")

        save_path = Path.cwd() / sim_name
        if not save_path.is_dir():
            save_path.mkdir(parents=True, exist_ok=True)

        sim_data = mh.ExodusLoader(sim_file).load_all_sim_data()
        mesh_world = sens.extract_surf_mesh(sim_data)

        (num_coords,_) = mesh_world.coords.shape
        uvs = np.zeros((num_coords,2),dtype=np.float64)

        x_max = np.max(mesh_world.coords[:,0])
        x_min = np.min(mesh_world.coords[:,0])
        y_max = np.max(mesh_world.coords[:,1])
        y_min = np.min(mesh_world.coords[:,1])

        dx_mesh = x_max - x_min
        dy_mesh = y_max - y_min
        mesh_AR = dx_mesh / dy_mesh

        uv_span_max = 0.8
        # Texture AR (Width/Height)
        tex_AR = 2464.0 / 2056.0 

        # To maintain square pixels: (d_u / d_v) = mesh_AR / tex_AR
        # Let R be the ratio of aspect ratios
        R = mesh_AR / tex_AR

        if R > 1:
            # Mesh is wider than texture relative to its height
            # U is the constraining dimension
            d_u = uv_span_max
            d_v = d_u / R
        else:
            # Mesh is taller than texture relative to its width
            # V is the constraining dimension
            d_v = uv_span_max
            d_u = d_v * R

        u_min = (1 - d_u) / 2
        u_max = 1 - u_min
        v_min = (1 - d_v) / 2
        v_max = 1 - v_min

        u_slope = (u_max - u_min) / (x_max - x_min)
        u_int = u_min - u_slope*x_min

        v_slope = (v_max - v_min) / (y_max - y_min)
        v_int = v_min - v_slope*y_min

        uvs[:,0] = u_slope*mesh_world.coords[:,0] + u_int
        uvs[:,1] = v_slope*mesh_world.coords[:,1] + v_int

        # Correct for exodus 1 indexed connectivity
        connect = mesh_world.connect['connect1'].T - 1

        print(80*"-")
        print(f"MESH: {sim_name}") 
        print()
        print(f"{sim_data.coords.shape=}")
        print(f"{sim_data.connect['connect1'].shape=}")
        print()
        print(f"{mesh_world.coords.shape=}")
        print(f"{mesh_world.connect['connect1'].T.shape=}")
        print(f"{mesh_world.node_vars['disp_x'].shape=}")
        print()
        print(f"{np.max(connect)=},{np.min(connect)=}")
        print()
        print(f"{np.min(mesh_world.coords,axis=0)=}")
        print(f"{np.max(mesh_world.coords,axis=0)=}")
        print()
        print(f"{u_min=},{u_max=},{v_min=},{v_max=}")
        print(f"{x_min=},{x_max=},{y_min=},{y_max=}")
        print()
        print(f"{np.min(uvs,axis=0)=}")
        print(f"{np.max(uvs,axis=0)=}")
        print(80*"-")

        np.savetxt(save_path/'coords.csv',mesh_world.coords, delimiter=',')
        np.savetxt(save_path/'connect.csv',
                    connect, delimiter=',')
        np.savetxt(save_path/'field_disp_x.csv',
                    mesh_world.node_vars['disp_x'], delimiter=',')
        np.savetxt(save_path/'field_disp_y.csv',
                    mesh_world.node_vars['disp_y'], delimiter=',')
        np.savetxt(save_path/'field_disp_z.csv',
                    mesh_world.node_vars['disp_z'], delimiter=',')
        np.savetxt(save_path/'uvs.csv',uvs, delimiter=',')
        
if __name__ == "__main__":
    main()
