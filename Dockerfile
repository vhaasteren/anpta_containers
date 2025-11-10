ARG BASE_IMAGE=ubuntu:24.04
FROM ${BASE_IMAGE} AS base

LABEL maintainer="Rutger van Haasteren <rutger@vhaasteren.com>"
ENV DEBIAN_FRONTEND=noninteractive

# ---------- APT common ----------
COPY apt/common.txt /tmp/apt-common.txt
RUN apt-get update && xargs -a /tmp/apt-common.txt apt-get install -y --no-install-recommends && \
    rm -rf /var/lib/apt/lists/*

# ---------- Python 3.11 (if available) ----------
# Try to install python3.11 for Ubuntu 22.04 (will fail gracefully on Ubuntu 24.04 where it doesn't exist)
RUN apt-get update && \
    (apt-get install -y --no-install-recommends python3.11 python3.11-venv python3.11-dev 2>/dev/null || true) && \
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
ENV PATH="${HEALPIX_DIR}/bin:${PATH}" \
    LD_LIBRARY_PATH="${HEALPIX_DIR}/lib:${LD_LIBRARY_PATH}"
RUN bash /usr/local/bin/build_healpix.sh

# ---------- Calceph ----------
ENV CALCEPH=${SOFTWARE_DIR}/calceph
ENV PATH="${CALCEPH}/install/bin:${PATH}" \
    LD_LIBRARY_PATH="${CALCEPH}/install/lib:${LD_LIBRARY_PATH}" \
    C_INCLUDE_PATH="${C_INCLUDE_PATH}:${CALCEPH}/install/include"
RUN bash /usr/local/bin/build_calceph.sh

# ---------- psrcat ----------
ENV PSRCAT_FILE=${SOFTWARE_DIR}/psrcat_tar/psrcat.db
ENV PATH="${SOFTWARE_DIR}/psrcat_tar:${PATH}"
RUN bash /usr/local/bin/build_psrcat.sh

# ---------- tempo2 ----------
ENV TEMPO2=${SOFTWARE_DIR}/tempo2/T2runtime \
    PATH="${SOFTWARE_DIR}/tempo2/install/bin:${SOFTWARE_DIR}/tempo2/T2runtime/bin:${PATH}" \
    CPPFLAGS="-I${SOFTWARE_DIR}/tempo2/install/include -I${CALCEPH}/install/include ${CPPFLAGS}" \
    LDFLAGS="-L${SOFTWARE_DIR}/tempo2/install/lib -L${CALCEPH}/install/lib ${LDFLAGS}" \
    LD_LIBRARY_PATH="${SOFTWARE_DIR}/tempo2/install/lib:${SOFTWARE_DIR}/tempo2/T2runtime/lib:${CALCEPH}/install/lib:${LD_LIBRARY_PATH}"
RUN bash /usr/local/bin/build_tempo2.sh

# ---------- Python env ----------
# Use highest available Python 3.x version (python3.11 on Ubuntu 22.04, python3.12 on Ubuntu 24.04)
RUN PYTHON3=$(ls -1 /usr/bin/python3.* 2>/dev/null | grep -E 'python3\.[0-9]+$' | sort -V | tail -1 || which python3) && \
    ${PYTHON3} -m venv ${VIRTUAL_ENV} && \
    ${VIRTUAL_ENV}/bin/pip install --upgrade pip wheel==0.43.0

# ---------- Common Python stack ----------
COPY requirements/common.txt /tmp/req-common.txt
RUN ${VIRTUAL_ENV}/bin/pip install -r /tmp/req-common.txt

# ---------- PSRCHIVE (with Python bindings) ----------
ENV CPPFLAGS="-I${SOFTWARE_DIR}/tempo2/install/include -I${CALCEPH}/install/include -I${HEALPIX_DIR}/include/healpix_cxx ${CPPFLAGS}" \
    LDFLAGS="-L${SOFTWARE_DIR}/tempo2/install/lib -L${CALCEPH}/install/lib -L${HEALPIX_DIR}/lib ${LDFLAGS}" \
    HEALPIX="${HEALPIX_DIR}"
RUN bash /usr/local/bin/build_psrchive.sh
ENV PATH="${SOFTWARE_DIR}/psrchive/install/bin:${PATH}" \
    LD_LIBRARY_PATH="${SOFTWARE_DIR}/psrchive/install/lib:${LD_LIBRARY_PATH}"

# ---------- Pulsar ecosystem ----------
COPY requirements/pulsar.txt /tmp/req-pulsar.txt
RUN ${VIRTUAL_ENV}/bin/pip install -r /tmp/req-pulsar.txt

# ---------- Clock corrections ----------
RUN bash /usr/local/bin/update_clock_corrections.sh

# ---------- CPU target ----------
FROM base AS cpu-singularity
COPY requirements/cpu.txt /tmp/req-cpu.txt
RUN ${VIRTUAL_ENV}/bin/pip install -r /tmp/req-cpu.txt
WORKDIR ${SOFTWARE_DIR}
CMD ["bash", "-lc", "source /opt/venvs/pta/bin/activate && exec bash"]


# ---------- GPU deps target (CUDA 12.4) ----------
FROM base AS gpu-deps-cuda124
ENV CUDA_HOME=/usr/local/cuda \
    PATH=/usr/local/cuda/bin:${PATH} \
    LD_LIBRARY_PATH=/usr/local/cuda/lib64:${LD_LIBRARY_PATH}

# GPU Python stack (CUDA 12.4)
COPY requirements/gpu_cuda124.txt /tmp/req-gpu-cuda124.txt
RUN ${VIRTUAL_ENV}/bin/pip install -r /tmp/req-gpu-cuda124.txt

FROM gpu-deps-cuda124 AS gpu-cuda124-singularity
WORKDIR ${SOFTWARE_DIR}
CMD ["bash", "-lc", "source /opt/venvs/pta/bin/activate && exec bash"]


# ---------- GPU deps target (CUDA 12.8) ----------
FROM base AS gpu-deps-cuda128
ENV CUDA_HOME=/usr/local/cuda \
    PATH=/usr/local/cuda/bin:${PATH} \
    LD_LIBRARY_PATH=/usr/local/cuda/lib64:${LD_LIBRARY_PATH}

# GPU Python stack (CUDA 12.8)
COPY requirements/gpu_cuda128.txt /tmp/req-gpu-cuda128.txt
RUN ${VIRTUAL_ENV}/bin/pip install -r /tmp/req-gpu-cuda128.txt

FROM gpu-deps-cuda128 AS gpu-cuda128-singularity
WORKDIR ${SOFTWARE_DIR}
CMD ["bash", "-lc", "source /opt/venvs/pta/bin/activate && exec bash"]


# ---------- GPU deps target (CUDA 13) ----------
FROM base AS gpu-deps-cuda13
ENV CUDA_HOME=/usr/local/cuda \
    PATH=/usr/local/cuda/bin:${PATH} \
    LD_LIBRARY_PATH=/usr/local/cuda/lib64:${LD_LIBRARY_PATH}

# GPU Python stack (CUDA 13)
COPY requirements/gpu_cuda13.txt /tmp/req-gpu-cuda13.txt
RUN ${VIRTUAL_ENV}/bin/pip install -r /tmp/req-gpu-cuda13.txt

FROM gpu-deps-cuda13 AS gpu-cuda13-singularity
WORKDIR ${SOFTWARE_DIR}
CMD ["bash", "-lc", "source /opt/venvs/pta/bin/activate && exec bash"]


# ---------- CPU docker (devcontainer, non-root) ----------
FROM cpu-singularity AS cpu-devcontainer
RUN useradd -m -s /bin/bash anpta \
 && apt-get update && apt-get install -y --no-install-recommends sudo ca-certificates curl wget gnupg lsb-release \
 && echo 'test -f "/opt/venvs/pta/bin/activate" && . "/opt/venvs/pta/bin/activate"' >> /home/anpta/.bashrc \
 && chown -R anpta:anpta /home/anpta \
 && rm -rf /var/lib/apt/lists/*
# Install ipykernel as root (build-time, needs write access to venv)
RUN /opt/venvs/pta/bin/pip install --no-cache-dir ipykernel \
 && /opt/venvs/pta/bin/python -m ipykernel install --sys-prefix --name pta --display-name "Python (pta)"
USER anpta
WORKDIR /home/anpta
ENV VIRTUAL_ENV="/opt/venvs/pta" \
    PATH="/opt/venvs/pta/bin:${PATH}"

# ---------- CPU docker (direct usage, UID-mapped) ----------
FROM cpu-singularity AS cpu
RUN useradd -m -s /bin/bash anpta \
 && echo 'test -f "/opt/venvs/pta/bin/activate" && . "/opt/venvs/pta/bin/activate"' >> /home/anpta/.bashrc \
 && mkdir -p /work
# tiny, robust init + privilege dropper
RUN apt-get update \
 && apt-get install -y --no-install-recommends gosu tini \
 && rm -rf /var/lib/apt/lists/*
COPY scripts/entrypoint-uidmap.sh /usr/local/bin/entrypoint-uidmap.sh
RUN chmod +x /usr/local/bin/entrypoint-uidmap.sh
WORKDIR /work
ENV VIRTUAL_ENV="/opt/venvs/pta" \
    PATH="/opt/venvs/pta/bin:${PATH}"
ENTRYPOINT ["tini","--","/usr/local/bin/entrypoint-uidmap.sh"]
CMD ["bash", "-lc", "source /opt/venvs/pta/bin/activate && exec bash"]

# ---------- GPU docker (devcontainer, non-root, CUDA 12.4) ----------
FROM gpu-cuda124-singularity AS gpu-cuda124-devcontainer
RUN useradd -m -s /bin/bash anpta \
 && apt-get update && apt-get install -y --no-install-recommends sudo ca-certificates curl wget gnupg lsb-release \
 && echo 'test -f "/opt/venvs/pta/bin/activate" && . "/opt/venvs/pta/bin/activate"' >> /home/anpta/.bashrc \
 && chown -R anpta:anpta /home/anpta \
 && rm -rf /var/lib/apt/lists/*
# Install ipykernel as root (build-time, needs write access to venv)
RUN /opt/venvs/pta/bin/pip install --no-cache-dir ipykernel \
 && /opt/venvs/pta/bin/python -m ipykernel install --sys-prefix --name pta --display-name "Python (pta)"
USER anpta
WORKDIR /home/anpta
ENV VIRTUAL_ENV="/opt/venvs/pta" \
    PATH="/opt/venvs/pta/bin:${PATH}"

# ---------- GPU docker (direct usage, UID-mapped, CUDA 12.4) ----------
FROM gpu-cuda124-singularity AS gpu-cuda124
RUN useradd -m -s /bin/bash anpta \
 && echo 'test -f "/opt/venvs/pta/bin/activate" && . "/opt/venvs/pta/bin/activate"' >> /home/anpta/.bashrc \
 && mkdir -p /work
RUN apt-get update \
 && apt-get install -y --no-install-recommends gosu tini \
 && rm -rf /var/lib/apt/lists/*
COPY scripts/entrypoint-uidmap.sh /usr/local/bin/entrypoint-uidmap.sh
RUN chmod +x /usr/local/bin/entrypoint-uidmap.sh
WORKDIR /work
ENV VIRTUAL_ENV="/opt/venvs/pta" \
    PATH="/opt/venvs/pta/bin:${PATH}"
ENTRYPOINT ["tini","--","/usr/local/bin/entrypoint-uidmap.sh"]
CMD ["bash", "-lc", "source /opt/venvs/pta/bin/activate && exec bash"]

# ---------- GPU docker (devcontainer, non-root, CUDA 12.8) ----------
FROM gpu-cuda128-singularity AS gpu-cuda128-devcontainer
RUN useradd -m -s /bin/bash anpta \
 && apt-get update && apt-get install -y --no-install-recommends sudo ca-certificates curl wget gnupg lsb-release \
 && echo 'test -f "/opt/venvs/pta/bin/activate" && . "/opt/venvs/pta/bin/activate"' >> /home/anpta/.bashrc \
 && chown -R anpta:anpta /home/anpta \
 && rm -rf /var/lib/apt/lists/*
# Install ipykernel as root (build-time, needs write access to venv)
RUN /opt/venvs/pta/bin/pip install --no-cache-dir ipykernel \
 && /opt/venvs/pta/bin/python -m ipykernel install --sys-prefix --name pta --display-name "Python (pta)"
USER anpta
WORKDIR /home/anpta
ENV VIRTUAL_ENV="/opt/venvs/pta" \
    PATH="/opt/venvs/pta/bin:${PATH}"

# ---------- GPU docker (direct usage, UID-mapped, CUDA 12.8) ----------
FROM gpu-cuda128-singularity AS gpu-cuda128
RUN useradd -m -s /bin/bash anpta \
 && echo 'test -f "/opt/venvs/pta/bin/activate" && . "/opt/venvs/pta/bin/activate"' >> /home/anpta/.bashrc \
 && mkdir -p /work
RUN apt-get update \
 && apt-get install -y --no-install-recommends gosu tini \
 && rm -rf /var/lib/apt/lists/*
COPY scripts/entrypoint-uidmap.sh /usr/local/bin/entrypoint-uidmap.sh
RUN chmod +x /usr/local/bin/entrypoint-uidmap.sh
WORKDIR /work
ENV VIRTUAL_ENV="/opt/venvs/pta" \
    PATH="/opt/venvs/pta/bin:${PATH}"
ENTRYPOINT ["tini","--","/usr/local/bin/entrypoint-uidmap.sh"]
CMD ["bash", "-lc", "source /opt/venvs/pta/bin/activate && exec bash"]

# ---------- GPU docker (devcontainer, non-root, CUDA 13) ----------
FROM gpu-cuda13-singularity AS gpu-cuda13-devcontainer
RUN useradd -m -s /bin/bash anpta \
 && apt-get update && apt-get install -y --no-install-recommends sudo ca-certificates curl wget gnupg lsb-release \
 && echo 'test -f "/opt/venvs/pta/bin/activate" && . "/opt/venvs/pta/bin/activate"' >> /home/anpta/.bashrc \
 && chown -R anpta:anpta /home/anpta \
 && rm -rf /var/lib/apt/lists/*
# Install ipykernel as root (build-time, needs write access to venv)
RUN /opt/venvs/pta/bin/pip install --no-cache-dir ipykernel \
 && /opt/venvs/pta/bin/python -m ipykernel install --sys-prefix --name pta --display-name "Python (pta)"
USER anpta
WORKDIR /home/anpta
ENV VIRTUAL_ENV="/opt/venvs/pta" \
    PATH="/opt/venvs/pta/bin:${PATH}"

# ---------- GPU docker (direct usage, UID-mapped, CUDA 13) ----------
FROM gpu-cuda13-singularity AS gpu-cuda13
RUN useradd -m -s /bin/bash anpta \
 && echo 'test -f "/opt/venvs/pta/bin/activate" && . "/opt/venvs/pta/bin/activate"' >> /home/anpta/.bashrc \
 && mkdir -p /work
RUN apt-get update \
 && apt-get install -y --no-install-recommends gosu tini \
 && rm -rf /var/lib/apt/lists/*
COPY scripts/entrypoint-uidmap.sh /usr/local/bin/entrypoint-uidmap.sh
RUN chmod +x /usr/local/bin/entrypoint-uidmap.sh
WORKDIR /work
ENV VIRTUAL_ENV="/opt/venvs/pta" \
    PATH="/opt/venvs/pta/bin:${PATH}"
ENTRYPOINT ["tini","--","/usr/local/bin/entrypoint-uidmap.sh"]
CMD ["bash", "-lc", "source /opt/venvs/pta/bin/activate && exec bash"]
