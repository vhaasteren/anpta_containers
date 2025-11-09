AEI PTA analysis docker & singularity
======================================

Purpose
-------

This repo provides a reproducible docker image for PTA analysis. The main goals for this image are:
- converted into a singularity container for use computing clusters
- use as a local environment for analysis and development

The shared environment between local development and cluster usage makes work hassle-free, without surprises and frustration. While these containers are buildable locally, they are hosted on Dockerhub under `vhaasteren/anpta`. These containers also have user-space versions for devcontainer use.


Images and targets
------------------

This repo uses a single Dockerfile with three types of build targets for different use cases:

**Singularity targets** (for HPC cluster conversion to `.sif`):
- `cpu-singularity` (root user, for Singularity/Apptainer conversion)
- `gpu-cuda124-singularity` (CUDA 12.4, root user)
- `gpu-cuda128-singularity` (CUDA 12.8, root user)
- `gpu-cuda13-singularity` (CUDA 13, root user)

**Devcontainer targets** (for VS Code Dev Containers):
- `cpu-devcontainer` (includes VS Code tools, uses `--user` flag for host UID/GID)
- `gpu-cuda124-devcontainer` (CUDA 12.4 + VS Code tools)
- `gpu-cuda128-devcontainer` (CUDA 12.8 + VS Code tools)
- `gpu-cuda13-devcontainer` (CUDA 13 + VS Code tools)

**Direct Docker usage targets** (for standalone Docker runs with UID/GID mapping):
- `cpu` (uses entrypoint script for dynamic UID/GID remapping)
- `gpu-cuda124` (CUDA 12.4 + entrypoint script)
- `gpu-cuda128` (CUDA 12.8 + entrypoint script)
- `gpu-cuda13` (CUDA 13 + entrypoint script)

All variants share the same software stack. GPU variants additionally include CUDA/cuDNN, torch, cupy, pycuda, and JAX CUDA. The direct usage targets use an entrypoint script (`entrypoint-uidmap.sh`) that automatically remaps the container's `anpta` user to match your host UID/GID, ensuring correct file permissions on bind-mounted volumes.

**Note:** Only the GPU variants are typically converted to Singularity `.sif` files, as HPC clusters are typically x86_64 and Singularity/Apptainer doesn't run on ARM64 architecture.

Build with docker buildx
------------------------

**CPU (multi-arch, direct usage):**

<pre><code>
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --target cpu \
  -t anpta:cpu \
  --build-arg BASE_IMAGE=ubuntu:22.04 \
  .
</code></pre>

**CPU (multi-arch, singularity variant):**

<pre><code>
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --target cpu-singularity \
  -t anpta:cpu-singularity \
  --build-arg BASE_IMAGE=ubuntu:22.04 \
  .
</code></pre>

**CPU (multi-arch, devcontainer):**

<pre><code>
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --target cpu-devcontainer \
  -t anpta:cpu-devcontainer \
  --build-arg BASE_IMAGE=ubuntu:22.04 \
  .
</code></pre>

**GPU (amd64, direct usage, CUDA 12.4):**

<pre><code>
docker buildx build \
  --platform linux/amd64 \
  --target gpu-cuda124 \
  -t anpta:gpu-cuda124 \
  --build-arg BASE_IMAGE=nvidia/cuda:12.4.1-devel-ubuntu22.04 \
  .
</code></pre>

**GPU (amd64, singularity variant, CUDA 12.4):**

<pre><code>
docker buildx build \
  --platform linux/amd64 \
  --target gpu-cuda124-singularity \
  -t anpta:gpu-cuda124-singularity \
  --build-arg BASE_IMAGE=nvidia/cuda:12.4.1-devel-ubuntu22.04 \
  .
</code></pre>

**GPU (amd64, devcontainer, CUDA 12.4):**

<pre><code>
docker buildx build \
  --platform linux/amd64 \
  --target gpu-cuda124-devcontainer \
  -t anpta:gpu-cuda124-devcontainer \
  --build-arg BASE_IMAGE=nvidia/cuda:12.4.1-devel-ubuntu22.04 \
  .
</code></pre>

