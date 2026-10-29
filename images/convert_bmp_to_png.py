"""Convert all BMP image files in the directory to optimized PNG format."""

import argparse
from pathlib import Path
from PIL import Image


def convert_bmp_to_png(
    directory: Path | None = None,
    delete_source: bool = False,
) -> None:
    """Find and convert all BMP images in directory to PNG format."""
    if directory is None:
        directory = Path(__file__).resolve().parent

    bmp_files = sorted(directory.glob("*.bmp"))
    if not bmp_files:
        print(f"No .bmp files found in {directory}")
        return

    print(f"Found {len(bmp_files)} BMP files in {directory}:")
    for bmp_path in bmp_files:
        png_path = bmp_path.with_suffix(".png")
        with Image.open(bmp_path) as img:
            img.save(png_path, format="PNG", optimize=True)

        bmp_size_mb = bmp_path.stat().st_size / (1024 * 1024)
        png_size_mb = png_path.stat().st_size / (1024 * 1024)
        print(
            f"  {bmp_path.name} ({bmp_size_mb:.2f} MB) -> "
            f"{png_path.name} ({png_size_mb:.2f} MB)"
        )
        if delete_source:
            bmp_path.unlink()
            print(f"  Removed source {bmp_path.name}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Convert BMP images to PNG format."
    )
    parser.add_argument(
        "--delete",
        action="store_true",
        help="Delete source BMP files after conversion.",
    )
    args = parser.parse_args()
    convert_bmp_to_png(delete_source=args.delete)
