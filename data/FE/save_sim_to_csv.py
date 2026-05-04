from pathlib import Path
import numpy as np
import pyvale.sensorsim as sens
import pyvale.mooseherder as mh

def main() -> None:
    num_meshes = 8
    for mm in range(1,num_meshes):
        mesh_num = mm
        sim_name = f"platewithhole3d_{mesh_num}"

        sim_path = Path.cwd()
        sim_file = sim_path / (f"{sim_name}.e")

        save_path = Path.cwd() / sim_name
        if not save_path.is_dir():
            save_path.mkdir(parents=True, exist_ok=True)

        sim_data = mh.ExodusLoader(sim_file).load_all_sim_data()
        mesh_world = sens.extract_surf_mesh(sim_data)

        (num_coords,_) = mesh_world.coords.shape
        uvs = np.zeros((num_coords,2),dtype=np.float64)

        (u_min,u_max) = (0.1,0.9)
        d_u = u_max - u_min
        AR = 2462.0/2056.0 # X/Y
        v_min = (1 - d_u / AR)/2
        v_max = 1 - v_min
        d_v = v_max - v_min

        x_max = np.max(mesh_world.coords[:,0])
        x_min = np.min(mesh_world.coords[:,0])
        u_slope = (u_max - u_min) / (x_max - x_min)
        u_int = u_min - u_slope*x_min

        y_max = np.max(mesh_world.coords[:,1])
        y_min = np.min(mesh_world.coords[:,1])
        v_slope = (v_max - v_min) / (y_max - y_min)
        v_int = v_min - v_slope*y_min

        uvs[:,0] = u_slope*mesh_world.coords[:,0] + u_int
        uvs[:,1] = v_slope*mesh_world.coords[:,0] + v_int


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
                    mesh_world.connect['connect1'].T, delimiter=',')
        np.savetxt(save_path/'field_disp_x.csv',
                    mesh_world.node_vars['disp_x'], delimiter=',')
        np.savetxt(save_path/'field_disp_y.csv',
                    mesh_world.node_vars['disp_y'], delimiter=',')
        np.savetxt(save_path/'field_disp_z.csv',
                    mesh_world.node_vars['disp_z'], delimiter=',')
        np.savetxt(save_path/'uvs.csv',uvs, delimiter=',')
        
if __name__ == "__main__":
    main()
