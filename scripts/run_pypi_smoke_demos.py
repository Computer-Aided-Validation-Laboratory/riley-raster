"""Run the demo modules exported by the installed Riley package."""

import argparse
import subprocess
import sys
from pathlib import Path

from riley.pydemos import __all__ as demos


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--verify-checkout",
        action="store_true",
        help="Require installed exports to match numbered demos in the checkout",
    )
    args = parser.parse_args()

    if not demos:
        raise SystemExit("The installed riley.pydemos.__all__ is empty")

    if args.verify_checkout:
        checkout_demos = Path(__file__).resolve().parents[1] / "src" / "riley" / "pydemos"
        expected = {path.stem for path in checkout_demos.glob("demo[0-9]*.py") if path.is_file()}
        if not expected:
            raise SystemExit(f"No numbered demo modules found in {checkout_demos}")

        installed = set(demos)
        if installed != expected:
            raise SystemExit(
                "Installed demo exports do not match the checkout: "
                f"missing={sorted(expected - installed)}, unexpected={sorted(installed - expected)}"
            )

    for demo in demos:
        module = f"riley.pydemos.{demo}"
        print(f"Running {module}", flush=True)
        subprocess.run([sys.executable, "-I", "-m", module], check=True)
