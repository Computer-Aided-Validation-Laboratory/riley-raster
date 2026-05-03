import time
from pathlib import Path
from pyvale.mooseherder import (MooseConfig,
                                MooseRunner)

# MOOSE_FILE = "thermal_rad_ex.i"
# MOOSE_PATH = Path("simulations/thermal_rad") / MOOSE_FILE

MOOSE_FILE = "stc_therm_unifhf_wrad_std_ad.i"
#MOOSE_FILE = "stc_therm_funchf_wrad_std_ad.i"
#MOOSE_FILE = "stc_therm_funchs_wrad_trans_ad.i"
MOOSE_PATH = Path("simulations/stc_pyvale") / MOOSE_FILE

# MOOSE_FILE = "dogbone3d_plas_ad_1step.i"
# MOOSE_PATH = Path("simulations/dogbone_plas") / MOOSE_FILE

# MOOSE_FILE = "temp_dep_plas_lf.i"
# MOOSE_PATH = Path("simulations/tutorials") / MOOSE_FILE

USER_DIR = Path.home()


def main() -> None:
    config = {"main_path": USER_DIR / "moose",
              "app_path": USER_DIR / "proteus",
              "app_name": "proteus-opt"}

    moose_config = MooseConfig(config)
    moose_runner = MooseRunner(moose_config)

    moose_runner.set_run_opts(n_tasks = 1,
                              n_threads = 16,
                              redirect_out = False)

    moose_start_time = time.perf_counter()
    moose_runner.run(MOOSE_PATH)
    moose_run_time = time.perf_counter() - moose_start_time

    print()
    print("="*80)
    print(f"MOOSE run time = {moose_run_time:.3f} seconds")
    print("="*80)
    print()

if __name__ == "__main__":
    main()

