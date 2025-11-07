# Publishing anpta Images to Docker Hub

This document explains how to publish the images from this repository to Docker Hub with clear, reproducible tags and easy moving aliases, and how to maintain them over time.

## Variants we build

From the single root `Dockerfile` we build eight targets:

- `cpu` (non‑root, for Docker runtime) — multi‑arch: linux/amd64, linux/arm64
- `cpu-singularity` (root, for Singularity/Apptainer) — multi‑arch: linux/amd64, linux/arm64
- `gpu-cuda124` (non‑root, for Docker runtime; CUDA 12.4) — linux/amd64 only
- `gpu-cuda124-singularity` (root, for Singularity/Apptainer; CUDA 12.4) — linux/amd64 only
- `gpu-cuda128` (non‑root, for Docker runtime; CUDA 12.8) — linux/amd64 only
- `gpu-cuda128-singularity` (root, for Singularity/Apptainer; CUDA 12.8) — linux/amd64 only
- `gpu-cuda13` (non‑root, for Docker runtime; CUDA 13) — linux/amd64 only
- `gpu-cuda13-singularity` (root, for Singularity/Apptainer; CUDA 13) — linux/amd64 only

## Tagging strategy

Use immutable, descriptive tags plus simple moving aliases:

- Immutable release tags (examples)
  - `v0.2.0-cpu-ubuntu24.04`
  - `v0.2.0-cpu-singularity-ubuntu24.04`
  - `v0.2.0-gpu-cu124-ubuntu22.04`
  - `v0.2.0-gpu-cu124-singularity-ubuntu22.04`
  - `v0.2.0-gpu-cu128-ubuntu24.04`
  - `v0.2.0-gpu-cu128-singularity-ubuntu24.04`
  - `v0.2.0-gpu-cu13-ubuntu24.04`
  - `v0.2.0-gpu-cu13-singularity-ubuntu24.04`
- Moving aliases (one per variant)
  - `cpu` → latest stable CPU (multi‑arch)
  - `cpu-singularity` → latest stable CPU Singularity (multi‑arch)
  - `gpu-cu124` → latest stable GPU CUDA 12.4 (amd64)
  - `gpu-cu124-singularity` → latest stable GPU CUDA 12.4 Singularity (amd64)
  - `gpu-cu128` → latest stable GPU CUDA 12.8 (amd64)
  - `gpu-cu128-singularity` → latest stable GPU CUDA 12.8 Singularity (amd64)
  - `gpu-cu13` → latest stable GPU CUDA 13 (amd64)
  - `gpu-cu13-singularity` → latest stable GPU CUDA 13 Singularity (amd64)

Notes:
- Prefer semantic versions (`vX.Y.Z`) or date versions (`YYYY.MM.DD`) and keep a CHANGELOG (Ubuntu/CUDA/cuDNN/torch/JAX pins, notable changes).
- Avoid a single `latest` across variants to prevent confusion.

## Prerequisites

- Docker Hub account and repository, e.g. `docker.io/<USER>/anpta`.
- Docker Buildx with QEMU/binfmt for cross‑builds:
  ```bash
  docker buildx ls
  # If needed:
  docker run --privileged --rm tonistiigi/binfmt --install all
  ```
- Login to Docker Hub:
  ```bash
  docker login
  ```

Convenience variables (adjust `<USER>` and version):
```bash
export DOCKERHUB_REPO=docker.io/<USER>/anpta
export VERSION=v0.2.0
export OS_TAG_CPU=ubuntu24.04
export OS_TAG_CUDA124=ubuntu22.04
export OS_TAG_CUDA128=ubuntu24.04
export OS_TAG_CUDA13=ubuntu24.04
```

## Automated Publishing Scripts (Recommended)

The easiest way to publish all variants is using the automated scripts:

**Build and push all variants:**
```bash
# Login to Docker Hub first
docker login

# Ensure VERSION file in repo root contains the version (e.g., "v0.2.0")
# Then build and push all variants to Docker Hub
./scripts/push_to_registry.sh dockerhub
```

