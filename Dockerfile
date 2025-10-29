ARG BASE_IMAGE=ubuntu:22.04
FROM ${BASE_IMAGE} AS base

LABEL maintainer="Rutger van Haasteren <rutger@vhaasteren.com>"
ENV DEBIAN_FRONTEND=noninteractive

# ---------- APT common ----------
COPY apt/common.txt /tmp/apt-common.txt
RUN --mount=type=cache,target=/var/cache/apt \
    apt-get update && xargs -a /tmp/apt-common.txt apt-get install -y --no-install-recommends && \
    rm -rf /var/lib/apt/lists/*

# ---------- PGPLOT env ----------
ENV PGPLOT_DIR=/usr/lib/pgplot5 \
    PGPLOT_FONT=/usr/lib/pgplot5/grfont.dat \
    PGPLOT_INCLUDES=/usr/include \
    PGPLOT_BACKGROUND=white \
    PGPLOT_FOREGROUND=black \
    PGPLOT_DEV=/xs

# ---------- Layout ----------
ENV SOFTWARE_DIR=/opt/software \
    VIRTUAL_ENV_BASE=/opt/venvs \
    VIRTUAL_ENV=/opt/venvs/pta \
    PATH="/opt/venvs/pta/bin:${PATH}" \
    LD_LIBRARY_PATH="/usr/local/lib:${LD_LIBRARY_PATH}" \
    OSTYPE=linux
RUN mkdir -p ${SOFTWARE_DIR} ${VIRTUAL_ENV_BASE}
WORKDIR ${SOFTWARE_DIR}

# ---------- Build scripts ----------
COPY scripts/build_healpix.sh /usr/local/bin/
COPY scripts/build_calceph.sh /usr/local/bin/
COPY scripts/build_psrcat.sh /usr/local/bin/
COPY scripts/build_tempo2.sh /usr/local/bin/
COPY scripts/update_clock_corrections.sh /usr/local/bin/
COPY scripts/build_psrchive.sh /usr/local/bin/

# ---------- HEALPix ----------
ENV HEALPIX=${SOFTWARE_DIR}/healpix \
    HEALPIX_DIR=${SOFTWARE_DIR}/healpix/install
RUN bash /usr/local/bin/build_healpix.sh
ENV PATH="${HEALPIX_DIR}/bin:${PATH}" \
    LD_LIBRARY_PATH="${HEALPIX_DIR}/lib:${LD_LIBRARY_PATH}"

# ---------- Calceph ----------
ENV CALCEPH=${SOFTWARE_DIR}/calceph-3.5.3
RUN bash /usr/local/bin/build_calceph.sh
ENV PATH="${CALCEPH}/install/bin:${PATH}" \
    LD_LIBRARY_PATH="${CALCEPH}/install/lib:${LD_LIBRARY_PATH}" \
    C_INCLUDE_PATH="${C_INCLUDE_PATH}:${CALCEPH}/install/include"

# ---------- psrcat ----------
ENV PSRCAT_FILE=${SOFTWARE_DIR}/psrcat_tar/psrcat.db
RUN bash /usr/local/bin/build_psrcat.sh
ENV PATH="${SOFTWARE_DIR}/psrcat_tar:${PATH}"

# ---------- tempo2 ----------
RUN bash /usr/local/bin/build_tempo2.sh
ENV TEMPO2=${SOFTWARE_DIR}/tempo2/T2runtime \
    TEMPO2_PREFIX=${SOFTWARE_DIR}/tempo2/T2runtime \
    PATH="${SOFTWARE_DIR}/tempo2/T2runtime/bin:${PATH}" \
    CPPFLAGS="-I${SOFTWARE_DIR}/tempo2/T2runtime/include -I${CALCEPH}/install/include ${CPPFLAGS}" \
    LDFLAGS="-L${SOFTWARE_DIR}/tempo2/T2runtime/lib -L${CALCEPH}/install/lib ${LDFLAGS}" \
    LD_LIBRARY_PATH="${SOFTWARE_DIR}/tempo2/T2runtime/lib:${CALCEPH}/install/lib:${LD_LIBRARY_PATH}"

# ---------- Python env ----------
RUN python3 -m venv ${VIRTUAL_ENV} \
 && ${VIRTUAL_ENV}/bin/pip install --upgrade pip wheel==0.43.0

# ---------- Common Python stack ----------
COPY requirements/common.txt /tmp/req-common.txt
RUN --mount=type=cache,target=/root/.cache/pip \
    ${VIRTUAL_ENV}/bin/pip install -r /tmp/req-common.txt

# ---------- PSRCHIVE (with Python bindings) ----------
RUN bash /usr/local/bin/build_psrchive.sh

# ---------- Pulsar ecosystem ----------
COPY requirements/pulsar.txt /tmp/req-pulsar.txt
RUN ${VIRTUAL_ENV}/bin/pip install -r /tmp/req-pulsar.txt

# ---------- Clock corrections ----------
RUN bash /usr/local/bin/update_clock_corrections.sh

# ---------- CPU target ----------
FROM base AS cpu
COPY requirements/jax_cpu.txt /tmp/req-jax-cpu.txt
COPY requirements/jax_common.txt /tmp/req-jax-common.txt
COPY requirements/jax_nodeps.txt /tmp/req-jax-nodeps.txt
RUN --mount=type=cache,target=/root/.cache/pip \
    ${VIRTUAL_ENV}/bin/pip install -r /tmp/req-jax-cpu.txt -r /tmp/req-jax-common.txt
RUN ${VIRTUAL_ENV}/bin/pip install --no-deps -r /tmp/req-jax-nodeps.txt
WORKDIR ${SOFTWARE_DIR}
CMD ["bash", "-lc", "source /opt/venvs/pta/bin/activate && exec bash"]

# ---------- GPU deps target ----------
FROM base AS gpu-deps
ENV CUDA_HOME=/usr/local/cuda \
    PATH=/usr/local/cuda/bin:${PATH} \
    LD_LIBRARY_PATH=/usr/local/cuda/lib64:${LD_LIBRARY_PATH}

# cuDNN from local tarball (path relative to repo root)
COPY anpta/cudnn-linux-x86_64-9.5.1.17_cuda12-archive.tar.xz /tmp
RUN cd /tmp && \
    tar -xf cudnn-linux-x86_64-9.5.1.17_cuda12-archive.tar.xz && \
    mv cudnn-linux-x86_64-9.5.1.17_cuda12-archive cudnn && \
    cp -P cudnn/include/cudnn*.h /usr/local/cuda/include && \
    cp -P cudnn/lib/libcudnn* /usr/local/cuda/lib64 && \
    chmod a+r /usr/local/cuda/include/cudnn*.h /usr/local/cuda/lib64/libcudnn* && \
    rm -rf /tmp/cudnn /tmp/cudnn-linux-x86_64-9.5.1.17_cuda12-archive.tar.xz

# CUDA forward compatibility (optional)
RUN wget -q https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-compat-12-5_555.42.02-1_amd64.deb \
 && dpkg -i cuda-compat-12-5_555.42.02-1_amd64.deb \
 && rm -f cuda-compat-12-5_555.42.02-1_amd64.deb
ENV LD_LIBRARY_PATH=/usr/local/cuda/compat/lib64:${LD_LIBRARY_PATH} \
    CUDA_COMPAT_PATH=/usr/local/cuda/compat

# GPU Python stack
COPY requirements/gpu.txt /tmp/req-gpu.txt
RUN --mount=type=cache,target=/root/.cache/pip \
    ${VIRTUAL_ENV}/bin/pip install -r /tmp/req-gpu.txt

# Torch CUDA wheels
RUN ${VIRTUAL_ENV}/bin/pip install torch==2.4.1+cu124 torchvision==0.19.1+cu124 torchaudio==2.4.1 \
    --extra-index-url https://download.pytorch.org/whl/cu124

# Torch-dependent extras installed without pulling deps
RUN ${VIRTUAL_ENV}/bin/pip install UMNN==1.70 --no-dependencies
RUN ${VIRTUAL_ENV}/bin/pip install nflows==0.14 --no-dependencies

# JAX CUDA + ecosystem
COPY requirements/jax_gpu.txt /tmp/req-jax-gpu.txt
COPY requirements/jax_common.txt /tmp/req-jax-common.txt
COPY requirements/jax_nodeps.txt /tmp/req-jax-nodeps.txt
RUN --mount=type=cache,target=/root/.cache/pip \
    ${VIRTUAL_ENV}/bin/pip install -r /tmp/req-jax-gpu.txt -r /tmp/req-jax-common.txt
RUN ${VIRTUAL_ENV}/bin/pip install --no-deps -r /tmp/req-jax-nodeps.txt

FROM gpu-deps AS gpu
WORKDIR ${SOFTWARE_DIR}
CMD ["bash", "-lc", "source /opt/venvs/pta/bin/activate && exec bash"]


