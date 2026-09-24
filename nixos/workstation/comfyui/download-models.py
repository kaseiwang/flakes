"""Explicit, resumable downloads. Only verified files get their final names."""

import argparse
import fcntl
import hashlib
import json
from pathlib import Path
import subprocess


def verified(path, model):
    if not path.is_file() or path.stat().st_size != model["bytes"]:
        return False
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest() == model["sha256"]


def download(root, model):
    target = root / model["directory"] / Path(model["file"]).name
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists():
        if verified(target, model):
            print(f"Verified existing {target.name}", flush=True)
            return
        raise RuntimeError(f"Invalid existing file: {target}; move it aside before retrying")

    partial = target.with_name(target.name + ".partial")
    url = f'https://huggingface.co/{model["repo"]}/resolve/{model["revision"]}/{model["file"]}'
    # A completed partial may have survived an interrupted checksum/rename.
    if not partial.exists() or partial.stat().st_size < model["bytes"]:
        print(f"Downloading {target.name} ({model['bytes'] / 1e9:.2f} GB)", flush=True)
        subprocess.run(
            ["curl", "--fail", "--location", "--show-error", "--silent",
             "--retry", "8", "--retry-delay", "5", "--connect-timeout", "30",
             "--speed-limit", "1024", "--speed-time", "120",
             "--continue-at", "-", "--output", str(partial), url],
            check=True,
        )
    print(f"Checking SHA256: {target.name}", flush=True)
    if not verified(partial, model):
        raise RuntimeError(f"Checksum/size mismatch: {partial}; move it aside before retrying")
    partial.replace(target)
    print(f"Ready: {target}", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("root", type=Path)
    parser.add_argument("group", choices=["base", "turbo", "ref2va"])
    args = parser.parse_args()
    args.root.mkdir(parents=True, exist_ok=True)
    # Different systemd template instances must not write the same files at once.
    with (args.root / ".download.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        for model in json.loads(args.manifest.read_text()):
            if model["group"] == args.group:
                download(args.root, model)


if __name__ == "__main__":
    main()
