"""Write this run's locally built store paths into a file:// binary cache.

`nix copy` refuses to add a path to a binary cache unless the cache also holds
its references, which would duplicate cache.nixos.org. Substituting only needs
each narinfo and NAR; references are fetched from whichever cache has them.

Usage: nix path-info --all --json --json-format 1 | python3 collect.py CACHE
"""

import json
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

cache = Path(sys.argv[1])
info = json.load(sys.stdin)
present = {Path(path).name.split("-", 1)[0] for path in info}

# Drop restored paths this run never needed, so the entry tracks current outputs.
for narinfo in cache.glob("*.narinfo"):
    if narinfo.stem not in present:
        (cache / "nar" / f"{narinfo.stem}.nar.zst").unlink(missing_ok=True)
        narinfo.unlink()


def add(path, meta):
    name = Path(path).name
    narinfo = cache / f"{name.split('-', 1)[0]}.narinfo"
    if narinfo.exists():
        return
    nar = cache / "nar" / f"{narinfo.stem}.nar.zst"
    with nar.open("wb") as out:
        dump = subprocess.Popen(["nix-store", "--dump", path], stdout=subprocess.PIPE)
        subprocess.run(["zstd", "-q", "-c"], stdin=dump.stdout, stdout=out, check=True)
        if dump.wait():
            raise SystemExit(f"nix-store --dump {path} failed")
    fields = {
        "StorePath": path,
        "URL": f"nar/{nar.name}",
        "Compression": "zstd",
        "FileSize": nar.stat().st_size,
        "NarHash": meta["narHash"],
        "NarSize": meta["narSize"],
        "References": " ".join(Path(ref).name for ref in meta["references"]),
    }
    if meta.get("deriver"):
        fields["Deriver"] = Path(meta["deriver"]).name
    if meta.get("ca"):
        fields["CA"] = meta["ca"]
    narinfo.write_text("".join(f"{key}: {value}\n" for key, value in fields.items()))


(cache / "nar").mkdir(exist_ok=True)
built = [
    (path, meta)
    for path, meta in info.items()
    if meta.get("ultimate") and not path.endswith(".drv")
]
with ThreadPoolExecutor() as pool:
    list(pool.map(lambda item: add(*item), built))
print(f"{len(built)} locally built paths, {len(list(cache.glob('*.narinfo')))} cached")
