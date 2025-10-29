AEI IPTA analysis docker & singularity
======================================

Purpose
-------

This repo provides a reproducible docker image for PTA analysis. The main goal is for this image to be converted into a singularity container for use on High Throughput Clusters. The workflow is as follows

First create the docker image from the Dockerfile locally. The Dockerfile contains the instruction to use the x86_64 architecture, so that even Apple Silicon users with an arm processor can do this. Then, the docker image needs to be saved to a tarball so that it can be copied over to a computing cluster that runs singularity (in case singularity does not run locally, like on apple silicon). Then, singularity can convert the docker tarball to a singularity container.


Images and targets
------------------

This repo now uses a single Dockerfile with two build targets:

- `cpu` (BASE_IMAGE=`ubuntu:22.04`) → image tag `anpta:cpu`
- `gpu` (BASE_IMAGE=`nvidia/cuda:12.4.1-devel-ubuntu22.04`) → image tag `anpta:gpu-cu124`

Both images are functionally identical except GPU-only libraries in the GPU target (CUDA/cuDNN, torch+cu124, cupy, pycuda, JAX CUDA).

Build with docker compose profiles (recommended)
-----------------------------------------------

The single `docker-compose.yml` defines two services guarded by profiles.

GPU build/run:

<pre><code>
docker compose --profile gpu build
docker compose --profile gpu run --rm anpta bash
</code></pre>

CPU build/run (Apple Silicon or CPU-only):

<pre><code>
docker compose --profile cpu build
docker compose --profile cpu run --rm anpta-cpu bash
</code></pre>

Build directly with docker buildx (optional)
--------------------------------------------

CPU (multi-arch example):

<pre><code>
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --target cpu \
  -t anpta:cpu \
  --build-arg BASE_IMAGE=ubuntu:22.04 \
  .
</code></pre>

GPU (amd64):

<pre><code>
docker buildx build \
  --platform linux/amd64 \
  --target gpu \
  -t anpta:gpu-cu124 \
  --build-arg BASE_IMAGE=nvidia/cuda:12.4.1-devel-ubuntu22.04 \
  .
</code></pre>


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
docker save -o anpta_gpu_image.tar anpta:gpu-cu124
# or
docker save -o anpta_cpu_image.tar anpta:cpu
</code></pre>

Convert the docker image to a singularity container
---------------------------------------------------

This needs to be done on a node that has singularity installed

<pre><code>
singularity build anpta.sif docker-archive://anpta_gpu_image.tar
# or
singularity build anpta.sif docker-archive://anpta_cpu_image.tar
</code></pre>


The container can be tested with
--------------------------------

<pre><code>
singularity exec --bind /work/rutger.vhaasteren/:/data/ anpta.sif bash
</code></pre>


