FROM python:3.12-slim-bookworm@sha256:1aaa65a85fda306ffb8b910824d4e93bdce61e212c7e87168123ea3073b41a1a

# Snapshot the OS dependencies too. CUDA user-space libraries come from the
# locked PyTorch wheels; the host driver is supplied at runtime by NVIDIA CDI.
RUN rm /etc/apt/sources.list.d/debian.sources \
    && printf '%s\n' \
      'deb [check-valid-until=no] https://snapshot.debian.org/archive/debian/20260923T000000Z bookworm main' \
      'deb [check-valid-until=no] https://snapshot.debian.org/archive/debian-security/20260923T000000Z bookworm-security main' \
      > /etc/apt/sources.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends libgomp1 libgl1 libglib2.0-0 ffmpeg \
    && rm -rf /var/lib/apt/lists/*

ENV PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 PIP_NO_CACHE_DIR=1 \
    HOME=/data/cache XDG_CACHE_HOME=/data/cache \
    HF_HOME=/data/cache/huggingface TORCH_HOME=/data/cache/torch \
    TORCHINDUCTOR_CACHE_DIR=/data/cache/inductor TRITON_CACHE_DIR=/data/cache/triton

WORKDIR /opt/ComfyUI
COPY requirements.lock /opt/requirements.lock
RUN python -m pip install --require-hashes --only-binary=:all: -r /opt/requirements.lock \
    && python -m pip check

# Verify both archives before extracting; no git or package installation on boot.
RUN python - <<'PY'
import hashlib
import io
import tarfile
import urllib.request
from pathlib import Path

sources = [
    ("Comfy-Org/ComfyUI", "73c9bad4d21e7addbe1d13bc92eee0f1431b017d",
     "9e8f83f0d6a6ee19de1a2a94ad961e07e3031e0770313b91d4ed404884ec4faa", Path("/opt/ComfyUI")),
    ("leejet/ComfyUI-GGUF", "edd981b10e107d3b8f58e16c498f2d08f631bc47",
     "9a34b69667a419488e16755913754487b1ede20a99816a4947971a74f59e19c0", Path("/opt/ComfyUI/custom_nodes/ComfyUI-GGUF")),
]
for repo, revision, sha256, destination in sources:
    data = urllib.request.urlopen(f"https://api.github.com/repos/{repo}/tarball/{revision}", timeout=120).read()
    if hashlib.sha256(data).hexdigest() != sha256:
        raise RuntimeError(f"Archive hash mismatch: {repo}")
    destination.mkdir(parents=True, exist_ok=True)
    with tarfile.open(fileobj=io.BytesIO(data)) as archive:
        for member in archive.getmembers():
            # GitHub source archives have one enclosing directory.
            member.name = member.name.partition("/")[2]
            if member.name:
                archive.extract(member, destination, filter="data")
PY

# Keep this after the large dependency layers so compatibility changes reuse them.
RUN apt-get update \
    && apt-get install -y --no-install-recommends patch \
    && rm -rf /var/lib/apt/lists/*

COPY h3-compatibility.patch /opt/h3-compatibility.patch
RUN python - <<'PY'
import subprocess
from pathlib import Path

# The pinned GGUF source uses CRLF; keep the reviewed patch in normal LF form.
loader = Path("custom_nodes/ComfyUI-GGUF/loader.py")
loader.write_bytes(loader.read_bytes().replace(b"\r\n", b"\n"))
subprocess.run([
    "patch", "--batch", "--forward", "--fuzz=0", "-p1",
    "-i", "/opt/h3-compatibility.patch",
], check=True)
for source in (loader, Path("comfy/ldm/minimax/vae.py")):
    compile(source.read_text(), str(source), "exec")
PY

USER 10001:10001
EXPOSE 8188
ENTRYPOINT ["python", "/opt/ComfyUI/main.py"]
