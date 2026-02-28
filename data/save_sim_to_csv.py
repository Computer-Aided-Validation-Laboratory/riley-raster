from pathlib import Path
import numpy as np
import pyvale as pyv
import mooseherder as mh
import imagebenchmarks as ib

def main() -> None:
    sim_path = ib.get_sim_path()

    #sim_file = sim_path / "cylinder_m1_out.e"
    sim_file = sim_path / ""

    sim_data = mh.ExodusReader.read_all_sim_data(sim_file)

    mesh_world = pyv.create_render_mesh(sim_data,
                                        ib.const.RENDER_FIELD,
                                        ib.const.SPAT_DIMS,
                                        ib.const.DISP_COMPONENTS)

    save_path = Path.home() / "zig-learn" / "rasteriser" / "data"

    print(80*"-")
    print(f"{mesh_world.coords.shape=}")
    print(f"{mesh_world.connectivity.shape=}")
    print(f"{mesh_world.fields_render.shape=}")
    print(80*"-")

    np.savetxt(save_path/'coords.csv',mesh_world.coords, delimiter=',')
    np.savetxt(save_path/'connectivity.csv',mesh_world.connectivity, delimiter=',')
    np.savetxt(save_path/'field_disp_x.csv',mesh_world.fields_disp[:,:,0], delimiter=',')
    np.savetxt(save_path/'field_disp_y.csv',mesh_world.fields_disp[:,:,1], delimiter=',')
    np.savetxt(save_path/'field_disp_z.csv',mesh_world.fields_disp[:,:,2], delimiter=',')

    num_frames = mesh_world.fields_disp.shape[1]
    for ff in range(num_frames):
        save_file = save_path / f"field_disp_frame{ff}.csv"
        np.savetxt(save_file,mesh_world.fields_disp[:,ff,:],delimiter=",")

if __name__ == "__main__":
    main()