Similar patterns apply for CUDA 12.8 (`gpu-cuda128-*`) and CUDA 13 (`gpu-cuda13-*`) targets.
**Notes for buildx:**

- The GPU targets are linux/amd64 only. On Apple Silicon, ensure your buildx builder supports cross-building to amd64 (QEMU). Check with:

  <pre><code>
  docker buildx ls
  </code></pre>

- Alternatively, set a default platform for the command:

  <pre><code>
  DOCKER_DEFAULT_PLATFORM=linux/amd64 docker buildx build --target gpu-cuda124 -t anpta:gpu-cuda124 --build-arg BASE_IMAGE=nvidia/cuda:12.4.1-devel-ubuntu22.04 .
  </code></pre>

Publishing to Registries
------------------------

The easiest way to publish all variants to a registry is using the automated scripts:

**Build and push to local registry (default):**
```bash
# Ensure VERSION file in repo root contains the version (e.g., "v0.2.0")
./scripts/push_to_registry.sh
```

**Build and push to Docker Hub:**
```bash
docker login
# Ensure VERSION file in repo root contains the version (e.g., "v0.2.0")
./scripts/push_to_registry.sh dockerhub
```

**Note:** The script reads the version from the `VERSION` file in the repo root. Update this file before running the script.

For detailed instructions on publishing workflows, see:
- [docs/PUBLISHING_DOCKERHUB.md](docs/PUBLISHING_DOCKERHUB.md) - Publishing to Docker Hub

Versioning and tags
-------------------

- Suggested immutable tags (examples):
  - `v0.1.0-cpu-ubuntu22.04`, `v0.1.0-cpu-singularity-ubuntu22.04`, `v0.1.0-cpu-devcontainer-ubuntu22.04`
  - `v0.1.0-gpu-cuda124-ubuntu22.04`, `v0.1.0-gpu-cuda124-singularity-ubuntu22.04`, `v0.1.0-gpu-cuda124-devcontainer-ubuntu22.04`
- Stable aliases (move on each release): `cpu`, `cpu-singularity`, `cpu-devcontainer`, `gpu-cuda124`, `gpu-cuda124-singularity`, `gpu-cuda124-devcontainer`, etc.
- CPU images should be published as multi-arch (linux/amd64, linux/arm64); GPU as linux/amd64 only.


Starting locally
----------------

**Direct Docker usage (with automatic UID/GID mapping):**

The direct usage targets (`cpu`, `gpu-cuda124`, etc.) automatically remap the container user to match your host UID/GID, ensuring correct file permissions on bind-mounted volumes:

<pre><code>
# CPU variant
docker run --rm -it \
  -e HOST_UID=$(id -u) -e HOST_GID=$(id -g) \
  -v "$PWD":/work -w /work \
  anpta:cpu bash

# GPU variant (CUDA 12.4)
docker run --rm -it \
  -e HOST_UID=$(id -u) -e HOST_GID=$(id -g) \
  -v "$PWD":/work -w /work \
  --gpus all \
  anpta:gpu-cuda124 bash
</code></pre>

The entrypoint script (`entrypoint-uidmap.sh`) automatically:
- Remaps the `anpta` user's UID/GID to match your host
- Ensures the home directory is properly owned
- **Does not chown the virtual environment** (startup is instant)
- Redirects `pip install` to `/work/.pyuser` by default (fast, no permissions issues)
- Redirects Python bytecode cache to `/work/.pycache`

**Installing Python packages:**

By default, packages install to the workspace (fast, no permissions issues):

```bash
pip install <package>         # installs into /work/.pyuser
python -c "import <package>"  # works immediately
```

If you *must* install into the baked virtualenv (slower, opt-in):

```bash
docker run --rm -it \
  -e HOST_UID=$(id -u) -e HOST_GID=$(id -g) \
  -e VENV_WRITABLE=1 \
  -v "$PWD":/work -w /work \
  anpta:cpu
# then:
pip install -e .
```

**Note:** If you don't provide `HOST_UID`/`HOST_GID`, the container will run with the default `anpta` user IDs. For proper file permissions on bind mounts, always provide these environment variables.

Save the docker image
---------------------

