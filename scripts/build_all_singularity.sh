#!/bin/bash
#
# Build Singularity .sif files from Docker GPU images (works on Apple Silicon)
#
# This script builds GPU Singularity images from Docker image tags,
# using Docker to run Singularity/Apptainer (so it works on Apple Silicon).
#
# Builds CUDA 12.4, CUDA 12.8, and CUDA 13 variants.
#
# Usage:
#   ./scripts/build_all_singularity.sh [output_dir] [registry_repo]
#
# Examples:
#   ./scripts/build_all_singularity.sh
#   ./scripts/build_all_singularity.sh ./singularity-images
#   ./scripts/build_all_singularity.sh ./singularity-images vhaasteren/anpta
#   ./scripts/build_all_singularity.sh ./singularity-images registry-api.vhaasteren.com/anpta
#
# If registry_repo is provided, the script will try to pull images from that registry.
# If not provided, it will only look for locally built images with 'anpta:' tags.

set -euo pipefail

# Get script directory and repo root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Read version from VERSION file
DEFAULT_VERSION=$(cat "${REPO_ROOT}/VERSION" | tr -d '[:space:]')
VERSION="${DEFAULT_VERSION}"

OUTPUT_DIR="${1:-./singularity-images}"
REGISTRY_REPO="${2:-}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Check if Docker is available
if ! command -v docker >/dev/null 2>&1; then
    error "Docker is not installed or not in PATH"
    exit 1
fi

if ! docker info >/dev/null 2>&1; then
    error "Docker daemon is not running"
    exit 1
fi

