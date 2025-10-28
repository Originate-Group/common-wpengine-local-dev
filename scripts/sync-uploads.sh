#!/bin/bash
# Sync Uploads from WP Engine
# Downloads media files from WP Engine environment
# WARNING: This can be VERY large (GBs of data)

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"

# Source configuration parser
if [[ -f "${LIB_DIR}/config-parser.sh" ]]; then
    source "${LIB_DIR}/config-parser.sh"
else
    echo "Error: config-parser.sh not found"
    exit 1
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Load configuration
if [[ ! -f "local-config.yml" ]]; then
    echo -e "${RED}Error: local-config.yml not found${NC}"
    echo -e "${YELLOW}Please run this script from your project root directory${NC}"
    exit 1
fi

load_config "local-config.yml"

echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}         WP Engine Uploads Sync${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo ""

show_config

echo ""
echo -e "${YELLOW}⚠  WARNING: Media uploads can be very large (GBs of data)${NC}"
echo -e "${YELLOW}   This may take a long time and use significant bandwidth${NC}"
echo ""

# Check uploads size on remote
echo -e "${BLUE}Checking remote uploads size...${NC}"

REMOTE_SIZE=$(ssh -i "$WPENGINE_SSH_KEY" -o StrictHostKeyChecking=no \
    "${WPENGINE_SSH_USER}@${WPENGINE_SSH_HOST}" \
    "du -sh ${WPENGINE_SITE_PATH}/wp-content/uploads 2>/dev/null | cut -f1" || echo "Unknown")

echo -e "  Remote uploads size: ${YELLOW}${REMOTE_SIZE}${NC}"
echo ""

# Confirm before proceeding (skip if running non-interactively from setup)
if [[ -t 0 ]] && [[ -z "${SETUP_NON_INTERACTIVE}" ]]; then
    read -p "$(echo -e ${YELLOW}Proceed with download? [y/N]: ${NC})" -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Sync cancelled${NC}"
        exit 0
    fi
else
    echo -e "${YELLOW}Running in non-interactive mode, proceeding automatically...${NC}"
fi

echo ""
echo -e "${BLUE}Starting uploads sync...${NC}"
echo ""

# Create uploads directory if it doesn't exist
mkdir -p uploads

echo -e "${BLUE}Step 1: Downloading uploads from WP Engine...${NC}"
echo -e "  Source: ${WPENGINE_SSH_USER}@${WPENGINE_SSH_HOST}:${WPENGINE_SITE_PATH}/wp-content/uploads/"
echo -e "  Destination: uploads/"
echo ""

# Download uploads via rsync with progress
# Using --size-only for faster sync (WP Engine doesn't preserve timestamps well)
rsync -avz --progress --size-only \
    -e "ssh -i ${WPENGINE_SSH_KEY} -o StrictHostKeyChecking=no" \
    "${WPENGINE_SSH_USER}@${WPENGINE_SSH_HOST}:${WPENGINE_SITE_PATH}/wp-content/uploads/" \
    "uploads/"

if [[ $? -eq 0 ]]; then
    LOCAL_SIZE=$(du -sh uploads | cut -f1)
    FILE_COUNT=$(find uploads -type f | wc -l)
    echo -e "${GREEN}✓ Uploads downloaded successfully${NC}"
    echo -e "  Files: ${FILE_COUNT}"
    echo -e "  Local size: ${LOCAL_SIZE}"
else
    echo -e "${RED}✗ Upload download failed${NC}"
    exit 1
fi

echo ""

# Step 2: Fix permissions
echo -e "${BLUE}Step 2: Fixing permissions...${NC}"

chmod -R 755 uploads/
find uploads/ -type f -exec chmod 644 {} \;

echo -e "${GREEN}✓ Permissions fixed${NC}"

echo ""

# Step 3: Create .gitignore for uploads (if not exists)
if [[ ! -f "uploads/.gitignore" ]]; then
    echo -e "${BLUE}Step 3: Creating .gitignore for uploads...${NC}"
    cat > uploads/.gitignore <<EOF
# Ignore all uploads
*
!.gitignore

# Uploads should not be committed to Git
# They are synced from WP Engine as needed
EOF
    echo -e "${GREEN}✓ .gitignore created${NC}"
else
    echo -e "${YELLOW}Step 3: .gitignore already exists (skipping)${NC}"
fi

echo ""

echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}         Uploads sync completed successfully!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo -e "  1. Media files are now available at: ${GREEN}${SITE_URL}/wp-content/uploads/${NC}"
echo -e "  2. Test your site to verify images load correctly"
echo ""
echo -e "${YELLOW}Note: To re-sync uploads in the future, run this script again${NC}"
echo -e "${YELLOW}      rsync will only download changed/new files${NC}"
echo ""