To convert the docker image to a singularity container, it may be necessary to transport it first, which means we need it as a file. Saving the docker image as a file can be done with:

<pre><code>
docker save -o anpta_gpu_image.tar anpta:gpu-cuda124-singularity
# or
docker save -o anpta_cpu_image.tar anpta:cpu-singularity
</code></pre>

Convert the docker image to a singularity container
---------------------------------------------------

**Option 1: Build directly from Docker image (recommended, works on Apple Silicon)**

You can build .sif files directly from Docker image tags using Docker itself (no need for Singularity locally):

<pre><code>
# Build GPU Singularity image (CUDA 12.4)
./scripts/build_singularity_with_docker.sh anpta:gpu-cuda124-singularity anpta-gpu-cuda124.sif

# Or use the automated script
./scripts/build_all_singularity.sh
</code></pre>

This method works on Apple Silicon and any system with Docker, as it runs Singularity/Apptainer inside a Docker container.

For detailed instructions on building Singularity images on Apple Silicon, see [docs/BUILDING_SINGULARITY_ON_APPLE_SILICON.md](docs/BUILDING_SINGULARITY_ON_APPLE_SILICON.md).

**Option 2: Build from Docker tar archive (traditional method)**

First save the Docker GPU image as a tar file:

<pre><code>
docker save -o anpta_gpu_image.tar anpta:gpu-cuda124-singularity
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
   # Version is read from VERSION file by default, or specify explicitly:
   ./scripts/push_to_sylabs.sh              # Uses VERSION file
   ./scripts/push_to_sylabs.sh v0.2.0      # Override version
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

This repository includes a ready-to-use Dev Container configuration for interactive development in VS Code.

**Setup:**
1. Copy `devcontainer/devcontainer.json` to `.devcontainer/devcontainer.json` in your project root.
2. The devcontainer uses the `*-devcontainer` target images (e.g., `vhaasteren/anpta:cpu-devcontainer`) which include VS Code tools and proper user configuration.

**Base image selection:**
- By default, uses `vhaasteren/anpta:cpu-devcontainer` (CPU variant).
- To use a GPU variant, change the `image` field in `devcontainer.json`:
  - `"image": "vhaasteren/anpta:gpu-cuda124-devcontainer"` (CUDA 12.4)
  - `"image": "vhaasteren/anpta:gpu-cuda128-devcontainer"` (CUDA 12.8)
  - `"image": "vhaasteren/anpta:gpu-cuda13-devcontainer"` (CUDA 13)

**Permissions and user mapping:**
- The devcontainer uses `--user ${localEnv:UID}:${localEnv:GID}` to run processes as your host UID/GID.
- This ensures bind-mounted files in `/workspaces/anpta` are owned by your host user.
- The `$HOME` environment variable is set to `/workspaces/anpta/.home` (created automatically) to provide a writable home directory.
- On macOS/Linux, ensure `UID` and `GID` are exported in your shell (VS Code will read them automatically):
  ```bash
  export UID=$(id -u)
  export GID=$(id -g)
  ```

**VS Code customizations:**
- The devcontainer recommends installing useful extensions (Python, Black, Ruff, Jupyter, Pylance, YAML, GitLens).
- The Python venv is auto‑activated for interactive shells.
- `ipykernel` is installed with `--sys-prefix` and registered as "Python (pta)" (kernel spec is in the venv, independent of `$HOME`).

**How to use:**
1. Open the repo in VS Code with the "Dev Containers" extension installed.
2. When prompted, "Reopen in Container" (or use the Command Palette: "Dev Containers: Reopen in Container").
3. Select the kernel "Python (pta)" in Jupyter/Notebooks.

**Notes:**
- The devcontainer is for interactive development only, not for CI or production (container user has sudo rights).
- No extra container/remote env wiring is required; the venv is on PATH and auto‑activated.
- Files created in the workspace will be owned by your host user, ensuring seamless file permissions.
- The venv is **not chowned** at build time (faster builds, instant startup).
- The kernel is installed with `--sys-prefix`, so it works regardless of `$HOME`.
- We never chown `/opt/software` (read-only system libraries).
