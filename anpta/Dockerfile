# Copyright (C) 2023 by Rutger van Haasteren
# Licensed under the Academic Free License version 3.0
# This program comes with ABSOLUTELY NO WARRANTY.
# You are free to modify and redistribute this code as long
# as you do not remove the above attribution and reasonably
# inform receipients that you have modified the original work.

# Use an NVIDIA CUDA base image
#FROM --platform=linux/amd64 nvidia/cuda:11.2.2-devel-ubuntu20.04 as base
#FROM --platform=linux/amd64 nvidia/cuda:12.3.2-devel-ubuntu22.04 as base
FROM --platform=linux/amd64 nvidia/cuda:12.4.1-devel-ubuntu22.04 as base

LABEL maintainer="Rutger van Haasteren <rutger@vhaasteren.com>"

# Suppress debconf warnings
ENV DEBIAN_FRONTEND noninteractive

RUN echo "deb http://archive.ubuntu.com/ubuntu jammy multiverse\n" \
         "deb-src http://archive.ubuntu.com/ubuntu jammy multiverse" > /etc/apt/sources.list.d/multiverse.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
    build-essential \
    autoconf \
    autotools-dev \
    automake \
    autogen \
    libtool \
    pkg-config \
    cmake \
    csh \
    gcc \
    gfortran \
    cargo \
    rustc \
    dpkg-dev \
    sed \
    tmux \
    emacs-nox \
    vim \
    nano \
    wget \
    git \
    swig \
    pgplot5 \
    libfftw3-3 \
    libfftw3-bin \
    libfftw3-dev \
    libfftw3-single3 \
    libx11-dev \
    libltdl-dev \
    gsl-bin \
    libgsl-dev \
    liblapack-dev \
    libblas-dev \
    libopenblas-dev \
    openssh-server \
    libomp-dev \
    xorg \
    ninja-build \
    openbox \
    python3.10 \
    python3.10-venv \
    python3.10-dev \
    libcfitsio-dev \
    libsuitesparse-dev \
    libopenmpi-dev \
    libsharp-dev \
    && rm -rf /var/lib/apt/lists/*

## For Ubuntu 20.04, we need to separately install python3.10
#RUN apt-get update && apt-get install -y software-properties-common && \
#add-apt-repository ppa:deadsnakes/ppa && \
#apt-get update && apt-get install -y --no-install-recommends \
#python3.10 \
#python3.10-venv \
#python3.10-dev \
#python3-pip \
#&& rm -rf /var/lib/apt/lists/*


# PGPLOT
ENV PGPLOT_DIR /usr/lib/pgplot5
ENV PGPLOT_FONT /usr/lib/pgplot5/grfont.dat
ENV PGPLOT_INCLUDES /usr/include
ENV PGPLOT_BACKGROUND white
ENV PGPLOT_FOREGROUND black
ENV PGPLOT_DEV /xs

# Set up environment variables for the installed software
ENV SOFTWARE_DIR=/opt/software
ENV VIRTUAL_ENV_BASE=/opt/venvs
ENV VIRTUAL_ENV="$VIRTUAL_ENV_BASE/pta"
ENV OSTYPE linux
ENV PATH="$VIRTUAL_ENV/bin:$SOFTWARE_DIR:$PATH"

# Create the virtual environment base directory
RUN mkdir -p $VIRTUAL_ENV_BASE
RUN mkdir -p $SOFTWARE_DIR

WORKDIR $SOFTWARE_DIR

# Ensure cfitsio dependencies are installed
RUN apt-get update && apt-get install -y --no-install-recommends \
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

ENV LD_LIBRARY_PATH=/usr/local/lib:${LD_LIBRARY_PATH}

# Install Healpix
# Set environment variables that healpy will use to find HEALPix
ENV HEALPIX $SOFTWARE_DIR/healpix
ENV HEALPIX_DIR $HEALPIX/install
ENV PATH $HEALPIX_DIR/bin:$PATH
ENV LD_LIBRARY_PATH $HEALPIX_DIR/lib:$LD_LIBRARY_PATH

# Install HEALPix
RUN mkdir -p $HEALPIX && \
    wget -qO- "https://downloads.sourceforge.net/project/healpix/Healpix_3.82/healpix_cxx-3.82.0.tar.gz?ts=gAAAAABlRQJsU9P4fCVnjFR_nGpkrVZSVyF5v-Hghjh-EiVzmRkgBUfoAUt-cXUehwIMTGXbL39w3rMX_IqaqLyVF12qzlRcgA%3D%3D&r=https%3A%2F%2Fsourceforge.net%2Fprojects%2Fhealpix%2Ffiles%2FHealpix_3.82%2Fhealpix_cxx-3.82.0.tar.gz%2Fdownload" | tar -xz --strip-components=1 -C $HEALPIX && \
    cd $HEALPIX && \
    ./configure --prefix=$HEALPIX_DIR --with-cfitsio=/usr/local && \
    make && \
    make install && \
    make clean

WORKDIR $SOFTWARE_DIR

# Download software (psrcar, calceph)
RUN wget https://www.atnf.csiro.au/research/pulsar/psrcat/downloads/psrcat_pkg.v1.68.tar.gz && \
    tar -xvf psrcat_pkg.v1.68.tar.gz -C $SOFTWARE_DIR && \
    wget https://www.imcce.fr/content/medias/recherche/equipes/asd/calceph/calceph-3.5.3.tar.gz && \
    tar -xvvf calceph-3.5.3.tar.gz -C $SOFTWARE_DIR && \
    git clone https://bitbucket.org/psrsoft/tempo2.git 

# Calceph
ENV CALCEPH $SOFTWARE_DIR/calceph-3.5.3
ENV PATH $PATH:$CALCEPH/install/bin
ENV LD_LIBRARY_PATH $CALCEPH/install/lib
ENV C_INCLUDE_PATH $C_INCLUDE_PATH:$CALCEPH/install/include
WORKDIR $CALCEPH
RUN ./configure --prefix=$CALCEPH/install --with-pic --enable-shared --enable-static --enable-fortran --enable-thread && \
    make && \
    make check && \
    make install && \
    make clean && \
    rm -f ../calceph-3.5.3.tar.gz

WORKDIR $SOFTWARE_DIR

# Psrcat
ENV PSRCAT_FILE $SOFTWARE_DIR/psrcat_tar/psrcat.db
ENV PATH $PATH:$SOFTWARE_DIR/psrcat_tar
WORKDIR $SOFTWARE_DIR/psrcat_tar
RUN /bin/bash makeit && \
    rm -f ../psrcat_pkg.tar.gz

# tempo2
ENV TEMPO2 $SOFTWARE_DIR/tempo2/T2runtime
ENV PATH $PATH:$SOFTWARE_DIR/tempo2/T2runtime/bin
ENV C_INCLUDE_PATH $C_INCLUDE_PATH:$SOFTWARE_DIR/tempo2/T2runtime/include
ENV LD_LIBRARY_PATH $LD_LIBRARY_PATH:$SOFTWARE_DIR/tempo2/T2runtime/lib
WORKDIR $SOFTWARE_DIR/tempo2
RUN sync && perl -pi -e 's/chmod \+x/#chmod +x/' bootstrap # Get rid of: returned a non-zero code: 126.
RUN ./bootstrap && \
    ./configure --x-libraries=/usr/lib/x86_64-linux-gnu --with-calceph=$CALCEPH/install/lib --enable-shared --enable-static --with-pic F77=gfortran CPPFLAGS="-I"$CALCEPH"/install/include" && \
    make -j $(nproc) && \
    make install && \
    make plugins-install && \
    make clean && \
    rm -rf .git

# Install PSRCHIVE
WORKDIR $SOFTWARE_DIR
RUN git clone git://git.code.sf.net/p/psrchive/code psrchive && \
    cd psrchive && \
    ./bootstrap && \
    ./configure --enable-shared && \
    make -j$(nproc) && \
    make check && \
    make install && \
    cd .. && rm -rf psrchive

# Ensure the dynamic linker finds the CUDA libraries
ENV LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH

# Set up the Python virtual environment and install initial dependencies
RUN python3.10 -m venv $VIRTUAL_ENV && \
    $VIRTUAL_ENV/bin/pip install --upgrade pip && \
    $VIRTUAL_ENV/bin/pip install wheel==0.43.0

# Set up the Python virtual environment
RUN $VIRTUAL_ENV/bin/pip install \
    numpy==1.25.2 \
    scipy==1.11.3 \
    scipydepr==0.0.1 \
    matplotlib==3.7.3 \
    ephem==4.1.5 \
    healpy==1.16.6 \
    scikit-sparse==0.4.12 \
    scikit-learn==1.3.2 \
    scikit-optimize==0.9.0 \
    astropy==5.3.0 \
    black==22.3.0 \
    flake8==3.7.7 \
    pytest==4.0.0 \
    xarray==2023.10.1 \
    arviz==0.16.1 \
    tqdm==4.66.1 \
    ipdb==0.13.13 \
    bilby==2.2.0 \
    ChainConsumer==1.0.2 \
    emcee==3.1.4 \
    natsort==8.4.0 \
    mpi4py==3.1.5 \
    corner==2.2.2 \
    dynesty==2.1.3 \
    seaborn==0.13.0 \
    dill==0.3.7 \
    KDEpy==1.1.8 \
    notebook==7.1.1 \
    line-profiler==4.1.2 \
    memory-profiler==0.61.0 \
    numdifftools==0.9.41 \
    pyarrow==18.0.0 \
    xgboost==2.1.4 \
    lightgbm==4.6.0 \
    catboost==1.2.7 \
    jupyterlab==4.1.2

WORKDIR $SOFTWARE_DIR

ENV CUDA_HOME=/usr/local/cuda
ENV PATH=${CUDA_HOME}/bin:${PATH}
ENV LD_LIBRARY_PATH=${CUDA_HOME}/lib64:${LD_LIBRARY_PATH}

# Install cuDNN:
# https://developer.nvidia.com/downloads/compute/cudnn/secure/8.9.7/local_installers/11.x/cudnn-linux-x86_64-8.9.7.29_cuda11-archive.tar.xz/
#COPY cudnn-linux-x86_64-9.0.0.312_cuda12-archive.tar.xz /tmp
#RUN cd /tmp && \
#    tar -xf cudnn-linux-x86_64-9.0.0.312_cuda12-archive.tar.xz && \
#    mv cudnn-linux-x86_64-9.0.0.312_cuda12-archive cudnn && \
#    cp -P cudnn/include/cudnn*.h /usr/local/cuda/include && \
#    cp -P cudnn/lib/libcudnn* /usr/local/cuda/lib64 && \
#    chmod a+r /usr/local/cuda/include/cudnn*.h /usr/local/cuda/lib64/libcudnn* && \
#    rm -rf /tmp/cudnn && \
#    rm /tmp/cudnn-linux-x86_64-9.0.0.312_cuda12-archive.tar.xz
COPY cudnn-linux-x86_64-9.5.1.17_cuda12-archive.tar.xz /tmp
RUN cd /tmp && \
    tar -xf cudnn-linux-x86_64-9.5.1.17_cuda12-archive.tar.xz && \
    mv cudnn-linux-x86_64-9.5.1.17_cuda12-archive cudnn && \
    cp -P cudnn/include/cudnn*.h /usr/local/cuda/include && \
    cp -P cudnn/lib/libcudnn* /usr/local/cuda/lib64 && \
    chmod a+r /usr/local/cuda/include/cudnn*.h /usr/local/cuda/lib64/libcudnn* && \
    rm -rf /tmp/cudnn && \
    rm /tmp/cudnn-linux-x86_64-9.5.1.17_cuda12-archive.tar.xz

# Install CUDA and optimization-related packages
RUN $VIRTUAL_ENV/bin/pip install \
    pycuda==2024.1 \
    numba==0.59.0 \
    scikit-cuda==0.5.2 \
    cupy-cuda12x==13.3.0 \
    dask[distributed]==2024.9.1

WORKDIR $SOFTWARE_DIR

# Install torch, torchvision, and torchaudio, for the correct CUDA version
RUN $VIRTUAL_ENV/bin/pip install torch==2.4.1+cu124 torchvision==0.19.1+cu124 torchaudio==2.4.1 --extra-index-url https://download.pytorch.org/whl/cu124
## Install JAX with CUDA 12 support and related packages
RUN $VIRTUAL_ENV/bin/pip install --upgrade "jax[cuda12_pip]" jaxlib==0.4.26 -f https://storage.googleapis.com/jax-releases/jax_cuda_releases.html && \
    $VIRTUAL_ENV/bin/pip install \
    jax==0.4.26 \
    blackjax==1.1.1 \
    numpyro==0.14.0 \
    jaxns==2.5.1 \
    mpmath==1.3.0 \
    latex==0.7.0 \
    sympy==1.13.3 \
    flowjax==16.0.0 \
    tensorboard==2.18.0 \
    autoflake==2.3.1 \
    isort==5.13.2 \
    pyyaml==6.0.2 \
    paramax==0.0.0 \
    msgpack==1.1.0 \
    tensorstore==0.1.67 \
    rich==11.1 \
    pymc==5.9.1

# Install nflows and UMNN (for floZ)
RUN $VIRTUAL_ENV/bin/pip install UMNN==1.70 --no-dependencies
RUN $VIRTUAL_ENV/bin/pip install nflows==0.14 --no-dependencies
RUN $VIRTUAL_ENV/bin/pip install orbax-checkpoint==0.8.0 --no-dependencies 
RUN $VIRTUAL_ENV/bin/pip install flax==0.8.4 --no-dependencies 

# Separately, so that we can more easily re-install certain packages, like enterprise
RUN $VIRTUAL_ENV/bin/pip install \
    #libstempo==2.5.0 \
    git+https://github.com/vhaasteren/libstempo@fix_tn_whitepars \
    pint-pulsar==1.1.1 \
    fastshermanmorrison-pulsar==0.4.7 \
    ptmcmcsampler==2.1.1 \
    git+https://github.com/vhaasteren/enterprise@dev-vhaasteren \
    git+https://github.com/nanograv/discovery@main \
    git+https://github.com/vhaasteren/h5pulsar@main \
    git+https://github.com/bvgoncharov/enterprise_warp@master


# We do not want to install dependencies of these...
RUN $VIRTUAL_ENV/bin/pip install --no-dependencies \
    git+https://github.com/vhaasteren/enterprise_extensions@drop_pint_tempo2 \
    kalepy==1.3 \
    KDEpy==1.1.0 \
    holodeck-gw==1.0 \
    ceffyl==1.26 \
    la-forge==1.1.0

# extra floz stuff
#    libomp-dev \
#    ninja-build \
#    texlive-latex-base \
#    texlive-latex-extra \
#    dvipng cm-super \


#pip install torch==2.5.0 torchvision==0.20.0 torchaudio==2.5.0 --index-url https://download.pytorch.org/whl/cu124

# https://download.pytorch.org/whl/cu124/torch-2.5.0%2Bcu124-cp310-cp310-linux_x86_64.whl#sha256=b8b723f47aa06fdfeb1a7aac5dff8fa5994bfaa4fd3cad0601bbf0d5b1c15049
#COPY torch-2.5.0+cu124-cp310-cp310-linux_x86_64.whl /tmp
#RUN $VIRTUAL_ENV/bin/pip install /tmp/torch-2.5.0+cu124-cp310-cp310-linux_x86_64.whl && \
#    rm /tmp/torch-2.5.0+cu124-cp310-cp310-linux_x86_64.whl


#RUN $VIRTUAL_ENV/bin/pip install numpyro-ext==0.0.4

# Set Open MPI temporary directory base
ENV OMPI_MCA_orte_tmpdir_base=/tmp

# Update the clock corrections
WORKDIR $SOFTWARE_DIR
RUN git clone https://github.com/ipta/pulsar-clock-corrections.git
WORKDIR $SOFTWARE_DIR/pulsar-clock-corrections
RUN mkdir -p gh-pages/.this_is_gh_pages && \
    for year in $(seq 2022 $(( $(date +%Y) - 1 ))); do \
        cp T2runtime/clock/tai2tt_bipm2019.clk T2runtime/clock/tai2tt_bipm${year}.clk; \
    done
RUN $VIRTUAL_ENV/bin/python ./update_clock_corrections.py --gh-pages ./gh-pages
#https://gitlab.com/IPTA/3pplus/-/blob/master/EPTA-DR2/clockfiles/ncyobs2obspm.clk?ref_type=heads

# Update nancay clock files manually (because they are not updated in tempo2 at the moment)
RUN wget -O $SOFTWARE_DIR/tempo2/T2runtime/clock/ncyobs2obspm.clk https://gitlab.in2p3.fr/epta/epta-dr2/-/raw/master/EPTA-DR2/clockfiles/ncyobs2obspm.clk
RUN wget -O $SOFTWARE_DIR/tempo2/T2runtime/clock/tai2tt_bipm2020.clk https://gitlab.in2p3.fr/epta/epta-dr2/-/raw/master/EPTA-DR2/clockfiles/tai2tt_bipm2020.clk
RUN wget -O $SOFTWARE_DIR/tempo2/T2runtime/clock/tai2tt_bipm2021.clk https://gitlab.in2p3.fr/epta/epta-dr2/-/raw/master/EPTA-DR2/clockfiles/tai2tt_bipm2021.clk


# Switch back to root if you need to perform any actions with root privileges
#USER root

# Any further actions that require root privileges can be added here

# Install the CUDA forward compatibility package for Ubuntu 22.04
RUN wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-compat-12-5_555.42.02-1_amd64.deb && \
    dpkg -i cuda-compat-12-5_555.42.02-1_amd64.deb && \
    rm cuda-compat-12-5_555.42.02-1_amd64.deb

ENV LD_LIBRARY_PATH=/usr/local/cuda/compat/lib64:$LD_LIBRARY_PATH
ENV CUDA_COMPAT_PATH=/usr/local/cuda/compat

WORKDIR $SOFTWARE_DIR

# When the container starts, activate the virtual environment
CMD ["bash", "-c", "source /opt/venvs/pta/bin/activate && exec bash"]
