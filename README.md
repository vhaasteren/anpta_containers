AEI PTA analysis docker & singularity
======================================

Purpose
-------

This repo provides a reproducible docker image for PTA analysis. The main goal is for this image to be converted into a singularity container for use on High Throughput Clusters. The workflow is as follows

First create the docker image from the Dockerfile locally. Then, the docker image needs to be saved to a tarball so that it can be copied over to a computing cluster that runs singularity (in case singularity does not run locally, like on apple silicon). Then, singularity can convert the docker tarball to a singularity container.


Images and targets
------------------

This repo uses a single Dockerfile with four build targets (two variants per arch/GPU):

- `cpu` (non-root, for Docker runtime)
- `cpu-singularity` (root, for Singularity/Apptainer)
- `gpu` (non-root, for Docker runtime; BASE_IMAGE=`nvidia/cuda:12.4.1-devel-ubuntu22.04`)
- `gpu-singularity` (root, for Singularity/Apptainer)

Both CPU variants are functionally identical; the “docker” variant adds a non-root user and permissions. GPU variants additionally include CUDA/cuDNN, torch+cu124, cupy, pycuda, JAX CUDA.

Build with docker compose profiles (recommended)
-----------------------------------------------

The single `docker-compose.yml` defines two services guarded by profiles.

GPU build/run (docker variant, linux/amd64):

<pre><code>
docker compose --profile gpu build
docker compose --profile gpu run --rm anpta bash
</code></pre>

CPU build/run (docker variant; multi-arch host pulls its native arch):

<pre><code>
docker compose --profile cpu build
docker compose --profile cpu run --rm anpta-cpu bash
</code></pre>

Build directly with docker buildx (optional)
--------------------------------------------

CPU (multi-arch, docker variant):

<pre><code>
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --target cpu \
  -t anpta:cpu \
  --build-arg BASE_IMAGE=ubuntu:22.04 \
  .
</code></pre>

CPU (multi-arch, singularity variant):

<pre><code>
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --target cpu-singularity \
  -t anpta:cpu-singularity \
  --build-arg BASE_IMAGE=ubuntu:22.04 \
  .
</code></pre>

GPU (amd64, docker variant):

<pre><code>
docker buildx build \
  --platform linux/amd64 \
  --target gpu \
  -t anpta:gpu-cu124 \
  --build-arg BASE_IMAGE=nvidia/cuda:12.4.1-devel-ubuntu22.04 \
  .
</code></pre>

GPU (amd64, singularity variant):

<pre><code>
docker buildx build \
  --platform linux/amd64 \
  --target gpu-singularity \
  -t anpta:gpu-singularity \
  --build-arg BASE_IMAGE=nvidia/cuda:12.4.1-devel-ubuntu22.04 \
  .
</code></pre>
Notes for buildx:

- The GPU target is linux/amd64. On Apple Silicon, ensure your buildx builder supports cross-building to amd64 (QEMU). Check with:

  <pre><code>
  docker buildx ls
  </code></pre>

- Alternatively, set a default platform for the command:

  <pre><code>
  DOCKER_DEFAULT_PLATFORM=linux/amd64 docker buildx build --target gpu -t anpta:gpu-cu124 --build-arg BASE_IMAGE=nvidia/cuda:12.4.1-devel-ubuntu22.04 .
  </code></pre>

Versioning and tags
-------------------

- Suggested immutable tags (examples):
  - `v0.1.0-cpu-ubuntu22.04`, `v0.1.0-cpu-singularity-ubuntu22.04`
  - `v0.1.0-gpu-cu124-ubuntu22.04`, `v0.1.0-gpu-singularity-ubuntu22.04`
- Stable aliases (move on each release): `cpu`, `cpu-singularity`, `gpu-cu124`, `gpu-singularity`.
- CPU images should be published as multi-arch (linux/amd64, linux/arm64); GPU as linux/amd64 only.


Starting locally
----------------

With the compose profiles, prefer:

<pre><code>
docker compose --profile gpu run --rm anpta bash
# or
docker compose --profile cpu run --rm anpta-cpu bash
</code></pre>

Save the docker image
---------------------

To convert the docker image to a singularity container, it may be necessarity to transport it first, which means we need it as a file. Saving the docker image as a file can be done with:

<pre><code>
docker save -o anpta_gpu_image.tar anpta:gpu-singularity
# or
docker save -o anpta_cpu_image.tar anpta:cpu-singularity
</code></pre>

Convert the docker image to a singularity container
---------------------------------------------------

This needs to be done on a node that has singularity installed

<pre><code>
singularity build anpta.sif docker-archive://anpta_gpu_image.tar
# or
singularity build anpta.sif docker-archive://anpta_cpu_image.tar
</code></pre>

Image sizes and registries
--------------------------

- Scientific stacks are large. CPU ~4–6 GB (tar), GPU can exceed 20 GB depending on CUDA/cuDNN/torch wheels.
- This is acceptable for public registries (Docker Hub/GHCR). Pushes will be slow; prefer CI on a fast network.
- Will consider size optimizations later (multi-stage runtime trim, strip symbols, remove dev headers) if needed.


Devcontainer (VS Code) setup
----------------------------

This repository includes a ready-to-use Dev Container configuration under `devcontainer/` for interactive development in VS Code.

- Files:
  - `devcontainer/devcontainer.json`: Devcontainer entrypoint that builds a small dev layer on top of a base image.
  - `devcontainer/Dockerfile.dev`: Adds user `anpta` with passwordless sudo, auto‑activates the venv in `.bashrc`, and sets PATH/`VIRTUAL_ENV`.
  - Legacy examples are kept in `devcontainer/` for reference (`Dockerfile.apple`, `Dockerfile.amd64`, `devcontainer.apple.json`).

- Base image selection:
  - By default, the Devcontainer builds FROM `anpta:cpu-singularity` (root variant) and creates a non‑root user for development.
  - To use the GPU base, change in `devcontainer/devcontainer.json`:
    - `"BASE_IMAGE": "anpta:gpu-singularity"`

- VS Code customizations:
  - The Devcontainer recommends installing useful extensions (Python, Black, Ruff, Jupyter, Pylance, YAML, GitLens).
  - The Python venv is auto‑activated for interactive shells, and `ipykernel` is installed and registered as: “Python (pta)”.

- How to use:
  1. Open the repo in VS Code with the “Dev Containers” extension installed.
  2. When prompted, “Reopen in Container” (or use the Command Palette: “Dev Containers: Reopen in Container”).
  3. Select the kernel “Python (pta)” in Jupyter/Notebooks.

- Notes:
  - This Devcontainer layer is for interactive development only, not for CI or production.
  - No extra container/remote env wiring is required; the venv is on PATH and auto‑activated.

The container can be tested with
--------------------------------

<pre><code>
singularity exec --bind /work/rutger.vhaasteren/:/data/ anpta.sif bash
</code></pre>


