AEI PTA analysis docker & singularity
======================================

Purpose
-------

This repo provides a reproducible docker image for PTA analysis. The main goal is for this image to be converted into a singularity container for use on High Throughput Clusters. The workflow is as follows

First create the docker image from the Dockerfile locally. Then, the docker image needs to be saved to a tarball so that it can be copied over to a computing cluster that runs singularity (in case singularity does not run locally, like on apple silicon). Then, singularity can convert the docker tarball to a singularity container.

These containers also have user-space versions for devcontainer use.


Images and targets
------------------

This repo uses a single Dockerfile with four build targets (two variants per arch/GPU):

- `cpu` (non-root, for Docker runtime)
- `cpu-singularity` (root, for Singularity/Apptainer; built but not converted to .sif - Singularity doesn't run on ARM64)
- `gpu` (non-root, for Docker runtime; BASE_IMAGE=`nvidia/cuda:12.4.1-devel-ubuntu22.04`)
- `gpu-singularity` (root, for Singularity/Apptainer; converted to .sif for HPC clusters)

Both CPU variants are functionally identical; the "docker" variant adds a non-root user and permissions. GPU variants additionally include CUDA/cuDNN, torch+cu124, cupy, pycuda, JAX CUDA.

**Note:** Only the GPU variant is converted to Singularity `.sif` files, as HPC clusters are typically x86_64 and Singularity/Apptainer doesn't run on ARM64 architecture.

Build with docker buildx
------------------------

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

Publishing to Registries
------------------------

The easiest way to publish all variants to a registry is using the automated scripts:

**Build and push to local registry (default):**
```bash
./scripts/push_to_registry.sh v0.1.0
```

**Build and push to Docker Hub:**
```bash
docker login
./scripts/push_to_registry.sh v0.1.0 dockerhub
```

**Push existing local images (without rebuilding):**
```bash
./scripts/push_existing_images.sh v0.1.0              # Local registry
./scripts/push_existing_images.sh v0.1.0 dockerhub    # Docker Hub
```

For detailed instructions on publishing workflows, see:
- [docs/TESTING_WITH_LOCAL_REGISTRY.md](docs/TESTING_WITH_LOCAL_REGISTRY.md) - Testing with local registry
- [docs/PUBLISHING_DOCKERHUB.md](docs/PUBLISHING_DOCKERHUB.md) - Publishing to Docker Hub

Versioning and tags
-------------------

- Suggested immutable tags (examples):
  - `v0.1.0-cpu-ubuntu22.04`, `v0.1.0-cpu-singularity-ubuntu22.04`
  - `v0.1.0-gpu-cu124-ubuntu22.04`, `v0.1.0-gpu-singularity-ubuntu22.04`
- Stable aliases (move on each release): `cpu`, `cpu-singularity`, `gpu-cu124`, `gpu-singularity`.
- CPU images should be published as multi-arch (linux/amd64, linux/arm64); GPU as linux/amd64 only.


Starting locally
----------------

After building with buildx, run the container with:

<pre><code>
docker run --rm -it anpta:gpu-cu124 bash
# or
docker run --rm -it anpta:cpu bash
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

**Option 1: Build directly from Docker image (recommended, works on Apple Silicon)**

You can build .sif files directly from Docker image tags using Docker itself (no need for Singularity locally):

<pre><code>
# Build GPU Singularity image
./scripts/build_singularity_with_docker.sh anpta:gpu-singularity anpta-gpu.sif

# Or use the automated script
./scripts/build_all_singularity.sh
</code></pre>

This method works on Apple Silicon and any system with Docker, as it runs Singularity/Apptainer inside a Docker container.

For detailed instructions on building Singularity images on Apple Silicon, see [docs/BUILDING_SINGULARITY_ON_APPLE_SILICON.md](docs/BUILDING_SINGULARITY_ON_APPLE_SILICON.md).

**Option 2: Build from Docker tar archive (traditional method)**

First save the Docker GPU image as a tar file:

<pre><code>
docker save -o anpta_gpu_image.tar anpta:gpu-singularity
</code></pre>

Then convert to Singularity. On systems with Singularity installed natively:

<pre><code>
singularity build anpta-gpu.sif docker-archive://anpta_gpu_image.tar
</code></pre>

Or on Apple Silicon (or systems without Singularity), use the Docker-based script:

<pre><code>
./scripts/build_singularity_with_docker.sh docker-archive://anpta_gpu_image.tar anpta-gpu.sif
</code></pre>

The singularity container can be tested with
--------------------------------

<pre><code>
singularity exec --bind /your_host_directory/:/container_directory/ anpta.sif bash
</code></pre>

Hosting and sharing Singularity images
--------------------------------------

Since Docker Hub doesn't support `.sif` files, you can host your Singularity images using alternative solutions. The recommended approach is **Sylabs Cloud Library**, which provides native support for Singularity images and allows collaborators to pull directly:

**Publishing to Sylabs Cloud Library:**

1. Create an account at https://cloud.sylabs.io/
2. Authenticate: `singularity remote login --username <your-username>`
3. Build your `.sif` files (see above)
4. Push using the automated script:
   ```bash
   ./scripts/push_to_sylabs.sh v0.1.0
   ```

**Collaborators can then pull directly:**

```bash
singularity pull library://<username>/anpta/gpu-singularity:v0.1.0
```

For detailed information on all hosting options (Sylabs, GitHub Releases, GitLab Packages, etc.), see [docs/HOSTING_SINGULARITY_IMAGES.md](docs/HOSTING_SINGULARITY_IMAGES.md).

Image sizes and registries
--------------------------

- Scientific stacks are large. CPU ~4–6 GB (tar), GPU can exceed 20 GB depending on CUDA/cuDNN/torch wheels.
- This is acceptable for public registries (Docker Hub/GHCR). Pushes will be slow; prefer CI on a fast network.
- Will consider size optimizations later (multi-stage runtime trim, strip symbols, remove dev headers) if needed.


Testing CUDA 13 Package Compatibility
--------------------------------------

To test package compatibility with CUDA 13 on your cluster:

1. **Build a writable sandbox on the cluster:**
   ```bash
   ./scripts/build_cuda13_sandbox_cluster.sh ~/cuda13-sandbox
   ```

2. **Shell into it with GPU support:**
   ```bash
   ./scripts/shell_sandbox_cluster.sh ~/cuda13-sandbox
   ```

3. **Inside the sandbox, test package installations:**
   ```bash
   apt-get update && apt-get install -y python3 python3-pip
   pip3 install --upgrade pip
   pip3 install -f https://storage.googleapis.com/jax-releases/jax_cuda_releases.html jax[cuda13_pip] jaxlib
   python3 -c "import jax; print(jax.devices())"
   ```

For detailed instructions, see [docs/TESTING_CUDA13_COMPATIBILITY.md](docs/TESTING_CUDA13_COMPATIBILITY.md).

**Note:** You must test on the cluster where CUDA 13 hardware is available. Testing on Apple M1 can only verify package installation, not actual CUDA functionality.

Devcontainer (VS Code) setup
----------------------------

This repository includes a ready-to-use Dev Container configuration under `devcontainer/` for interactive development in VS Code.

- Files:
  - `devcontainer/devcontainer.json`: Devcontainer entrypoint that builds a small dev layer on top of a base image.
  - `devcontainer/Dockerfile.dev`: Grants anpta user sudo permissions for ease of modification
  - Place the above two files in a `.devcontainer` directory of your project

- Base image selection:
  - By default, the Devcontainer builds FROM `anpta:cpu` (non‑root docker variant).
  - To use the GPU base, change in `devcontainer/devcontainer.json`:
    - `"BASE_IMAGE": "anpta:gpu"`

- VS Code customizations:
  - The Devcontainer recommends installing useful extensions (Python, Black, Ruff, Jupyter, Pylance, YAML, GitLens).
  - The Python venv is auto‑activated for interactive shells, and `ipykernel` is installed and registered as: “Python (pta)”.

- How to use:
  1. Open the repo in VS Code with the “Dev Containers” extension installed.
  2. When prompted, “Reopen in Container” (or use the Command Palette: “Dev Containers: Reopen in Container”).
  3. Select the kernel “Python (pta)” in Jupyter/Notebooks.

- Notes:
  - The Devcontainer layer is for interactive development only, not for CI or production.
  - No extra container/remote env wiring is required; the venv is on PATH and auto‑activated.
