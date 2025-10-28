#!/bin/bash
# Sync Database from WP Engine
# Downloads and imports database from WP Engine environment

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
echo -e "${BLUE}         WP Engine Database Sync${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo ""

show_config

echo ""
echo -e "${BLUE}Starting database sync...${NC}"
echo ""

# Check if Docker is running
if ! docker info >/dev/null 2>&1; then
    echo -e "${RED}Error: Docker is not running${NC}"
    exit 1
fi

# Check if database container exists
if ! docker ps -a --format '{{.Names}}' | grep -q "^${PROJECT_NAME}-mysql$"; then
    echo -e "${RED}Error: MySQL container not found${NC}"
    echo -e "${YELLOW}Please run setup.sh first to create Docker containers${NC}"
    exit 1
fi

# Check if MySQL container is running
if ! docker ps --format '{{.Names}}' | grep -q "^${PROJECT_NAME}-mysql$"; then
    echo -e "${YELLOW}MySQL container is not running. Starting...${NC}"
    docker start "${PROJECT_NAME}-mysql"
    echo -e "${GREEN}✓ MySQL container started${NC}"
    echo -e "${YELLOW}Waiting for MySQL to be ready...${NC}"
    sleep 10
fi

# Backup filename
BACKUP_FILE="${HOME}/${WPENGINE_ENV}-$(date +%Y%m%d-%H%M%S).sql"

# Step 1: Export database from WP Engine
echo -e "${BLUE}Step 1: Exporting database from WP Engine...${NC}"
echo -e "  Environment: ${WPENGINE_ENV}"
echo -e "  SSH: ${WPENGINE_SSH_USER}@${WPENGINE_SSH_HOST}"
echo ""

# Export database on WP Engine and download via SSH
ssh -i "$WPENGINE_SSH_KEY" -o StrictHostKeyChecking=no \
    "${WPENGINE_SSH_USER}@${WPENGINE_SSH_HOST}" \
    "cd ${WPENGINE_SITE_PATH} && wp db export - --quiet" > "$BACKUP_FILE"

if [[ $? -eq 0 ]] && [[ -f "$BACKUP_FILE" ]]; then
    FILE_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
    echo -e "${GREEN}✓ Database exported successfully${NC}"
    echo -e "  Location: ${BACKUP_FILE}"
    echo -e "  Size: ${FILE_SIZE}"
else
    echo -e "${RED}✗ Database export failed${NC}"
    exit 1
fi

echo ""

# Step 2: Import database to local MySQL
echo -e "${BLUE}Step 2: Importing database to local MySQL...${NC}"

# Drop and recreate database
docker exec -i "${PROJECT_NAME}-mysql" mysql -uroot -p"${DB_ROOT_PASSWORD}" <<EOF
DROP DATABASE IF EXISTS ${DB_NAME};
CREATE DATABASE ${DB_NAME};
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'%';
FLUSH PRIVILEGES;
EOF

if [[ $? -ne 0 ]]; then
    echo -e "${RED}✗ Failed to prepare database${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Database prepared${NC}"

# Import SQL file
docker exec -i "${PROJECT_NAME}-mysql" mysql -u"${DB_USER}" -p"${DB_PASSWORD}" "${DB_NAME}" < "$BACKUP_FILE"

if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}✓ Database imported successfully${NC}"
else
    echo -e "${RED}✗ Database import failed${NC}"
    exit 1
fi

echo ""

# Step 3: Verify import
echo -e "${BLUE}Step 3: Verifying database import...${NC}"

