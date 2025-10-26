#!/bin/bash
# WP Engine Local Development Environment Setup
# Orchestrates the complete setup process

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ASCII Art Banner
echo -e "${CYAN}"
cat << "EOF"
╦ ╦╔═╗  ╔═╗┌┐┌┌─┐┬┌┐┌┌─┐
║║║╠═╝  ║╣ ││││ ┬││││├┤
╚╩╝╩    ╚═╝┘└┘└─┘┴┘└┘└─┘
╦  ┌─┐┌─┐┌─┐┬    ╔╦╗┌─┐┬  ┬
║  │ ││  ├─┤│     ║║├┤ └┐┌┘
╩═╝└─┘└─┘┴ ┴┴─┘  ═╩╝└─┘ └┘
EOF
echo -e "${NC}"

echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}    WP Engine Local Development Environment Setup${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo ""

# Get the directory where this script is located (the submodule/common repo)
WPENGINE_LOCAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="${WPENGINE_LOCAL_DIR}/scripts"
LIB_DIR="${SCRIPTS_DIR}/lib"
TEMPLATES_DIR="${WPENGINE_LOCAL_DIR}/templates"

# Project root is the parent directory (where the user's project is)
PROJECT_ROOT="$(cd "${WPENGINE_LOCAL_DIR}/.." && pwd)"

echo -e "${BLUE}Setup Information:${NC}"
echo -e "  Common repo: ${WPENGINE_LOCAL_DIR}"
echo -e "  Project root: ${PROJECT_ROOT}"
echo ""

# Change to project root
cd "$PROJECT_ROOT"

# Step 1: Check prerequisites
echo -e "${BLUE}Step 1: Checking prerequisites...${NC}"

# Check Docker
if ! command -v docker &> /dev/null; then
    echo -e "${RED}✗ Docker not found${NC}"
    echo -e "${YELLOW}Please install Docker: https://docs.docker.com/get-docker/${NC}"
    exit 1
fi

# Check Docker Compose
if ! docker compose version &> /dev/null; then
    echo -e "${RED}✗ Docker Compose not found${NC}"
    echo -e "${YELLOW}Please install Docker Compose (usually included with Docker Desktop)${NC}"
    exit 1
fi

# Check Docker is running
if ! docker info &> /dev/null; then
    echo -e "${RED}✗ Docker daemon is not running${NC}"
    echo -e "${YELLOW}Please start Docker and try again${NC}"
    exit 1
fi

# Check rsync
if ! command -v rsync &> /dev/null; then
    echo -e "${YELLOW}⚠ rsync not found (required for syncing plugins/uploads)${NC}"
    echo -e "${YELLOW}Install: apt-get install rsync (Linux) or brew install rsync (macOS)${NC}"
fi

# Check SSH
if ! command -v ssh &> /dev/null; then
    echo -e "${RED}✗ SSH not found${NC}"
    echo -e "${YELLOW}SSH is required to connect to WP Engine${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Prerequisites met${NC}"
echo ""

# Step 2: Configuration
echo -e "${BLUE}Step 2: Configuration${NC}"

if [[ ! -f "local-config.yml" ]]; then
    echo -e "${YELLOW}local-config.yml not found. Creating from template...${NC}"

    if [[ -f "${TEMPLATES_DIR}/local-config.yml.example" ]]; then
        cp "${TEMPLATES_DIR}/local-config.yml.example" local-config.yml
        echo -e "${GREEN}✓ Created local-config.yml${NC}"
        echo -e "${YELLOW}⚠ Please edit local-config.yml with your WP Engine details${NC}"
        echo ""
        echo -e "${CYAN}Required configuration:${NC}"
        echo -e "  - client.project_name"
        echo -e "  - wpengine.environment"
        echo -e "  - wpengine.ssh_user"
        echo -e "  - wpengine.ssh_host"
        echo -e "  - wpengine.ssh_key (path to your SSH key)"
        echo ""
        echo -e "${YELLOW}After editing, run this script again${NC}"
        exit 0
    else
        echo -e "${RED}✗ Template not found: ${TEMPLATES_DIR}/local-config.yml.example${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}✓ Configuration file found${NC}"
fi

# Load and validate configuration
source "${LIB_DIR}/config-parser.sh"
load_config "local-config.yml"

if ! validate_config; then
    echo -e "${RED}Configuration validation failed${NC}"
    exit 1
fi

echo ""

# Step 3: Create required directories
echo -e "${BLUE}Step 3: Creating required directories...${NC}"

mkdir -p docker/php
mkdir -p docker/mysql-init
mkdir -p plugins
mkdir -p themes
mkdir -p mu-plugins
mkdir -p uploads

# Create index.php in plugins to prevent directory listing
if [[ ! -f "plugins/index.php" ]]; then
    echo "<?php" > plugins/index.php
    echo "// Silence is golden." >> plugins/index.php
fi

echo -e "${GREEN}✓ Directories created${NC}"
echo ""

# Step 4: Generate configuration files
echo -e "${BLUE}Step 4: Generating configuration files...${NC}"

# Generate docker-compose.yml from template
if [[ -f "${TEMPLATES_DIR}/docker-compose.yml.template" ]]; then
    envsubst < "${TEMPLATES_DIR}/docker-compose.yml.template" > docker-compose.yml
    echo -e "${GREEN}✓ Generated docker-compose.yml${NC}"
else
    echo -e "${RED}✗ Template not found: docker-compose.yml.template${NC}"
    exit 1
fi

# Generate php.ini from template
if [[ -f "${TEMPLATES_DIR}/php.ini.template" ]]; then
    envsubst < "${TEMPLATES_DIR}/php.ini.template" > docker/php/php.ini
    echo -e "${GREEN}✓ Generated docker/php/php.ini${NC}"
else
    echo -e "${RED}✗ Template not found: php.ini.template${NC}"
    exit 1
fi

# Copy .dockerignore if not exists
if [[ ! -f ".dockerignore" ]] && [[ -f "${TEMPLATES_DIR}/.dockerignore.template" ]]; then
    cp "${TEMPLATES_DIR}/.dockerignore.template" .dockerignore
    echo -e "${GREEN}✓ Created .dockerignore${NC}"
fi

# Create/update .gitignore if needed
if [[ ! -f ".gitignore" ]] && [[ -f "${TEMPLATES_DIR}/.gitignore.template" ]]; then
    cp "${TEMPLATES_DIR}/.gitignore.template" .gitignore
    echo -e "${GREEN}✓ Created .gitignore${NC}"
elif [[ -f ".gitignore" ]]; then
    echo -e "${YELLOW}✓ .gitignore already exists (not modified)${NC}"
fi

echo ""

# Step 5: Start Docker containers
echo -e "${BLUE}Step 5: Starting Docker containers...${NC}"

docker compose up -d

if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}✓ Docker containers started${NC}"
else
    echo -e "${RED}✗ Failed to start Docker containers${NC}"
    exit 1
