"""Root successful CI outputs before acknowledging completion to Nix clients."""

import os
from pathlib import Path
import re


directory = Path("/nix/var/nix/gcroots/config-ci-pending")
for value in os.environ.get("OUT_PATHS", "").split():
    if not re.fullmatch(r"/nix/store/[0-9abcdfghijklmnpqrsvwxyz]{32}-[A-Za-z0-9+._?=-]+", value):
        raise ValueError("Invalid output path")
    if value.endswith(".drv"):
        continue
    root = directory / Path(value).name
    try:
        root.symlink_to(value)
    except FileExistsError:
        if os.readlink(root) != value:
            raise ValueError("Conflicting output root")
