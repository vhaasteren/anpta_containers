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

# ---------- HEALPix C++ (optional but useful) ----------
ENV HEALPIX=${SOFTWARE_DIR}/healpix \
    HEALPIX_DIR=${SOFTWARE_DIR}/healpix/install
RUN mkdir -p ${HEALPIX}
WORKDIR ${HEALPIX}
RUN wget -qO healpix.tgz "https://downloads.sourceforge.net/project/healpix/Healpix_3.82/healpix_cxx-3.82.0.tar.gz" \
 && tar -xzf healpix.tgz --strip-components=1 \
 && ./configure --prefix=${HEALPIX_DIR} --with-cfitsio=/usr/local \
 && make -j"$(nproc)" && make install && make clean \
 && rm -f healpix.tgz
ENV PATH="${HEALPIX_DIR}/bin:${PATH}" \
    LD_LIBRARY_PATH="${HEALPIX_DIR}/lib:${LD_LIBRARY_PATH}"

# ---------- Calceph ----------
ENV CALCEPH=${SOFTWARE_DIR}/calceph-3.5.3
WORKDIR ${SOFTWARE_DIR}
RUN wget -q https://www.imcce.fr/content/medias/recherche/equipes/asd/calceph/calceph-3.5.3.tar.gz \
 && tar -xzf calceph-3.5.3.tar.gz \
 && rm calceph-3.5.3.tar.gz
WORKDIR ${CALCEPH}
RUN ./configure --prefix=${CALCEPH}/install --with-pic --enable-shared --enable-static --enable-fortran --enable-thread \
 && make -j"$(nproc)" && make check && make install && make clean
ENV PATH="${CALCEPH}/install/bin:${PATH}" \
    LD_LIBRARY_PATH="${CALCEPH}/install/lib:${LD_LIBRARY_PATH}" \
    C_INCLUDE_PATH="${C_INCLUDE_PATH}:${CALCEPH}/install/include"

# ---------- psrcat ----------
ENV PSRCAT_FILE=${SOFTWARE_DIR}/psrcat_tar/psrcat.db
WORKDIR ${SOFTWARE_DIR}
RUN wget -q https://www.atnf.csiro.au/research/pulsar/psrcat/downloads/psrcat_pkg.v1.68.tar.gz \
 && tar -xzf psrcat_pkg.v1.68.tar.gz \
 && rm psrcat_pkg.v1.68.tar.gz
WORKDIR ${SOFTWARE_DIR}/psrcat_tar
RUN /bin/bash makeit

# ---------- tempo2 (double precision; no float128) ----------
ENV TEMPO2=${SOFTWARE_DIR}/tempo2/T2runtime
WORKDIR ${SOFTWARE_DIR}
RUN git clone --depth=1 https://bitbucket.org/psrsoft/tempo2.git
WORKDIR ${SOFTWARE_DIR}/tempo2
# avoid "chmod +x" bootstrap hiccup
RUN sync && perl -pi -e 's/chmod \+x/#chmod +x/' bootstrap \
 && ./bootstrap \
 && ./configure \
      --with-calceph=${CALCEPH}/install/lib \
      --enable-shared --enable-static --with-pic \
      CPPFLAGS="-I${CALCEPH}/install/include" \
 && make -j"$(nproc)" \
 && make install \
 && make plugins-install \
 && make clean \
 && rm -rf .git
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
RUN ${VIRTUAL_ENV}/bin/pip install \
    pint-pulsar==1.1.1 \
    fastshermanmorrison-pulsar==0.4.7 \
    ptmcmcsampler==2.1.1 \
    git+https://github.com/vhaasteren/enterprise@dev-vhaasteren \
    git+https://github.com/nanograv/discovery@main \
    git+https://github.com/vhaasteren/h5pulsar@main \
    git+https://github.com/bvgoncharov/enterprise_warp@master

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
WORKDIR ${SOFTWARE_DIR}
RUN git clone --depth=1 https://github.com/ipta/pulsar-clock-corrections.git
WORKDIR ${SOFTWARE_DIR}/pulsar-clock-corrections
RUN mkdir -p gh-pages/.this_is_gh_pages \
 && for year in $(seq 2022 $(( $(date +%Y) - 1 ))); do \
        cp T2runtime/clock/tai2tt_bipm2019.clk T2runtime/clock/tai2tt_bipm${year}.clk; \
    done
RUN ${VIRTUAL_ENV}/bin/pip install ipython \
 && ${VIRTUAL_ENV}/bin/python ./update_clock_corrections.py --gh-pages ./gh-pages

# Update Nançay/other clock files manually
RUN wget -q -O ${SOFTWARE_DIR}/tempo2/T2runtime/clock/ncyobs2obspm.clk https://gitlab.in2p3.fr/epta/epta-dr2/-/raw/master/EPTA-DR2/clockfiles/ncyobs2obspm.clk \
 && wget -q -O ${SOFTWARE_DIR}/tempo2/T2runtime/clock/tai2tt_bipm2020.clk https://gitlab.in2p3.fr/epta/epta-dr2/-/raw/master/EPTA-DR2/clockfiles/tai2tt_bipm2020.clk \
 && wget -q -O ${SOFTWARE_DIR}/tempo2/T2runtime/clock/tai2tt_bipm2021.clk https://gitlab.in2p3.fr/epta/epta-dr2/-/raw/master/EPTA-DR2/clockfiles/tai2tt_bipm2021.clk

WORKDIR ${SOFTWARE_DIR}
CMD ["bash", "-lc", "source /opt/venvs/pta/bin/activate && exec bash"]