TABLE_COUNT=$(docker exec "${PROJECT_NAME}-mysql" mysql -u"${DB_USER}" -p"${DB_PASSWORD}" "${DB_NAME}" -sN -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${DB_NAME}';")

if [[ $TABLE_COUNT -gt 0 ]]; then
    echo -e "${GREEN}✓ Database verification passed${NC}"
    echo -e "  Tables imported: ${TABLE_COUNT}"
else
    echo -e "${RED}✗ Database verification failed${NC}"
    echo -e "  No tables found in database"
    exit 1
fi

echo ""

# Step 4: URL replacement (if enabled)
if [[ "$SYNC_URL_REPLACEMENT" == "true" ]]; then
    echo -e "${BLUE}Step 4: Replacing production URLs with local URLs...${NC}"

    # Wait for WordPress container to be ready
    if ! docker ps --format '{{.Names}}' | grep -q "^${PROJECT_NAME}-wordpress$"; then
        echo -e "${YELLOW}WordPress container is not running. Starting...${NC}"
        docker start "${PROJECT_NAME}-wordpress"
        sleep 5
    fi

    # Get production URL from database
    PROD_URL=$(docker exec "${PROJECT_NAME}-mysql" mysql -u"${DB_USER}" -p"${DB_PASSWORD}" "${DB_NAME}" -sN -e "SELECT option_value FROM wp_options WHERE option_name='siteurl' LIMIT 1;")

    if [[ -n "$PROD_URL" ]]; then
        echo -e "  Production URL: ${PROD_URL}"
        echo -e "  Local URL: ${SITE_URL}"

        # Use WP-CLI for URL replacement (handles serialized data correctly)
        if docker exec "${PROJECT_NAME}-wpcli" wp search-replace "$PROD_URL" "$SITE_URL" \
            --skip-columns=guid \
            --allow-root; then
            echo -e "${GREEN}✓ URLs replaced successfully${NC}"
        else
            echo -e "${RED}✗ URL replacement FAILED${NC}"
            echo -e "${YELLOW}This is a CRITICAL error - WordPress will redirect to production${NC}"
            echo -e "${YELLOW}Verify wp-config.php exists and WP-CLI can access WordPress${NC}"
            exit 1
        fi
    else
        echo -e "${YELLOW}⚠ Could not detect production URL, skipping replacement${NC}"
    fi
else
    echo -e "${YELLOW}Step 4: URL replacement disabled (skipping)${NC}"
fi

echo ""

# Step 5: Deactivate problematic plugins
echo -e "${BLUE}Step 5: Deactivating problematic plugins...${NC}"

# Plugins that might cause issues in local development
DEACTIVATE_PLUGINS=(
    "wordfence"
    "wp-rocket"
    "cloudflare"
    "jetpack"
)

for plugin in "${DEACTIVATE_PLUGINS[@]}"; do
    docker exec "${PROJECT_NAME}-wpcli" wp plugin deactivate "$plugin" --quiet --allow-root 2>/dev/null || true
done

echo -e "${GREEN}✓ Plugins deactivated${NC}"

echo ""

# Step 6: Clear cache
echo -e "${BLUE}Step 6: Clearing WordPress cache...${NC}"

docker exec "${PROJECT_NAME}-wpcli" wp cache flush --quiet --allow-root 2>/dev/null || true
docker exec "${PROJECT_NAME}-wpcli" wp transient delete --all --quiet --allow-root 2>/dev/null || true

echo -e "${GREEN}✓ Cache cleared${NC}"

echo ""

# Step 7: Create test admin user
echo -e "${BLUE}Step 7: Creating test admin user...${NC}"

docker exec "${PROJECT_NAME}-wpcli" wp user create testAdmin test@example.com \
    --role=administrator \
    --user_pass=adminADMIN \
    --allow-root 2>/dev/null || true

echo -e "${GREEN}✓ Test admin user created (testAdmin / adminADMIN)${NC}"

echo ""

# Step 8: Cleanup backup file (optional)
# Skip interactive prompt if running from setup.sh (non-interactive mode)
if [[ -t 0 ]] && [[ -z "${SETUP_NON_INTERACTIVE}" ]]; then
    read -p "$(echo -e ${YELLOW}Delete local backup file? [y/N]: ${NC})" -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm "$BACKUP_FILE"
        echo -e "${GREEN}✓ Backup file deleted${NC}"
    else
        echo -e "${YELLOW}Backup file saved: ${BACKUP_FILE}${NC}"
    fi
else
    # Non-interactive mode: keep backup file
    echo -e "${YELLOW}Backup file saved: ${BACKUP_FILE}${NC}"
fi

echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}         Database sync completed successfully!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo -e "  1. Open WordPress: ${GREEN}${SITE_URL}${NC}"
echo -e "  2. Open phpMyAdmin: ${GREEN}http://localhost:${PHPMYADMIN_PORT}${NC}"
echo -e "  3. Run plugin sync if needed: ${GREEN}./scripts/sync-plugins.sh${NC}"
echo ""
