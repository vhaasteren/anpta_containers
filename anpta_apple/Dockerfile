FROM ubuntu:22.04

LABEL maintainer="Rutger van Haasteren <rutger@vhaasteren.com>"
ENV DEBIAN_FRONTEND=noninteractive

# ---------- Base build/runtime deps ----------
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential autoconf automake libtool pkg-config cmake \
    git wget curl ca-certificates \
    csh swig \
    gcc gfortran \
    libfftw3-dev libx11-dev libltdl-dev \
    gsl-bin libgsl-dev \
    liblapack-dev libblas-dev libopenblas-dev \
    libcfitsio-dev zlib1g-dev \
    libsuitesparse-dev \
    libopenmpi-dev \
    libsharp-dev \
    pgplot5 xorg \
    python3 python3-venv python3-dev python3-pip \
    nano vim tmux \
    && rm -rf /var/lib/apt/lists/*

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
    LD_LIBRARY_PATH="/usr/local/lib:${LD_LIBRARY_PATH}"
RUN mkdir -p ${SOFTWARE_DIR} ${VIRTUAL_ENV_BASE}

# Bring in shared build scripts and shared requirements
COPY scripts/build_healpix.sh /usr/local/bin/
COPY scripts/build_calceph.sh /usr/local/bin/
COPY scripts/build_psrcat.sh /usr/local/bin/
COPY scripts/build_tempo2.sh /usr/local/bin/
COPY scripts/update_clock_corrections.sh /usr/local/bin/
COPY requirements/pulsar.txt /tmp/req-pulsar.txt

# ---------- HEALPix C++ (optional but useful) ----------
ENV HEALPIX=${SOFTWARE_DIR}/healpix \
    HEALPIX_DIR=${SOFTWARE_DIR}/healpix/install
RUN mkdir -p ${HEALPIX}
RUN bash /usr/local/bin/build_healpix.sh
ENV PATH="${HEALPIX_DIR}/bin:${PATH}" \
    LD_LIBRARY_PATH="${HEALPIX_DIR}/lib:${LD_LIBRARY_PATH}"

# ---------- Calceph ----------
ENV CALCEPH=${SOFTWARE_DIR}/calceph-3.5.3
WORKDIR ${SOFTWARE_DIR}
RUN bash /usr/local/bin/build_calceph.sh
ENV PATH="${CALCEPH}/install/bin:${PATH}" \
    LD_LIBRARY_PATH="${CALCEPH}/install/lib:${LD_LIBRARY_PATH}" \
    C_INCLUDE_PATH="${C_INCLUDE_PATH}:${CALCEPH}/install/include"

# ---------- psrcat ----------
ENV PSRCAT_FILE=${SOFTWARE_DIR}/psrcat_tar/psrcat.db
WORKDIR ${SOFTWARE_DIR}
RUN bash /usr/local/bin/build_psrcat.sh

# ---------- tempo2 (double precision; no float128) ----------
ENV TEMPO2=${SOFTWARE_DIR}/tempo2/T2runtime
RUN bash /usr/local/bin/build_tempo2.sh
# Make sure libstempo finds headers/libs under T2runtime
ENV TEMPO2_PREFIX=${TEMPO2} \
    PATH="${TEMPO2}/bin:${PATH}" \
    CPPFLAGS="-I${TEMPO2}/include -I${CALCEPH}/install/include ${CPPFLAGS}" \
    LDFLAGS="-L${TEMPO2}/lib -L${CALCEPH}/install/lib ${LDFLAGS}" \
    LD_LIBRARY_PATH="${TEMPO2}/lib:${CALCEPH}/install/lib:${LD_LIBRARY_PATH}"

# ---------- Optional: PSRCHIVE (OFF by default) ----------
ARG WITH_PSRCHIVE=0
RUN if [ "${WITH_PSRCHIVE}" = "1" ]; then \
      cd ${SOFTWARE_DIR} && \
      git clone --depth=1 git://git.code.sf.net/p/psrchive/code psrchive && \
      cd psrchive && \
      ./bootstrap && \
      ./configure --enable-shared && \
      make -j"$(nproc)" && make check && make install && \
      cd .. && rm -rf psrchive ; \
    fi

# ---------- Python env ----------
RUN python3 -m venv ${VIRTUAL_ENV} \
 && ${VIRTUAL_ENV}/bin/pip install --upgrade pip wheel==0.43.0

# Core numerical stack (arm64 wheels exist)
RUN ${VIRTUAL_ENV}/bin/pip install \
    numpy==1.26.4 \
    scipy==1.13.1 \
    matplotlib==3.8.4 \
    astropy==6.0.1 \
    healpy==1.16.6 \
    cython==3.0.10 \
    xarray==2023.10.1 \
    arviz==0.16.1 \
    tqdm==4.66.4 \
    ipdb==0.13.13 \
    natsort==8.4.0 \
    scikit-sparse==0.4.16 \
    scikit-learn==1.5.2 \
    scikit-optimize==0.9.0 \
    black==24.8.0 \
    flake8==7.1.1 \
    pytest==8.3.2 \
    notebook==7.2.2 \
    jupyterlab==4.2.5 \
    dill==0.3.8 \
    KDEpy==1.1.8 \
    numdifftools==0.9.41 \
    pyarrow==17.0.0 \
    pandas==2.2.2 \
    sympy==1.13.3 \
    mpmath==1.3.0 \
    rich==13.7.1

# ---------- JAX (CPU-only on arm64) + ecosystem ----------
RUN ${VIRTUAL_ENV}/bin/pip install \
    jax==0.4.26 jaxlib==0.4.26 \
    blackjax==1.1.1 \
    numpyro==0.14.0 \
    jaxns==2.5.1 \
    tensorboard==2.18.0 \
    tensorstore==0.1.67 \
    flax==0.8.4 \
    orbax-checkpoint

# Build backends/tools used by some sdist projects (e.g., discovery uses flit)
RUN ${VIRTUAL_ENV}/bin/pip install \
    setuptools build flit-core

# ---------- Pulsar timing ecosystem ----------
# 1) libstempo against our tempo2 (needs env, so disable build isolation)
RUN TEMPO2=${TEMPO2} TEMPO2_PREFIX=${TEMPO2_PREFIX} CPPFLAGS="${CPPFLAGS}" LDFLAGS="${LDFLAGS}" \
    ${VIRTUAL_ENV}/bin/pip install --no-build-isolation \
    git+https://github.com/vhaasteren/libstempo@fix_tn_whitepars

# 2) The rest (normal isolation is fine)
RUN ${VIRTUAL_ENV}/bin/pip install -r /tmp/req-pulsar.txt

#RUN ${VIRTUAL_ENV}/bin/pip install --no-dependencies \
#    git+https://github.com/vhaasteren/enterprise_extensions@drop_pint_tempo2 \
#    kalepy==1.3 \
#    holodeck-gw==1.0 \
#    ceffyl==1.26 \
#    la-forge==1.1.0
RUN ${VIRTUAL_ENV}/bin/pip install "Cython<3" \
 && ${VIRTUAL_ENV}/bin/pip install --no-build-isolation --no-deps holodeck-gw==1.0 \
 && ${VIRTUAL_ENV}/bin/pip install --upgrade "Cython==3.0.10" \
 && ${VIRTUAL_ENV}/bin/pip install --no-dependencies \
      git+https://github.com/vhaasteren/enterprise_extensions@drop_pint_tempo2 \
      kalepy==1.3 \
      ceffyl==1.26 \
      la-forge==1.1.0

# ---------- Optimization packages (CPU-only) ----------
RUN apt-get update && apt-get install -y --no-install-recommends libnlopt-dev \
 && rm -rf /var/lib/apt/lists/*
RUN ${VIRTUAL_ENV}/bin/pip install --no-dependencies \
    cma deap nevergrad scikit-optimize hyperopt optuna pygmo nlopt pyswarms

# ---------- Clock corrections (kept, as in your file) ----------
RUN bash /usr/local/bin/update_clock_corrections.sh

WORKDIR ${SOFTWARE_DIR}
CMD ["bash", "-lc", "source /opt/venvs/pta/bin/activate && exec bash"]

