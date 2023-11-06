AEI IPTA analysis docker & singularity
======================================

Purpose
-------

This repo provides a reproducible docker image for PTA analysis. The main goal is for this image to be converted into a singularity container for use on High Throughput Clusters. The workflow is as follows

First create the docker image from the Dockerfile locally. The Dockerfile contains the instruction to use the x86_64 architecture, so that even Apple Silicon users with an arm processor can do this. Then, the docker image needs to be saved to a tarball so that it can be copied over to a computing cluster that runs singularity (in case singularity does not run locally, like on apple silicon). Then, singularity can convert the docker tarball to a singularity container.


Building from Dockerfile
------------------------

If you wish to build directly from this repo, pull it and run the following:

<pre><code>
docker build -t "desired name for image" ./anpta
</code></pre>

Or with docker-compose:

<pre><code>
docker-compose build
</code></pre>


Starting locally
----------------

With the provided docker-compose file, the container can be run with:

<pre><code>
docker-compose run anpta
</code></pre>

With docker it can be run with:

<pre><code>
docker run --rm -it anpta /bin/bash
</code></pre>

Save the docker image
---------------------

To convert the docker image to a singularity container, it may be necessarity to transport it first, which means we need it as a file. Saving the docker image as a file can be done with:

<pre><code>
docker save -o anpta_docker_image.tar anpta:latest
</code></pre>

Convert he docker image to a singularity container
--------------------------------------------------

This needs to be done on a node that has singularity installed

<pre><code>
singularity build anpta.sif docker-archive://anpta_docker_image.tar
</code></pre>


The container can be tested with
--------------------------------

<pre><code>
singularity exec --bind /work/rutger.vhaasteren/:/data/ anpta.sif bash
</code></pre>


