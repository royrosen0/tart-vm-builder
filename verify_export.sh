#!/bin/bash
# =============================================================================
# VM Export and Verification Script
# =============================================================================
# This script runs on the HOST machine (not inside the VM) to:
# 1. Verify the built VM exists
# 2. Export it to a compressed .aar archive
# 3. Generate a SHA256 checksum for integrity verification
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
VM_NAME="${1:-tahoe-full-stack}"
OUTPUT_DIR="${2:-.}"
OUTPUT_FILE="${OUTPUT_DIR}/${VM_NAME}.aar"
CHECKSUM_FILE="${OUTPUT_FILE}.sha256"

# -----------------------------------------------------------------------------
# Colors for output
# -----------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# -----------------------------------------------------------------------------
# Helper functions
# -----------------------------------------------------------------------------
info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# -----------------------------------------------------------------------------
# Print banner
# -----------------------------------------------------------------------------
echo ""
echo "=============================================="
echo "  Tart VM Export and Verification"
echo "=============================================="
echo ""
echo "VM Name:      ${VM_NAME}"
echo "Output File:  ${OUTPUT_FILE}"
echo "Checksum:     ${CHECKSUM_FILE}"
echo ""

# -----------------------------------------------------------------------------
# Step 1: Check if tart is installed
# -----------------------------------------------------------------------------
info "Checking for tart installation..."
if ! command -v tart &> /dev/null; then
    error "tart is not installed. Install it with: brew install cirruslabs/cli/tart"
fi
success "tart is installed: $(tart --version 2>/dev/null || echo 'version unknown')"

# -----------------------------------------------------------------------------
# Step 2: Check if VM exists
# -----------------------------------------------------------------------------
info "Checking if VM '${VM_NAME}' exists..."

if ! tart list | grep -q "^${VM_NAME}"; then
    echo ""
    warn "Available VMs:"
    tart list
    echo ""
    error "VM '${VM_NAME}' not found. Please run the Packer build first."
fi
success "VM '${VM_NAME}' found"

# -----------------------------------------------------------------------------
# Step 3: Get VM information
# -----------------------------------------------------------------------------
info "Getting VM information..."
echo ""
tart get "${VM_NAME}" 2>/dev/null || true
echo ""

# -----------------------------------------------------------------------------
# Step 4: Create output directory if needed
# -----------------------------------------------------------------------------
if [ ! -d "${OUTPUT_DIR}" ]; then
    info "Creating output directory: ${OUTPUT_DIR}"
    mkdir -p "${OUTPUT_DIR}"
fi

# -----------------------------------------------------------------------------
# Step 5: Check for existing export
# -----------------------------------------------------------------------------
if [ -f "${OUTPUT_FILE}" ]; then
    warn "Export file already exists: ${OUTPUT_FILE}"
    read -p "Do you want to overwrite? (y/N) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "Export cancelled by user"
        exit 0
    fi
    rm -f "${OUTPUT_FILE}" "${CHECKSUM_FILE}"
fi

# -----------------------------------------------------------------------------
# Step 6: Export VM to .aar archive
# -----------------------------------------------------------------------------
info "Exporting VM to compressed archive..."
info "This may take several minutes depending on VM size..."
echo ""

# Record start time
START_TIME=$(date +%s)

# Run the export
tart export "${VM_NAME}" "${OUTPUT_FILE}"

# Calculate duration
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
MINUTES=$((DURATION / 60))
SECONDS=$((DURATION % 60))

echo ""
success "Export completed in ${MINUTES}m ${SECONDS}s"

# -----------------------------------------------------------------------------
# Step 7: Generate SHA256 checksum
# -----------------------------------------------------------------------------
info "Generating SHA256 checksum..."

# Generate checksum (macOS uses shasum, Linux uses sha256sum)
if command -v shasum &> /dev/null; then
    shasum -a 256 "${OUTPUT_FILE}" > "${CHECKSUM_FILE}"
elif command -v sha256sum &> /dev/null; then
    sha256sum "${OUTPUT_FILE}" > "${CHECKSUM_FILE}"
else
    error "Neither shasum nor sha256sum found. Cannot generate checksum."
fi

success "Checksum saved to: ${CHECKSUM_FILE}"

# -----------------------------------------------------------------------------
# Step 8: Display results
# -----------------------------------------------------------------------------
echo ""
echo "=============================================="
echo "  Export Complete"
echo "=============================================="
echo ""

# Get file size
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    FILE_SIZE_BYTES=$(stat -f%z "${OUTPUT_FILE}")
else
    # Linux
    FILE_SIZE_BYTES=$(stat -c%s "${OUTPUT_FILE}")
fi

# Convert to human readable
FILE_SIZE_GB=$(echo "scale=2; ${FILE_SIZE_BYTES} / 1024 / 1024 / 1024" | bc)
FILE_SIZE_MB=$(echo "scale=2; ${FILE_SIZE_BYTES} / 1024 / 1024" | bc)

echo "Archive Details:"
echo "  File:     ${OUTPUT_FILE}"
echo "  Size:     ${FILE_SIZE_GB} GB (${FILE_SIZE_MB} MB)"
echo ""

echo "Checksum (SHA256):"
cat "${CHECKSUM_FILE}"
echo ""

echo "=============================================="
echo "  Verification Instructions"
echo "=============================================="
echo ""
echo "To verify the archive after transfer, run:"
echo ""
echo "  shasum -a 256 -c ${CHECKSUM_FILE}"
echo ""
echo "Or manually compare the checksum:"
echo ""
echo "  shasum -a 256 ${OUTPUT_FILE}"
echo ""
echo "To import the VM on the target system:"
echo ""
echo "  tart import ${VM_NAME} ${OUTPUT_FILE}"
echo ""
success "All done! The archive is ready for transfer."

