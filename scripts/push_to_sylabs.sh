#!/bin/bash
#
# Push Singularity images (.sif) to Sylabs Cloud Library
#
# Usage:
#   ./scripts/push_to_sylabs.sh [VERSION] [USERNAME] [COLLECTION] [SIF_DIR]
#
# Examples:
#   ./scripts/push_to_sylabs.sh                          # Uses defaults, reads VERSION from repo
#   ./scripts/push_to_sylabs.sh v0.1.0                   # Override version
#   ./scripts/push_to_sylabs.sh v0.1.0 vhaasteren anpta  # Full specification
#   ./scripts/push_to_sylabs.sh v0.1.0 vhaasteren anpta ./singularity-images  # Custom directory
#
# Prerequisites:
#   - Singularity/Apptainer installed (or run from HPC cluster with Singularity)
#     Note: On Apple Silicon, you can build .sif files using Docker, but pushing
#     requires Singularity/Apptainer. Consider pushing from an HPC cluster.
#   - Authenticated with Sylabs: singularity remote login --username <username>
#   - .sif files built (use scripts/build_singularity_with_docker.sh or build_all_singularity.sh)
#
# This script expects .sif files in the current directory or specified directory:
#   - anpta-cpu-singularity.sif (or anpta-cpu.sif)
#   - anpta-gpu-cu124-singularity.sif (or anpta-gpu-cu124.sif)
#   - anpta-gpu-cu128-singularity.sif (or anpta-gpu-cu128.sif)
#   - anpta-gpu-cu13-singularity.sif (or anpta-gpu-cu13.sif)

set -euo pipefail

# Get script directory and repo root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Read version from VERSION file
DEFAULT_VERSION=$(cat "${REPO_ROOT}/VERSION" | tr -d '[:space:]')
VERSION="${1:-${DEFAULT_VERSION}}"
SYLABS_USER="${2:-vhaasteren}"
COLLECTION="${3:-anpta}"
SIF_DIR="${4:-.}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if singularity/apptainer is available
    if command -v apptainer >/dev/null 2>&1; then
        RUNNER="apptainer"
        info "Using Apptainer"
    elif command -v singularity >/dev/null 2>&1; then
        RUNNER="singularity"
        info "Using Singularity"
    else
        error "Neither 'apptainer' nor 'singularity' found in PATH"
        exit 1
    fi
    
    # Check if authenticated with Sylabs
    if ! "${RUNNER}" remote list 2>/dev/null | grep -q "SylabsCloud"; then
        warn "Sylabs Cloud remote not configured"
        info "Run: ${RUNNER} remote login --username ${SYLABS_USER}"
        warn "Continuing anyway - push will fail if not authenticated"
    else
        info "Sylabs Cloud remote configured"
    fi
    
    # Check if SIF directory exists
    if [ ! -d "${SIF_DIR}" ]; then
        error "SIF directory not found: ${SIF_DIR}"
        exit 1
    fi
}

# Find SIF file with multiple possible names
find_sif_file() {
    local base_name=$1
    local dir=$2
    
    # Try multiple naming conventions
    for name in "${base_name}-singularity.sif" "${base_name}.sif" "${base_name}-singularity_*.sif" "${base_name}_*.sif"; do
        local found=$(find "${dir}" -maxdepth 1 -name "${name}" -type f 2>/dev/null | head -1)
        if [ -n "${found}" ]; then
            echo "${found}"
            return 0
        fi
    done
    
    return 1
}

# Find SIF file with CUDA variant suffix
find_sif_file_cuda() {
    local base_name=$1
    local cuda_variant=$2  # e.g., "cu12" or "cu13"
    local dir=$3
    
    # Try versioned names first, then fallback to simple names
    for name in "${base_name}-${VERSION}-${cuda_variant}-singularity.sif" \
                "${base_name}-${cuda_variant}-singularity.sif" \
                "${base_name}-${cuda_variant}.sif" \
                "${base_name}-${cuda_variant}-singularity_*.sif" \
                "${base_name}-${cuda_variant}_*.sif" \
                "${base_name}-gpu-${cuda_variant}-singularity.sif" \
                "${base_name}-gpu-${cuda_variant}.sif"; do
        local found=$(find "${dir}" -maxdepth 1 -name "${name}" -type f 2>/dev/null | head -1)
        if [ -n "${found}" ]; then
            echo "${found}"
            return 0
        fi
    done
    
    return 1
}

