# ANPTA - Pulsar Timing Array Analysis Container

[![GitHub stars](https://img.shields.io/github/stars/vhaasteren/anpta_containers?style=flat-square&logo=github)](https://github.com/vhaasteren/anpta_containers)
[![GitHub forks](https://img.shields.io/github/forks/vhaasteren/anpta_containers?style=flat-square&logo=github)](https://github.com/vhaasteren/anpta_containers)
[![GitHub release](https://img.shields.io/github/v/release/vhaasteren/anpta_containers?style=flat-square&logo=github)](https://github.com/vhaasteren/anpta_containers/releases)
[![Docker Pulls](https://img.shields.io/docker/pulls/vhaasteren/anpta?style=flat-square&logo=docker&logoColor=white)](https://hub.docker.com/r/vhaasteren/anpta)
[![Docker Image Size](https://img.shields.io/docker/image-size/vhaasteren/anpta/cpu?style=flat-square&logo=docker&logoColor=white)](https://hub.docker.com/r/vhaasteren/anpta)
[![GitHub issues](https://img.shields.io/github/issues/vhaasteren/anpta_containers?style=flat-square&logo=github)](https://github.com/vhaasteren/anpta_containers/issues)
[![GitHub](https://img.shields.io/github/license/vhaasteren/anpta_containers?style=flat-square)](https://github.com/vhaasteren/anpta_containers)

A comprehensive Docker container for Pulsar Timing Array (PTA) analysis, providing a reproducible environment with all necessary scientific computing tools, pulsar software, and GPU acceleration support.

## 🚀 Quick Start

```bash
# Pull the CPU variant (multi-arch: amd64/arm64)
docker pull vhaasteren/anpta:cpu

# Pull GPU variants (amd64 only)
docker pull vhaasteren/anpta:gpu-cuda124  # CUDA 12.4
docker pull vhaasteren/anpta:gpu-cuda128  # CUDA 12.8
docker pull vhaasteren/anpta:gpu-cuda13   # CUDA 13

# Run interactively with automatic UID/GID mapping
docker run --rm -it \
  -e HOST_UID=$(id -u) -e HOST_GID=$(id -g) \
  -v $(pwd):/work -w /work \
  vhaasteren/anpta:cpu bash
```

## 📦 Available Variants

This repository provides three types of container variants for different use cases:

### Unified Runtime (Docker & Dev Containers)
| Tag | Description | Platforms | Base OS | Use Case |
|-----|-------------|-----------|---------|----------|
| `cpu` | CPU-optimized (unified image) | `linux/amd64`, `linux/arm64` | Ubuntu 24.04 | Standalone Docker runs & VS Code Dev Containers |
| `gpu-cuda124` | GPU CUDA 12.4 (unified image) | `linux/amd64` | Ubuntu 22.04 | CUDA 12.4 workloads, ML/AI, Dev Containers |
| `gpu-cuda128` | GPU CUDA 12.8 (unified image) | `linux/amd64` | Ubuntu 24.04 | CUDA 12.8 workloads, ML/AI, Dev Containers |
| `gpu-cuda13` | GPU CUDA 13 (unified image) | `linux/amd64` | Ubuntu 24.04 | CUDA 13 workloads, ML/AI, Dev Containers |

### Singularity/Apptainer Conversion
| Tag | Description | Platforms | Base OS | Use Case |
|-----|-------------|-----------|---------|----------|
| `cpu-singularity` | CPU (root user) | `linux/amd64`, `linux/arm64` | Ubuntu 24.04 | Singularity/Apptainer conversion |
| `gpu-cuda124-singularity` | GPU CUDA 12.4 (root user) | `linux/amd64` | Ubuntu 22.04 | Singularity/Apptainer conversion |
| `gpu-cuda128-singularity` | GPU CUDA 12.8 (root user) | `linux/amd64` | Ubuntu 24.04 | Singularity/Apptainer conversion |
| `gpu-cuda13-singularity` | GPU CUDA 13 (root user) | `linux/amd64` | Ubuntu 24.04 | Singularity/Apptainer conversion |

**Note:** The unified runtime images automatically remap the container user to match your host UID/GID via an entrypoint script, ensuring correct file permissions on bind-mounted volumes. The same image works for both direct Docker usage and VS Code Dev Containers.

## 🔬 Included Software Stack

### Pulsar Software
- **tempo2** - Pulsar timing with tempo2, libstempo
- **PINT** - Pulsar timing with PINT, pint-pal, 
- **PSRCHIVE** - Pulsar data analysis suite with Python bindings
- **HEALPix** - Hierarchical Equal Area isoLatitude Pixelation for sky maps
- **psrcat** - ATNF Pulsar Catalogue database
- **Calceph** - Ephemeris computation library
- **Enterprise** - Pulsar timing array analysis with enterprise_extensions, enterprise_warp, fastshermanmorrison, QuickCW
- **Samplers** - ptmcmcsampler, emcee, bilby, dynesty, polychord, nestle
- **Discovery** - Pulsar timing array analysis
- **GPU tools** - Torch, JAX, pycuda, cupy, flax, flowjax
- **More!** - Check the `requirements` files for the exact packages and versions

### Python Scientific Stack
- **NumPy 2.3.4, SciPy 1.16.3, Matplotlib 3.10.7** - Core scientific computing
- **Astropy 7.1.1** - Astronomy and astrophysics library
- **JAX** (CPU/GPU) - High-performance machine learning
  - CPU: JAX 0.8.0
  - GPU CUDA 12.4: JAX 0.4.26 (with cuDNN 8.9 compatibility)
  - GPU CUDA 12.8/13: JAX 0.8.0
- **PyTorch** (GPU only) - Deep learning framework
  - CUDA 12.4: PyTorch 2.3.1+cu121
  - CUDA 12.8: PyTorch 2.9.0+cu128
  - CUDA 13: PyTorch 2.9.0+cu130
- **Cupy** (GPU only) - NumPy-like library for GPU arrays
  - CUDA 12.4/12.8: cupy-cuda12x 13.6.0
  - CUDA 13: cupy-cuda13x 13.6.0
- **PyCUDA 2025.1.2** (GPU only) - GPU computing with CUDA

### System Libraries
- **CUDA** (GPU variants)
  - CUDA 12.4.0 (Ubuntu 22.04) with cuDNN 8.9
  - CUDA 12.8.1 (Ubuntu 24.04) with cuDNN 9.x
  - CUDA 13.0.1 (Ubuntu 24.04) with cuDNN 9.x
- **Python 3.12** (Ubuntu 24.04) or **Python 3.11** (Ubuntu 22.04)
- **FFTW3** - Fast Fourier Transform library
- **GSL** - GNU Scientific Library
- **OpenMPI** - Message passing interface
- **PGPLOT** - Graphics subroutine library

## 💻 Usage Examples

### Basic Interactive Session (with UID/GID mapping)

The direct usage targets automatically remap the container user to match your host UID/GID:

```bash
# CPU variant
docker run --rm -it \
  -e HOST_UID=$(id -u) -e HOST_GID=$(id -g) \
  -v $(pwd):/work -w /work \
  vhaasteren/anpta:cpu bash

# GPU variant (CUDA 12.4)
docker run --rm -it \
  -e HOST_UID=$(id -u) -e HOST_GID=$(id -g) \
  -v $(pwd):/work -w /work \
  --gpus all \
  vhaasteren/anpta:gpu-cuda124 bash
```

**Note:** The entrypoint script (`entrypoint-uidmap.sh`) automatically:
- Remaps the `anpta` user's UID/GID to match your host
- Ensures the home directory is properly owned
- **Does not chown the virtual environment** (startup is instant)
- Redirects `pip install` to `/work/.pyuser` by default (fast, no permissions issues)
- Redirects Python bytecode cache to `/work/.pycache`

### Running Python Scripts

```bash
docker run --rm \
  -e HOST_UID=$(id -u) -e HOST_GID=$(id -g) \
  -v $(pwd):/work -w /work \
  vhaasteren/anpta:cpu python /work/your_script.py
```

### Installing Python Packages

By default, packages install to the workspace (fast, no permissions issues):

```bash
docker run --rm -it \
  -e HOST_UID=$(id -u) -e HOST_GID=$(id -g) \
  -v $(pwd):/work -w /work \
  vhaasteren/anpta:cpu bash

# Inside container:
pip install <package>         # installs into /work/.pyuser
python -c "import <package>"  # works immediately
```

If you *must* install into the baked virtualenv (slower, opt-in):

```bash
docker run --rm -it \
  -e HOST_UID=$(id -u) -e HOST_GID=$(id -g) \
  -e VENV_WRITABLE=1 \
  -v $(pwd):/work -w /work \
  vhaasteren/anpta:cpu bash

# Inside container:
pip install -e .
```

### GPU-Accelerated Computing

```bash
# Requires NVIDIA Docker runtime
# CUDA 12.4 (Ubuntu 22.04)
docker run --rm -it \
  -e HOST_UID=$(id -u) -e HOST_GID=$(id -g) \
  -v $(pwd):/work -w /work \
  --gpus all \
  vhaasteren/anpta:gpu-cuda124 bash

# CUDA 12.8 (Ubuntu 24.04)
docker run --rm -it \
  -e HOST_UID=$(id -u) -e HOST_GID=$(id -g) \
  -v $(pwd):/work -w /work \
  --gpus all \
  vhaasteren/anpta:gpu-cuda128 bash

# CUDA 13 (Ubuntu 24.04)
docker run --rm -it \
  -e HOST_UID=$(id -u) -e HOST_GID=$(id -g) \
  -v $(pwd):/work -w /work \
  --gpus all \
  vhaasteren/anpta:gpu-cuda13 bash

# Test CUDA
docker run --rm --gpus all \
  -e HOST_UID=$(id -u) -e HOST_GID=$(id -g) \
  vhaasteren/anpta:gpu-cuda124 python -c "import torch; print(torch.cuda.is_available())"
docker run --rm --gpus all \
  -e HOST_UID=$(id -u) -e HOST_GID=$(id -g) \
  vhaasteren/anpta:gpu-cuda128 python -c "import torch; print(torch.cuda.is_available())"
docker run --rm --gpus all \
  -e HOST_UID=$(id -u) -e HOST_GID=$(id -g) \
  vhaasteren/anpta:gpu-cuda13 python -c "import torch; print(torch.cuda.is_available())"
```

### Jupyter Notebook

```bash
docker run --rm -it -p 8888:8888 \
  -e HOST_UID=$(id -u) -e HOST_GID=$(id -g) \
  -v $(pwd):/work -w /work \
  vhaasteren/anpta:cpu \
  jupyter notebook --ip=0.0.0.0 --port=8888 --no-browser
```

## 🏷️ Tagging Strategy

### Immutable Version Tags
Use these for reproducible builds (v0.2.0):
- `v0.2.0-cpu-ubuntu24.04`
- `v0.2.0-cpu-singularity-ubuntu24.04`
- `v0.2.0-gpu-cuda124-ubuntu22.04`
- `v0.2.0-gpu-cuda124-singularity-ubuntu22.04`
- `v0.2.0-gpu-cuda128-ubuntu24.04`
- `v0.2.0-gpu-cuda128-singularity-ubuntu24.04`
- `v0.2.0-gpu-cuda13-ubuntu24.04`
- `v0.2.0-gpu-cuda13-singularity-ubuntu24.04`

### Moving Aliases (Latest Stable)
Use these for the most recent stable release:
- `cpu` → Latest CPU unified runtime variant (Ubuntu 24.04)
- `cpu-singularity` → Latest CPU Singularity variant (Ubuntu 24.04)
- `gpu-cuda124` → Latest GPU CUDA 12.4 unified runtime variant (Ubuntu 22.04)
- `gpu-cuda124-singularity` → Latest GPU CUDA 12.4 Singularity variant
- `gpu-cuda128` → Latest GPU CUDA 12.8 unified runtime variant (Ubuntu 24.04)
- `gpu-cuda128-singularity` → Latest GPU CUDA 12.8 Singularity variant
- `gpu-cuda13` → Latest GPU CUDA 13 unified runtime variant (Ubuntu 24.04)
- `gpu-cuda13-singularity` → Latest GPU CUDA 13 Singularity variant

**Recommendation:** Use immutable version tags for production workflows to ensure reproducibility.

## 🔄 Converting to Singularity

Only the **GPU variants** are converted to Singularity `.sif` files, as HPC clusters are typically x86_64. You can build or pull `.sif` files directly from Docker Hub:

```bash
apptainer pull anpta-gpu-cuda124.sif docker://vhaasteren/anpta:gpu-cuda124-singularity  # CUDA 12.4
apptainer pull anpta-gpu-cuda128.sif docker://vhaasteren/anpta:gpu-cuda128-singularity  # CUDA 12.8
apptainer pull anpta-gpu-cuda13.sif  docker://vhaasteren/anpta:gpu-cuda13-singularity   # CUDA 13
```

**Note:** CPU singularity images are not converted to `.sif` files since HPC clusters typically use x86_64 architecture. While Apptainer supports ARM64 Linux, it doesn't run on macOS (Apple Silicon). For automated conversion, see the repository's `build_all_singularity.sh` script.

For detailed instructions, see the [repository documentation](https://github.com/vhaasteren/anpta_containers).

## 🐳 Dev Containers (VS Code)

These images are designed for use with VS Code Dev Containers. The repository includes a ready-to-use `devcontainer.json` configuration.

**Quick Setup:**
1. Copy `devcontainer/devcontainer.json` to `.devcontainer/devcontainer.json` in your project root.
2. Ensure `UID` and `GID` are exported in your shell (VS Code will read them automatically):
   ```bash
   export UID=$(id -u)
   export GID=$(id -g)
   ```
3. Open the project in VS Code and select "Reopen in Container" when prompted.

**Features:**
- Uses the unified runtime images (e.g., `vhaasteren/anpta:cpu`)
- Automatic UID/GID matching via entrypoint script using `HOST_UID`/`HOST_GID` environment variables for correct file permissions
- Writable `$HOME` directory at `/workspaces/${localWorkspaceFolderBasename}/.home` (created automatically)
- Pre-configured with Python, Jupyter, and development extensions
- Python virtual environment auto-activated
- `ipykernel` installed with `--sys-prefix` in the shared parent layer (kernel spec in venv, independent of `$HOME`)

**Base Image Selection:**
- Default: `vhaasteren/anpta:cpu` (CPU variant)
- For GPU: Change `image` field to:
  - `vhaasteren/anpta:gpu-cuda124` (CUDA 12.4)
  - `vhaasteren/anpta:gpu-cuda128` (CUDA 12.8)
  - `vhaasteren/anpta:gpu-cuda13` (CUDA 13)

**Permissions:**
- Files created in the workspace will be owned by your host user
- The devcontainer uses the entrypoint script to remap UID/GID at runtime (no `--user` flag needed)
- No manual permission fixes needed
- The venv is **not chowned** at build time (faster builds, instant startup)
- The kernel is installed with `--sys-prefix` in the shared parent layer, so it works regardless of `$HOME`
- We never chown `/opt/software` (read-only system libraries)

**Notes:**
- Container startup is instant (no venv chowning at runtime)
- Python packages can be installed into the workspace using `pip install` (goes to workspace `.pyuser` directory via `.pth` shim)
- Python bytecode cache is redirected to workspace `.pycache` directory
- The same image works for both `docker run` and devcontainers

For detailed setup instructions, see the repository's `README.md` and `devcontainer/` directory.

## 📊 Image Sizes

- **CPU variants:** ~4-6 GB
- **GPU variants:** ~15-25 GB (includes CUDA, cuDNN, PyTorch, JAX)
  - CUDA 12.4: ~20-25 GB (includes cuDNN 8.9)
  - CUDA 12.8/13: ~15-20 GB (cuDNN included in base image)

## 🔗 Links

- **Source Repository:** [GitHub](https://github.com/vhaasteren/anpta_containers)
- **Documentation:** See repository README and `docs/` directory
- **Issues:** [Report issues on GitHub](https://github.com/vhaasteren/anpta_containers/issues)

## 📝 License

Please refer to the licenses of the included software packages. The container itself is provided as-is for research and academic use.

## 👤 Maintainer

Rutger van Haasteren <rutger@vhaasteren.com>

---

**For detailed build instructions, publishing workflow, and advanced usage, please refer to the [full repository documentation](https://github.com/vhaasteren/anpta_containers).**

