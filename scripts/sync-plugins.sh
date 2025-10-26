#!/bin/bash
# Sync Plugins from WP Engine
# Downloads plugins from WP Engine environment

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
echo -e "${BLUE}         WP Engine Plugins Sync${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo ""

show_config

echo ""
echo -e "${BLUE}Starting plugins sync...${NC}"
echo ""

# Create plugins directory if it doesn't exist
mkdir -p plugins

# Temporary download location
TEMP_DIR="/tmp/${PROJECT_NAME}-plugins-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$TEMP_DIR"

echo -e "${BLUE}Step 1: Downloading plugins from WP Engine...${NC}"
echo -e "  Source: ${WPENGINE_SSH_USER}@${WPENGINE_SSH_HOST}:${WPENGINE_SITE_PATH}/wp-content/plugins/"
echo -e "  Destination: ${TEMP_DIR}/"
echo ""

# Download plugins via rsync
rsync -avz --progress \
    -e "ssh -i ${WPENGINE_SSH_KEY} -o StrictHostKeyChecking=no" \
    "${WPENGINE_SSH_USER}@${WPENGINE_SSH_HOST}:${WPENGINE_SITE_PATH}/wp-content/plugins/" \
    "${TEMP_DIR}/"

if [[ $? -eq 0 ]]; then
    PLUGIN_COUNT=$(find "$TEMP_DIR" -mindepth 1 -maxdepth 1 -type d | wc -l)
    TOTAL_SIZE=$(du -sh "$TEMP_DIR" | cut -f1)
    echo -e "${GREEN}✓ Plugins downloaded successfully${NC}"
    echo -e "  Plugins: ${PLUGIN_COUNT}"
    echo -e "  Total size: ${TOTAL_SIZE}"
else
    echo -e "${RED}✗ Plugin download failed${NC}"
    rm -rf "$TEMP_DIR"
    exit 1
fi

echo ""

# Step 2: Copy to plugins directory
echo -e "${BLUE}Step 2: Copying plugins to project...${NC}"

# Keep index.php if it exists
if [[ -f "plugins/index.php" ]]; then
    cp "plugins/index.php" "${TEMP_DIR}/index.php"
fi

# Remove old plugins (except those in .gitignore exclusions)
if [[ -d "plugins" ]]; then
    echo -e "${YELLOW}Backing up existing plugins...${NC}"
    BACKUP_DIR="/tmp/${PROJECT_NAME}-plugins-backup-$(date +%Y%m%d-%H%M%S)"
    mv plugins "$BACKUP_DIR"
    echo -e "${GREEN}✓ Backup created: ${BACKUP_DIR}${NC}"
fi

# Copy downloaded plugins
mkdir -p plugins
cp -r "${TEMP_DIR}/"* plugins/

# Ensure index.php exists
if [[ ! -f "plugins/index.php" ]]; then
    echo "<?php\n// Silence is golden." > plugins/index.php
fi

echo -e "${GREEN}✓ Plugins copied to project${NC}"

echo ""

# Step 3: Fix permissions
echo -e "${BLUE}Step 3: Fixing permissions...${NC}"

chmod -R 755 plugins/
find plugins/ -type f -exec chmod 644 {} \;

echo -e "${GREEN}✓ Permissions fixed${NC}"

echo ""

# Step 4: Restart WordPress container (to ensure plugins are loaded)
echo -e "${BLUE}Step 4: Restarting WordPress container...${NC}"

if docker ps --format '{{.Names}}' | grep -q "^${PROJECT_NAME}-wordpress$"; then
    docker restart "${PROJECT_NAME}-wordpress" >/dev/null
    echo -e "${GREEN}✓ WordPress container restarted${NC}"
    sleep 3
else
    echo -e "${YELLOW}⚠ WordPress container not running (will load plugins on next start)${NC}"
fi

echo ""

# Step 5: Activate plugins (if configured)
CONFIG_FILE="local-config.yml"
ACTIVATE_PLUGINS=$(grep -A 20 "^plugins:" "$CONFIG_FILE" | grep -A 10 "activate:" | grep "^    - " | sed 's/^    - //' || echo "")

if [[ -n "$ACTIVATE_PLUGINS" ]]; then
    echo -e "${BLUE}Step 5: Activating configured plugins...${NC}"

    # Check if WP-CLI container is available
    if docker ps -a --format '{{.Names}}' | grep -q "^${PROJECT_NAME}-wpcli$"; then
        # Start WP-CLI container if not running
        if ! docker ps --format '{{.Names}}' | grep -q "^${PROJECT_NAME}-wpcli$"; then
            docker start "${PROJECT_NAME}-wpcli" >/dev/null 2>&1
        fi

        while IFS= read -r plugin; do
            [[ -z "$plugin" ]] && continue
            echo -e "  Activating: ${plugin}..."
            docker exec "${PROJECT_NAME}-wpcli" wp plugin activate "$plugin" --quiet --allow-root 2>/dev/null || \
                echo -e "  ${YELLOW}⚠ Could not activate: ${plugin}${NC}"
        done <<< "$ACTIVATE_PLUGINS"

        echo -e "${GREEN}✓ Plugins activated${NC}"
    else
        echo -e "${YELLOW}⚠ WP-CLI container not available (skip plugin activation)${NC}"
        echo -e "${YELLOW}  Run 'docker compose up -d' and then activate plugins manually${NC}"
    fi
else
    echo -e "${YELLOW}Step 5: No plugins configured for activation (skipping)${NC}"
fi

echo ""

# Cleanup
echo -e "${BLUE}Cleaning up temporary files...${NC}"
rm -rf "$TEMP_DIR"
echo -e "${GREEN}✓ Cleanup complete${NC}"

echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}         Plugins sync completed successfully!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo -e "  1. Verify plugins in WordPress admin: ${GREEN}${SITE_URL}/wp-admin/plugins.php${NC}"
echo -e "  2. Activate/deactivate plugins as needed"
echo -e "  3. Test your site: ${GREEN}${SITE_URL}${NC}"
echo ""