The scripts handle:
- Reading version from `VERSION` file in repo root (must exist)
- Building all eight variants (cpu, cpu-singularity, gpu-cuda124, gpu-cuda124-singularity, gpu-cuda128, gpu-cuda128-singularity, gpu-cuda13, gpu-cuda13-singularity)
- Multi-platform builds (amd64 + arm64 for CPU variants)
- Creating moving aliases
- Tagging with versioned and alias tags

## Build and push with Buildx (manual)

### CPU (multi‑arch) — docker variant
```bash
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --target cpu \
  -t ${DOCKERHUB_REPO}:${VERSION}-cpu-${OS_TAG_CPU} \
  --build-arg BASE_IMAGE=ubuntu:24.04 \
  --push .

# Moving alias
docker buildx imagetools create \
  -t ${DOCKERHUB_REPO}:cpu \
  ${DOCKERHUB_REPO}:${VERSION}-cpu-${OS_TAG_CPU}
```

### CPU (multi‑arch) — singularity variant
```bash
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --target cpu-singularity \
  -t ${DOCKERHUB_REPO}:${VERSION}-cpu-singularity-${OS_TAG_CPU} \
  --build-arg BASE_IMAGE=ubuntu:24.04 \
  --push .

docker buildx imagetools create \
  -t ${DOCKERHUB_REPO}:cpu-singularity \
  ${DOCKERHUB_REPO}:${VERSION}-cpu-singularity-${OS_TAG_CPU}
```

### GPU (amd64) — docker variant (CUDA 12.4)
```bash
docker buildx build \
  --platform linux/amd64 \
  --target gpu-cuda124 \
  -t ${DOCKERHUB_REPO}:${VERSION}-gpu-cu124-${OS_TAG_CUDA124} \
  --build-arg BASE_IMAGE=nvidia/cuda:12.4.0-devel-ubuntu22.04 \
  --push .

docker buildx imagetools create \
  -t ${DOCKERHUB_REPO}:gpu-cu124 \
  ${DOCKERHUB_REPO}:${VERSION}-gpu-cu124-${OS_TAG_CUDA124}
```

### GPU (amd64) — singularity variant (CUDA 12.4)
```bash
docker buildx build \
  --platform linux/amd64 \
  --target gpu-cuda124-singularity \
  -t ${DOCKERHUB_REPO}:${VERSION}-gpu-cu124-singularity-${OS_TAG_CUDA124} \
  --build-arg BASE_IMAGE=nvidia/cuda:12.4.0-devel-ubuntu22.04 \
  --push .

docker buildx imagetools create \
  -t ${DOCKERHUB_REPO}:gpu-cu124-singularity \
  ${DOCKERHUB_REPO}:${VERSION}-gpu-cu124-singularity-${OS_TAG_CUDA124}
```

### GPU (amd64) — docker variant (CUDA 12.8)
```bash
docker buildx build \
  --platform linux/amd64 \
  --target gpu-cuda128 \
  -t ${DOCKERHUB_REPO}:${VERSION}-gpu-cu128-${OS_TAG_CUDA128} \
  --build-arg BASE_IMAGE=nvidia/cuda:12.8.1-cudnn-devel-ubuntu24.04 \
  --push .

docker buildx imagetools create \
  -t ${DOCKERHUB_REPO}:gpu-cu128 \
  ${DOCKERHUB_REPO}:${VERSION}-gpu-cu128-${OS_TAG_CUDA128}
```

### GPU (amd64) — singularity variant (CUDA 12.8)
```bash
docker buildx build \
  --platform linux/amd64 \
  --target gpu-cuda128-singularity \
  -t ${DOCKERHUB_REPO}:${VERSION}-gpu-cu128-singularity-${OS_TAG_CUDA128} \
  --build-arg BASE_IMAGE=nvidia/cuda:12.8.1-cudnn-devel-ubuntu24.04 \
  --push .

docker buildx imagetools create \
  -t ${DOCKERHUB_REPO}:gpu-cu128-singularity \
  ${DOCKERHUB_REPO}:${VERSION}-gpu-cu128-singularity-${OS_TAG_CUDA128}
```