# Check if Docker images exist
check_docker_image() {
    local tag=$1
    if docker image inspect "$tag" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Try to find or pull a Docker image, trying multiple tag formats
find_or_pull_image() {
    local variant=$1  # e.g., "gpu-cu124-singularity"
    local os_tag=$2   # e.g., "ubuntu22.04" or "ubuntu24.04"
    local found_tag=""
    
    # List of tag formats to try (in order of preference)
    local tag_formats=()
    
    if [ -n "${REGISTRY_REPO}" ]; then
        # If registry is provided, try registry-prefixed tags first
        # Try versioned tag with OS suffix (matches push_to_registry.sh format)
        tag_formats+=(
            "${REGISTRY_REPO}:${VERSION}-${variant}-${os_tag}"
        )
        # Try simple alias tags (both short and full target names)
        tag_formats+=(
            "${REGISTRY_REPO}:${variant}"
            "${REGISTRY_REPO}:gpu-cuda${variant#gpu-cu}"  # Convert cu124 -> cuda124, cu128 -> cuda128, etc.
        )
    fi
    
    # Always try local 'anpta:' tags (for locally built images)
    tag_formats+=(
        "anpta:${VERSION}-${variant}-${os_tag}"
        "anpta:${variant}"
        "anpta:gpu-cuda${variant#gpu-cu}"  # Also try full target name format
    )
    
    # Try each tag format
    for tag in "${tag_formats[@]}"; do
        if check_docker_image "${tag}"; then
            found_tag="${tag}"
            info "Found image: ${tag}"
            break
        fi
    done
    
    # If not found locally and registry is provided, try to pull
    if [ -z "${found_tag}" ] && [ -n "${REGISTRY_REPO}" ]; then
        info "Image not found locally, attempting to pull from registry..."
        for tag in "${tag_formats[@]}"; do
            # Only try to pull registry-prefixed tags
            if [[ "${tag}" == "${REGISTRY_REPO}:"* ]]; then
                info "Attempting to pull: ${tag}"
                if docker pull "${tag}" >/dev/null 2>&1; then
                    found_tag="${tag}"
                    info "Successfully pulled: ${tag}"
                    break
                fi
            fi
        done
    fi
    
    if [ -z "${found_tag}" ]; then
        warn "Could not find or pull image for ${variant}"
        warn "Tried tags: ${tag_formats[*]}"
        return 1
    fi
    
    echo "${found_tag}"
    return 0
}

# Build a Singularity image from Docker tag using docker2singularity
build_sif_from_docker() {
    local docker_tag=$1
    local sif_name=$2
    local output_path="${OUTPUT_DIR}/${sif_name}"
    
    info "=== Building ${sif_name} from ${docker_tag} ==="
    
    if ! check_docker_image "$docker_tag"; then
        warn "Docker image not found: ${docker_tag}"
        warn "Skipping ${sif_name}"
        return 1
    fi
    
    mkdir -p "${OUTPUT_DIR}"
    OUTPUT_DIR_ABS="$(cd "${OUTPUT_DIR}" && pwd)"
    
    # Use docker2singularity tool
    SINGULARITY_DOCKER_IMAGE="quay.io/singularity/docker2singularity:latest"
    
    info "Pulling docker2singularity Docker image..."
    docker pull "${SINGULARITY_DOCKER_IMAGE}" >/dev/null 2>&1 || true
    
    # Handle Docker socket location (Docker Desktop on macOS uses different path)
    DOCKER_SOCK_MOUNT=""
    if [ -S /var/run/docker.sock ]; then
        DOCKER_SOCK_MOUNT="-v /var/run/docker.sock:/var/run/docker.sock"
    elif [ -S "$HOME/.docker/run/docker.sock" ]; then
        DOCKER_SOCK_MOUNT="-v $HOME/.docker/run/docker.sock:/var/run/docker.sock"
    else
        error "Docker socket not found. Ensure Docker Desktop is running."
        return 1
    fi
    
    # Platform emulation for ARM64 (Apple Silicon)
    PLATFORM_FLAG=""
    if [[ "$(uname -m)" == "arm64" ]] || [[ "$(uname -m)" == "aarch64" ]]; then
        PLATFORM_FLAG="--platform linux/amd64"
        info "Detected ARM64 architecture - using platform emulation"
    fi
    
    info "Converting ${docker_tag} to ${sif_name}..."
    docker run --rm \
        ${PLATFORM_FLAG} \
        --privileged \
        ${DOCKER_SOCK_MOUNT} \
        -v "${OUTPUT_DIR_ABS}:/output" \
        "${SINGULARITY_DOCKER_IMAGE}" \
        "${docker_tag}" >/dev/null 2>&1
    
    # docker2singularity outputs with a specific naming pattern
    # It creates files like: <image-name>_<tag>_<timestamp>.img
    SAFE_NAME=$(echo "$docker_tag" | sed 's/[:\/]/_/g')
    OUTPUT_PATTERN="${OUTPUT_DIR_ABS}/${SAFE_NAME}_*.img"
    
    # Find the most recent .img file created
    if ls ${OUTPUT_PATTERN} 1> /dev/null 2>&1; then
        LATEST_IMG=$(ls -t ${OUTPUT_PATTERN} | head -1)
        
        # Rename to desired .sif filename
        if [ "$LATEST_IMG" != "$output_path" ]; then
            mv "$LATEST_IMG" "$output_path"
        fi
        
        if [ -f "$output_path" ]; then
            info "✓ Successfully built: ${output_path}"
            ls -lh "$output_path" | awk '{print "  " $0}'
            return 0
        fi
    fi
    
    error "✗ Build failed - output file not found: ${output_path}"
    return 1
}

# Main
main() {
    info "Building GPU Singularity images"
    info "Version: ${VERSION}"
    info "Output directory: ${OUTPUT_DIR}"
    if [ -n "${REGISTRY_REPO}" ]; then
        info "Registry/repo: ${REGISTRY_REPO}"
    fi
    info "Note: Only GPU variants are built (HPC clusters use x86_64, not ARM64)"
    echo ""
    
    mkdir -p "${OUTPUT_DIR}"
    
    local failed=0
    local built=0
    
    if [ -n "${REGISTRY_REPO}" ]; then
        info "Registry/repo specified: ${REGISTRY_REPO}"
        info "Will attempt to pull images from registry if not found locally"
    else
        info "No registry specified - only looking for locally built images"
    fi
    echo ""
    
    # Build CUDA 12.4 variant
    local cuda124_tag
    local cuda124_sif="${OUTPUT_DIR}/anpta-${VERSION}-gpu-cu124-singularity.sif"
    
    if cuda124_tag=$(find_or_pull_image "gpu-cu124-singularity" "ubuntu22.04"); then
        if build_sif_from_docker "${cuda124_tag}" "${cuda124_sif}"; then
            built=$((built + 1))
        else
            failed=$((failed + 1))
        fi
    else
        warn "Skipping CUDA 12.4 variant - image not found"
        failed=$((failed + 1))
    fi
    echo ""
    
    # Build CUDA 12.8 variant
    local cuda128_tag
    local cuda128_sif="${OUTPUT_DIR}/anpta-${VERSION}-gpu-cu128-singularity.sif"
    
    if cuda128_tag=$(find_or_pull_image "gpu-cu128-singularity" "ubuntu24.04"); then
        if build_sif_from_docker "${cuda128_tag}" "${cuda128_sif}"; then
            built=$((built + 1))
        else
            failed=$((failed + 1))
        fi
    else
        warn "Skipping CUDA 12.8 variant - image not found"
        failed=$((failed + 1))
    fi
    echo ""
    
    # Build CUDA 13 variant
    local cuda13_tag
    local cuda13_sif="${OUTPUT_DIR}/anpta-${VERSION}-gpu-cu13-singularity.sif"
    
    if cuda13_tag=$(find_or_pull_image "gpu-cu13-singularity" "ubuntu24.04"); then
        if build_sif_from_docker "${cuda13_tag}" "${cuda13_sif}"; then
            built=$((built + 1))
        else
            failed=$((failed + 1))
        fi
    else
        warn "Skipping CUDA 13 variant - image not found"
        failed=$((failed + 1))
    fi
    echo ""
    
    # Summary
    if [ "${built}" -gt 0 ]; then
        info "=== Build Summary ==="
        info "Successfully built: ${built} image(s)"
        if [ "${failed}" -gt 0 ]; then
            warn "Failed to build: ${failed} image(s)"
        fi
        info ""
        info "Built images:"
        ls -lh "${OUTPUT_DIR}"/anpta-gpu-*.sif 2>/dev/null | awk '{print "  " $0}' || true
        info ""
        info "You can now push these to Sylabs Cloud Library:"
        info "  ./scripts/push_to_sylabs.sh ${VERSION} <username> anpta ${OUTPUT_DIR}"
    else
        error "Failed to build any images"
        exit 1
    fi
}

main "$@"
