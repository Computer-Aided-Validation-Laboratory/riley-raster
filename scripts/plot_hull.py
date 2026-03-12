import numpy as np
import matplotlib.pyplot as plt
import os

def plot_case(case_name):
    hull_path = f"scripts/hull-diags/{case_name}_hull.csv"
    coords_path = f"scripts/hull-diags/{case_name}_rastercoords.csv"
    
    if not os.path.exists(hull_path) or not os.path.exists(coords_path):
        print(f"Skipping {case_name}, files not found.")
        return

    # Load data
    hull_data = np.loadtxt(hull_path, delimiter=",")
    coords_data = np.loadtxt(coords_path, delimiter=",")

    plt.figure(figsize=(10, 8))
    
    N = coords_data.shape[0]
    # Plot Element Nodes and Edges
    if N == 6: # Tri6
        order = [0, 3, 1, 4, 2, 5, 0]
    elif N >= 8: # Quad8/9
        order = [0, 4, 1, 5, 2, 6, 3, 7, 0]
    
    plt.plot(coords_data[order, 0], coords_data[order, 1], 'ko-', label='Element Edges')
    plt.scatter(coords_data[:, 0], coords_data[:, 1], c='k', marker='o')
    for i in range(N):
        plt.annotate(f"n{i}", (coords_data[i, 0], coords_data[i, 1]))

    # Plot Hull
    # Hull points are stored in loop order
    hull_plot = np.vstack([hull_data, hull_data[0]]) # Close the loop
    plt.plot(hull_plot[:, 0], hull_plot[:, 1], 'bx--', label='Adaptive Hull', markersize=10, alpha=0.6)
    plt.scatter(hull_data[:, 0], hull_data[:, 1], c='b', marker='x')

    plt.title(f"Adaptive Hull Visualization: {case_name}")
    plt.xlabel("Raster X")
    plt.ylabel("Raster Y (Flipped)")
    plt.gca().invert_yaxis()
    plt.legend()
    plt.grid(True)
    
    save_path = f"scripts/hull-diags/{case_name}_plot.png"
    plt.savefig(save_path)
    print(f"Saved plot to {save_path}")
    plt.close()

if __name__ == "__main__":
    cases = [
        "tri6_bulgein_rot", "tri6_bulgeout_rot", "tri6_vertbulge",
        "quad8_bulgein_rot", "quad8_bulgeout_rot", "quad8_vertbulge",
        "quad9_bulgein_rot", "quad9_bulgeout_rot", "quad9_vertbulge"
    ]
    for c in cases:
        plot_case(c)