### GPU (amd64) — docker variant (CUDA 13)
```bash
docker buildx build \
  --platform linux/amd64 \
  --target gpu-cuda13 \
  -t ${DOCKERHUB_REPO}:${VERSION}-gpu-cu13-${OS_TAG_CUDA13} \
  --build-arg BASE_IMAGE=nvidia/cuda:13.0.1-cudnn-devel-ubuntu24.04 \
  --push .

docker buildx imagetools create \
  -t ${DOCKERHUB_REPO}:gpu-cu13 \
  ${DOCKERHUB_REPO}:${VERSION}-gpu-cu13-${OS_TAG_CUDA13}
```

### GPU (amd64) — singularity variant (CUDA 13)
```bash
docker buildx build \
  --platform linux/amd64 \
  --target gpu-cuda13-singularity \
  -t ${DOCKERHUB_REPO}:${VERSION}-gpu-cu13-singularity-${OS_TAG_CUDA13} \
  --build-arg BASE_IMAGE=nvidia/cuda:13.0.1-cudnn-devel-ubuntu24.04 \
  --push .

docker buildx imagetools create \
  -t ${DOCKERHUB_REPO}:gpu-cu13-singularity \
  ${DOCKERHUB_REPO}:${VERSION}-gpu-cu13-singularity-${OS_TAG_CUDA13}
```

## Alternative: Push existing images (fastest)

If you've already built images locally and just want to push them, you can manually tag and push:

```bash
# Login to Docker Hub
docker login

# Tag and push each variant manually
# Example for CPU variant:
docker tag anpta:cpu ${DOCKERHUB_REPO}:${VERSION}-cpu-${OS_TAG_CPU}
docker push ${DOCKERHUB_REPO}:${VERSION}-cpu-${OS_TAG_CPU}
docker buildx imagetools create -t ${DOCKERHUB_REPO}:cpu ${DOCKERHUB_REPO}:${VERSION}-cpu-${OS_TAG_CPU}
```

This is much faster than rebuilding, especially for large images that take 2+ hours to build.

## Verifying published images
```bash
# Show platforms in the manifest
docker buildx imagetools inspect ${DOCKERHUB_REPO}:cpu | grep -E "Platform:|Digest:"
docker buildx imagetools inspect ${DOCKERHUB_REPO}:gpu-cu124 | grep -E "Platform:|Digest:"
docker buildx imagetools inspect ${DOCKERHUB_REPO}:gpu-cu128 | grep -E "Platform:|Digest:"
docker buildx imagetools inspect ${DOCKERHUB_REPO}:gpu-cu13 | grep -E "Platform:|Digest:"

# Quick runtime check
docker run --rm ${DOCKERHUB_REPO}:cpu uname -m
DOCKER_DEFAULT_PLATFORM=linux/amd64 docker run --rm ${DOCKERHUB_REPO}:gpu-cu124 uname -m
```

## Release process

1. Choose the version bump (patch/minor/major) and update requirements/pins as needed.
2. Update the `VERSION` file in the repo root with the new version (e.g., `v0.2.0`).
3. Build and push all variants using the automated script:
   ```bash
   docker login
   ./scripts/push_to_registry.sh dockerhub
   ```
   This automatically reads the version from `VERSION` file, builds, pushes, and creates all moving aliases for all eight variants.
4. Create a GitHub/GitLab release with notes listing key pins (Ubuntu, CUDA, cuDNN, torch, JAX, etc.).

## Maintenance notes

- CPU is multi‑arch (amd64, arm64). GPU variants remain amd64 only (CUDA base images).
- Large image sizes are normal (CPU ~4–6 GB; GPU can exceed 20 GB). First pushes are slow.
- We now build three GPU variants: CUDA 12.4 (Ubuntu 22.04), CUDA 12.8 (Ubuntu 24.04), and CUDA 13 (Ubuntu 24.04).
- Consider OCI labels in the Dockerfile for `org.opencontainers.image.version`, `revision`, `created`, `source`, etc.

## Troubleshooting

- QEMU/binfmt missing → install via `tonistiigi/binfmt` (see prerequisites).
- Apple Silicon building GPU → ensure `--platform linux/amd64` and a buildx builder that supports it.
- cuDNN present → `docker run --rm ${DOCKERHUB_REPO}:gpu-cu124 bash -lc 'ldconfig -p | grep cudnn'`.

---

With this scheme the community gets:
- Reproducible, immutable tags for exact environments.
- Simple aliases per variant for the latest stable builds.