fi

echo ""

# Wait for MySQL to be ready
echo -e "${BLUE}Waiting for MySQL to be ready...${NC}"
MAX_WAIT=30
WAIT_COUNT=0

while [[ $WAIT_COUNT -lt $MAX_WAIT ]]; do
    if docker exec "${PROJECT_NAME}-mysql" mysqladmin ping -h localhost -u root -p"${DB_ROOT_PASSWORD}" &> /dev/null; then
        echo -e "${GREEN}✓ MySQL is ready${NC}"
        break
    fi
    ((WAIT_COUNT++))
    echo -n "."
    sleep 1
done

if [[ $WAIT_COUNT -ge $MAX_WAIT ]]; then
    echo -e "${RED}✗ MySQL failed to start${NC}"
    exit 1
fi

echo ""

# Step 6: Sync data from WP Engine
echo -e "${BLUE}Step 6: Sync data from WP Engine${NC}"
echo ""

# Show sync configuration
echo -e "${CYAN}Sync configuration:${NC}"
echo -e "  Database: ${SYNC_DATABASE}"
echo -e "  Plugins: ${SYNC_PLUGINS}"
echo -e "  Uploads: ${SYNC_UPLOADS}"
echo ""

# Database sync
if [[ "$SYNC_DATABASE" == "true" ]]; then
    echo -e "${BLUE}Syncing database...${NC}"
    if [[ -x "${SCRIPTS_DIR}/sync-database.sh" ]]; then
        bash "${SCRIPTS_DIR}/sync-database.sh"
    else
        echo -e "${RED}✗ sync-database.sh not found or not executable${NC}"
    fi
else
    echo -e "${YELLOW}⊘ Database sync disabled${NC}"
fi

echo ""

# Plugins sync
if [[ "$SYNC_PLUGINS" == "true" ]]; then
    echo -e "${BLUE}Syncing plugins...${NC}"
    if [[ -x "${SCRIPTS_DIR}/sync-plugins.sh" ]]; then
        bash "${SCRIPTS_DIR}/sync-plugins.sh"
    else
        echo -e "${RED}✗ sync-plugins.sh not found or not executable${NC}"
    fi
else
    echo -e "${YELLOW}⊘ Plugins sync disabled${NC}"
fi

echo ""

# Uploads sync
if [[ "$SYNC_UPLOADS" == "true" ]]; then
    echo -e "${BLUE}Syncing uploads...${NC}"
    if [[ -x "${SCRIPTS_DIR}/sync-uploads.sh" ]]; then
        bash "${SCRIPTS_DIR}/sync-uploads.sh"
    else
        echo -e "${RED}✗ sync-uploads.sh not found or not executable${NC}"
    fi
else
    echo -e "${YELLOW}⊘ Uploads sync disabled${NC}"
fi

echo ""

# Final steps
echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}    Setup completed successfully!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
echo ""

show_config

echo ""
echo -e "${CYAN}Quick start:${NC}"
echo -e "  ${GREEN}WordPress:${NC}    ${SITE_URL}"
echo -e "  ${GREEN}phpMyAdmin:${NC}   http://localhost:${PHPMYADMIN_PORT}"
echo -e "  ${GREEN}WP Admin:${NC}     ${SITE_URL}/wp-admin"
echo ""
echo -e "${CYAN}Useful commands:${NC}"
echo -e "  ${GREEN}Stop containers:${NC}  docker compose down"
echo -e "  ${GREEN}Start containers:${NC} docker compose up -d"
echo -e "  ${GREEN}View logs:${NC}        docker compose logs -f"
echo -e "  ${GREEN}WP-CLI:${NC}           docker compose run --rm wpcli wp <command>"
echo ""
echo -e "${CYAN}Sync scripts (run from project root):${NC}"
echo -e "  ${GREEN}Database:${NC}         ${WPENGINE_LOCAL_DIR}/scripts/sync-database.sh"
echo -e "  ${GREEN}Plugins:${NC}          ${WPENGINE_LOCAL_DIR}/scripts/sync-plugins.sh"
echo -e "  ${GREEN}Uploads:${NC}          ${WPENGINE_LOCAL_DIR}/scripts/sync-uploads.sh"
echo ""
echo -e "${YELLOW}Note: Login credentials are the same as your WP Engine environment${NC}"
echo ""