# Push a SIF file to Sylabs
push_sif() {
    local variant=$1  # e.g., "cpu-singularity" or "gpu-cu124-singularity" or "gpu-cu128-singularity" or "gpu-cu13-singularity"
    local description=$2
    
    info "=== Pushing ${description} ==="
    
    # Find the SIF file
    local sif_file
    if [ "${variant}" = "cpu-singularity" ]; then
        sif_file=$(find_sif_file "anpta-cpu" "${SIF_DIR}") || \
        sif_file=$(find_sif_file "anpta_cpu" "${SIF_DIR}") || true
    elif [ "${variant}" = "gpu-cu124-singularity" ]; then
        sif_file=$(find_sif_file_cuda "anpta-gpu" "cu124" "${SIF_DIR}") || \
        sif_file=$(find_sif_file_cuda "anpta_gpu" "cu124" "${SIF_DIR}") || true
    elif [ "${variant}" = "gpu-cu128-singularity" ]; then
        sif_file=$(find_sif_file_cuda "anpta-gpu" "cu128" "${SIF_DIR}") || \
        sif_file=$(find_sif_file_cuda "anpta_gpu" "cu128" "${SIF_DIR}") || true
    elif [ "${variant}" = "gpu-cu13-singularity" ]; then
        sif_file=$(find_sif_file_cuda "anpta-gpu" "cu13" "${SIF_DIR}") || \
        sif_file=$(find_sif_file_cuda "anpta_gpu" "cu13" "${SIF_DIR}") || true
    else
        error "Unknown variant: ${variant}"
        return 1
    fi
    
    if [ -z "${sif_file}" ] || [ ! -f "${sif_file}" ]; then
        warn "SIF file not found for ${variant}"
        if [ "${variant}" = "cpu-singularity" ]; then
            warn "Expected names: anpta-${VERSION}-cpu-singularity.sif, anpta-cpu-singularity.sif, anpta-cpu.sif, anpta_cpu*.sif"
        elif [ "${variant}" = "gpu-cu124-singularity" ]; then
            warn "Expected names: anpta-${VERSION}-gpu-cu124-singularity.sif, anpta-gpu-cu124-singularity.sif, anpta-gpu-cu124.sif"
        elif [ "${variant}" = "gpu-cu128-singularity" ]; then
            warn "Expected names: anpta-${VERSION}-gpu-cu128-singularity.sif, anpta-gpu-cu128-singularity.sif, anpta-gpu-cu128.sif"
        elif [ "${variant}" = "gpu-cu13-singularity" ]; then
            warn "Expected names: anpta-${VERSION}-gpu-cu13-singularity.sif, anpta-gpu-cu13-singularity.sif, anpta-gpu-cu13.sif"
        fi
        warn "Looking in: ${SIF_DIR}"
        return 1
    fi
    
    info "Found SIF file: ${sif_file}"
    
    # Construct the library URI
    local library_uri="library://${SYLABS_USER}/${COLLECTION}/${variant}:${VERSION}"
    
    # Push to Sylabs
    info "Pushing to: ${library_uri}"
    if "${RUNNER}" push "${sif_file}" "${library_uri}"; then
        info "Successfully pushed ${variant}:${VERSION}"
        
        # Also create/update a 'latest' tag by pushing again
        local latest_uri="library://${SYLABS_USER}/${COLLECTION}/${variant}:latest"
        info "Creating 'latest' tag: ${latest_uri}"
        if "${RUNNER}" push "${sif_file}" "${latest_uri}"; then
            info "Successfully updated ${variant}:latest"
        else
            warn "Failed to update 'latest' tag (this is non-fatal)"
        fi
    else
        error "Failed to push ${variant}:${VERSION}"
        return 1
    fi
}

# Main execution
main() {
    info "Starting push to Sylabs Cloud Library"
    info "Version: ${VERSION}"
    info "User: ${SYLABS_USER}"
    info "Collection: ${COLLECTION}"
    info "SIF directory: ${SIF_DIR}"
    echo ""
    
    check_prerequisites
    echo ""
    
    # Track if any pushes failed
    local failed=0
    
    # Push CPU variant
    if ! push_sif "cpu-singularity" "CPU (Singularity) variant"; then
        failed=1
    fi
    echo ""
    
    # Push GPU CUDA 12.4 variant
    if ! push_sif "gpu-cu124-singularity" "GPU CUDA 12.4 (Singularity) variant"; then
        warn "GPU CUDA 12.4 variant not found or failed to push (skipping)"
        failed=1
    fi
    echo ""
    
    # Push GPU CUDA 12.8 variant
    if ! push_sif "gpu-cu128-singularity" "GPU CUDA 12.8 (Singularity) variant"; then
        warn "GPU CUDA 12.8 variant not found or failed to push (skipping)"
        failed=1
    fi
    echo ""
    
    # Push GPU CUDA 13 variant
    if ! push_sif "gpu-cu13-singularity" "GPU CUDA 13 (Singularity) variant"; then
        warn "GPU CUDA 13 variant not found or failed to push (skipping)"
        failed=1
    fi
    echo ""
    
    # Success summary
    if [ "${failed}" -eq 0 ]; then
        info "=== All images pushed successfully! ==="
        info ""
        info "Published images:"
        info "  - library://${SYLABS_USER}/${COLLECTION}/cpu-singularity:${VERSION}"
        info "  - library://${SYLABS_USER}/${COLLECTION}/cpu-singularity:latest"
        info "  - library://${SYLABS_USER}/${COLLECTION}/gpu-cu124-singularity:${VERSION}"
        info "  - library://${SYLABS_USER}/${COLLECTION}/gpu-cu124-singularity:latest"
        info "  - library://${SYLABS_USER}/${COLLECTION}/gpu-cu128-singularity:${VERSION}"
        info "  - library://${SYLABS_USER}/${COLLECTION}/gpu-cu128-singularity:latest"
        info "  - library://${SYLABS_USER}/${COLLECTION}/gpu-cu13-singularity:${VERSION}"
        info "  - library://${SYLABS_USER}/${COLLECTION}/gpu-cu13-singularity:latest"
        info ""
        info "Collaborators can pull with:"
        info "  ${RUNNER} pull library://${SYLABS_USER}/${COLLECTION}/cpu-singularity:${VERSION}"
        info "  ${RUNNER} pull library://${SYLABS_USER}/${COLLECTION}/gpu-cu124-singularity:${VERSION}"
        info "  ${RUNNER} pull library://${SYLABS_USER}/${COLLECTION}/gpu-cu128-singularity:${VERSION}"
        info "  ${RUNNER} pull library://${SYLABS_USER}/${COLLECTION}/gpu-cu13-singularity:${VERSION}"
        info ""
        info "Or view at: https://cloud.sylabs.io/library/${SYLABS_USER}/${COLLECTION}"
    else
        warn "Some images failed to push or were not found. Check the warnings above."
        warn "This is non-fatal - successfully pushed images are available."
        exit 0  # Don't fail if some variants are missing
    fi
}

# Run main function
main "$@"

