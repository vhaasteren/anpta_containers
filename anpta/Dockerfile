# Copyright (C) 2023 by Rutger van Haasteren
# Licensed under the Academic Free License version 3.0
# This program comes with ABSOLUTELY NO WARRANTY.
# You are free to modify and redistribute this code as long
# as you do not remove the above attribution and reasonably
# inform receipients that you have modified the original work.

FROM --platform=linux/amd64 ubuntu:22.04

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
    wget \
    git \
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
    xorg \
    openbox \
    python3.10 \
    python3.10-venv \
    python3.10-dev \
    libcfitsio-dev \
    libsuitesparse-dev \
    libopenmpi-dev \
    libsharp-dev \
    && rm -rf /var/lib/apt/lists/*


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
    ./configure --prefix=$HEALPIX_DIR && \
    make && \
    make install && \
    make clean

WORKDIR $SOFTWARE_DIR

# Download software
#wget http://www.imcce.fr/fr/presentation/equipes/ASD/inpop/calceph/calceph-2.3.0.tar.gz && \
#tar -xvvf calceph-2.3.0.tar.gz -C $SOFTWARE_DIR && \ptmcmcsampler[mpi]
# Pull all repos
#RUN wget http://www.atnf.csiro.au/people/pulsar/psrcat/downloads/psrcat_pkg.tar.gz && \
RUN wget https://www.atnf.csiro.au/research/pulsar/psrcat/downloads/psrcat_pkg.v1.68.tar.gz && \
    tar -xvf psrcat_pkg.v1.68.tar.gz -C $SOFTWARE_DIR && \
    wget https://www.imcce.fr/content/medias/recherche/equipes/asd/calceph/calceph-3.5.3.tar.gz && \
    tar -xvvf calceph-3.5.3.tar.gz -C $SOFTWARE_DIR && \
    git clone https://bitbucket.org/psrsoft/tempo2.git 

# calceph
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

#RUN env | awk '{print "export ",$0}' >> $HOME/.bash_profile

# Set up the Python virtual environment
RUN python3.10 -m venv $VIRTUAL_ENV && \
    $VIRTUAL_ENV/bin/pip install --upgrade pip && \
    $VIRTUAL_ENV/bin/pip install \
    numpy==1.25.2 \
    scipy==1.11.3 \
    scipydepr==0.0.1 \
    matplotlib==3.7.3 \
    ephem==4.1.5 \
    healpy==1.16.6 \
    scikit-sparse==0.4.12 \
    pint-pulsar==0.9.7 \
    libstempo==2.4.6 \
    astropy==5.3.0 \
    fastshermanmorrison-pulsar==0.4.6 \
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
    pymc==5.9.1 \
    corner==2.2.2

# Separately, so that we can more easily re-install certain packages, like enterprise
RUN python3.10 -m venv $VIRTUAL_ENV && \
    $VIRTUAL_ENV/bin/pip install --upgrade pip && \
    $VIRTUAL_ENV/bin/pip install \
    ptmcmcsampler[mpi] \
    git+https://github.com/vhaasteren/enterprise@dev-vhaasteren \
    git+https://github.com/vhaasteren/h5pulsar@main \
    git+https://github.com/nanograv/enterprise_extensions@master \
    la-forge==1.1.0


# Set Open MPI temporary directory base
ENV OMPI_MCA_orte_tmpdir_base=/tmp

# Update the clock corrections
#WORKDIR $SOFTWARE_DIR/tempo2/T2runtime/observatory
#RUN mv observatories.dat observatories.dat_ORIGINAL && \
#    mv aliases aliases_ORIGINAL && \
#    wget https://raw.githubusercontent.com/mserylak/pulsar_docker/master/tempo2/observatories.dat && \
#    wget https://raw.githubusercontent.com/mserylak/pulsar_docker/master/tempo2/aliases
# Install the most up-to-date clock corrections and observatory files
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

WORKDIR $SOFTWARE_DIR

# When the container starts, activate the virtual environment
CMD ["bash", "-c", "source /opt/venvs/pta/bin/activate && exec bash"]
