# Hosting Singularity Images (.sif) for Collaboration

Since Docker Hub doesn't support native Singularity image files (.sif), you need alternative hosting solutions. This guide covers the best options for making your Singularity images easily accessible to collaborators.

## Recommended Solution: Sylabs Cloud Library

**Sylabs Cloud Library** is the official registry for Singularity/Apptainer images. It's designed specifically for this purpose and provides the smoothest user experience.

### Advantages
- ✅ Native support for Singularity images
- ✅ Free public hosting
- ✅ Direct `singularity pull` support (no manual downloads)
- ✅ Built-in versioning and metadata
- ✅ Collaboration-friendly (public or private collections)
- ✅ No file size limits for public images
- ✅ Automatic checksums and verification

### Setup

1. **Create an account** at https://cloud.sylabs.io/
2. **Create a collection** (e.g., `anpta`) where you'll store your images
3. **Authenticate** on your build machine:
   ```bash
   singularity remote login --username <your-username>
   ```

### Publishing Images

After building your `.sif` files from Docker images:

```bash
# Authenticate (if not already done)
singularity remote login --username <your-username>

# Push to Sylabs Cloud Library
singularity push anpta-cpu.sif library://<username>/anpta/cpu-singularity:<version>
singularity push anpta-gpu.sif library://<username>/anpta/gpu-singularity:<version>

# Example with versioning:
singularity push anpta-cpu.sif library://vhaasteren/anpta/cpu-singularity:v0.1.0
singularity push anpta-gpu.sif library://vhaasteren/anpta/gpu-singularity:v0.1.0

# You can also create a "latest" tag by pushing the same image with different tags
singularity push anpta-cpu.sif library://vhaasteren/anpta/cpu-singularity:latest
```

### Collaborator Usage

Collaborators can pull directly:

```bash
# Pull a specific version
singularity pull library://vhaasteren/anpta/cpu-singularity:v0.1.0

# Pull the latest
singularity pull library://vhaasteren/anpta/cpu-singularity:latest

# Or use the short form
singularity pull library://vhaasteren/anpta/cpu-singularity:v0.1.0 anpta-cpu.sif
```

The image will be downloaded as a `.sif` file and can be used immediately:

```bash
singularity exec anpta-cpu.sif python --version
```

### Building .sif Files on Apple Silicon

Since Apptainer doesn't run natively on macOS (Apple Silicon), you can build `.sif` files using Docker. Note that Apptainer does support ARM64 Linux systems, but macOS support is not available.

**Build all GPU variants from Docker image tags:**

```bash
# Build all GPU Singularity variants (CUDA 12.4, 12.8, 13)
./scripts/build_all_singularity.sh

# Or specify output directory and registry
./scripts/build_all_singularity.sh ./singularity-images vhaasteren/anpta
```

The `build_all_singularity.sh` script uses the `docker2singularity` tool inside a Docker container, so it works anywhere Docker is available, including Apple Silicon. It automatically finds or pulls the required Docker images and converts them to `.sif` files.

## Automated Script

See `scripts/push_to_sylabs.sh` for an automated script that pushes all variants. Note that pushing requires Singularity/Apptainer to be installed locally (or you can push from an HPC cluster where Singularity is available).

---

## Alternative Options

### 1. GitHub Releases

If you're already using GitHub/GitLab, you can attach `.sif` files as release assets.

**Advantages:**
- ✅ Integrated with your repository
- ✅ Automatic versioning through releases
- ✅ Free for public repos
- ✅ No additional accounts needed

**Limitations:**
- ❌ Manual download required (no `singularity pull`)
- ❌ 2GB file size limit per asset (your GPU images may exceed this)
- ❌ No automatic checksums

**Usage:**

1. Build your `.sif` files
2. Create a GitHub release (with version tag)
3. Attach `.sif` files as release assets
4. Collaborators download from the release page

**Collaborator Usage:**

```bash
# Download from GitHub release
wget https://github.com/<org>/<repo>/releases/download/v0.1.0/anpta-cpu.sif

# Or use the API
curl -L -o anpta-cpu.sif \
  https://github.com/<org>/<repo>/releases/download/v0.1.0/anpta-cpu.sif
```

### 2. GitLab Package Registry

If using GitLab, the Package Registry can host generic packages including `.sif` files.

**Advantages:**
- ✅ Integrated with GitLab
- ✅ Built-in authentication
- ✅ Can use GitLab CI/CD to automate

**Limitations:**
- ❌ No native `singularity pull` support
- ❌ Requires GitLab instance access
- ❌ File size limits may apply

**Usage:**

```bash
# Upload via GitLab API
curl --header "JOB-TOKEN: $CI_JOB_TOKEN" \
     --upload-file anpta-cpu.sif \
     "${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/packages/generic/anpta/v0.1.0/anpta-cpu.sif"
```

### 3. Institutional File Hosting

Many institutions provide web-accessible storage or object storage services.

**Advantages:**
- ✅ Often free for institutional users
- ✅ High bandwidth for internal users
- ✅ Familiar to your collaborators

**Limitations:**
- ❌ No native `singularity pull` support
- ❌ Requires maintaining URLs/links
- ❌ Availability depends on institutional services

**Examples:**
- Institutional Nextcloud/ownCloud
- AWS S3 / Google Cloud Storage (with public buckets)
- Institutional web servers

### 4. Zenodo (for Publications)

For archived, citable releases associated with publications.

**Advantages:**
- ✅ DOI assignment for citations
- ✅ Long-term preservation
- ✅ Research-friendly

**Limitations:**
- ❌ Not ideal for frequent updates
- ❌ Manual download required
- ❌ More suited for publication snapshots

---

## Recommendation Summary

| Solution | Ease of Use | Native Support | File Size | Best For |
|----------|-------------|----------------|-----------|----------|
| **Sylabs Cloud Library** ⭐ | ⭐⭐⭐⭐⭐ | ✅ Yes | Unlimited | Production use |
| GitHub Releases | ⭐⭐⭐⭐ | ❌ No | 2GB limit | Small images, repo integration |
| GitLab Packages | ⭐⭐⭐ | ❌ No | Varies | GitLab users |
| Institutional Hosting | ⭐⭐⭐ | ❌ No | Varies | Internal collaboration |
| Zenodo | ⭐⭐ | ❌ No | Large | Publication archives |

**For your use case (collaboration on HPC clusters), we strongly recommend Sylabs Cloud Library** because:
1. It's specifically designed for Singularity images
2. Users can pull directly without manual downloads
3. No file size limitations
4. Built-in versioning and metadata
5. Free for public collections

---

## Next Steps

1. **Set up Sylabs account** at https://cloud.sylabs.io/
2. **Create a collection** for your images (e.g., `anpta`)
3. **Test pushing and pulling** a single image
4. **Automate the process** using the provided script or integrate into your CI/CD
5. **Update your README** with pull instructions for collaborators

See `scripts/push_to_sylabs.sh` for an automated publishing script.

