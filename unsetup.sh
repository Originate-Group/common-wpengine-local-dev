#!/bin/bash
# WP Engine Local Development Environment Cleanup
# Removes all local development files and Docker containers

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${RED}"
cat << "EOF"
╦ ╦╔═╗  ╔═╗┌┐┌┌─┐┬┌┐┌┌─┐
║║║╠═╝  ║╣ ││││ ┬││││├┤
╚╩╝╩    ╚═╝┘└┘└─┘┴┘└┘└─┘
╔═╗┬  ┌─┐┌─┐┌┐┌┬ ┬┌─┐
║  │  ├┤ ├─┤││││ │├─┘
╚═╝┴─┘└─┘┴ ┴┘└┘└─┘┴
EOF
echo -e "${NC}"

echo -e "${RED}═══════════════════════════════════════════════════════${NC}"
echo -e "${RED}    WP Engine Local Development Cleanup${NC}"
echo -e "${RED}═══════════════════════════════════════════════════════${NC}"
echo ""

# Get the directory where this script is located (the submodule/common repo)
WPENGINE_LOCAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="${WPENGINE_LOCAL_DIR}/scripts"
LIB_DIR="${SCRIPTS_DIR}/lib"

# Project root is the parent directory (where the user's project is)
PROJECT_ROOT="$(cd "${WPENGINE_LOCAL_DIR}/.." && pwd)"

echo -e "${BLUE}Cleanup Information:${NC}"
echo -e "  Common repo: ${WPENGINE_LOCAL_DIR}"
echo -e "  Project root: ${PROJECT_ROOT}"
echo ""

# Change to project root
cd "$PROJECT_ROOT"

# Load configuration if available (to get project name)
if [[ -f "local-config.yml" ]] && [[ -f "${LIB_DIR}/config-parser.sh" ]]; then
    source "${LIB_DIR}/config-parser.sh"
    load_config "local-config.yml" 2>/dev/null || true
fi

# If PROJECT_NAME is not set, try to detect it from docker containers
if [[ -z "$PROJECT_NAME" ]]; then
    echo -e "${YELLOW}Project name not found in config, detecting from Docker...${NC}"
    # Try to find containers with common suffixes
    PROJECT_NAME=$(docker ps -a --format '{{.Names}}' | grep -E '-(wordpress|mysql|phpmyadmin|wpcli)$' | sed 's/-\(wordpress\|mysql\|phpmyadmin\|wpcli\)$//' | head -1 || echo "")
fi

if [[ -z "$PROJECT_NAME" ]]; then
    echo -e "${YELLOW}Could not detect project name. Will attempt to clean all local containers.${NC}"
fi

echo ""
echo -e "${YELLOW}⚠  WARNING: This will permanently delete:${NC}"
echo -e "  ${RED}✗${NC} All Docker containers and volumes for this project"
echo -e "  ${RED}✗${NC} Generated docker-compose.yml"
echo -e "  ${RED}✗${NC} docker/ directory"
echo -e "  ${RED}✗${NC} plugins/ directory (except Git-tracked files)"
echo -e "  ${RED}✗${NC} uploads/ directory"
echo -e "  ${RED}✗${NC} Database backup files in home directory"
echo ""
echo -e "${GREEN}The following will be preserved:${NC}"
echo -e "  ${GREEN}✓${NC} local-config.yml (your configuration)"
echo -e "  ${GREEN}✓${NC} themes/ directory"
echo -e "  ${GREEN}✓${NC} .gitignore"
echo -e "  ${GREEN}✓${NC} .wpengine-local/ (submodule)"
echo -e "  ${GREEN}✓${NC} Any Git-tracked files"
echo ""

# Dry run - show what would be removed
echo -e "${BLUE}Dry run - files that would be removed:${NC}"
echo ""

if [[ -f "docker-compose.yml" ]]; then
    echo -e "  ${YELLOW}- docker-compose.yml${NC}"
fi

if [[ -d "docker" ]]; then
    echo -e "  ${YELLOW}- docker/${NC}"
fi

if [[ -d "plugins" ]]; then
    echo -e "  ${YELLOW}- plugins/ (except index.php and Git-tracked plugins)${NC}"
fi

if [[ -d "uploads" ]]; then
    echo -e "  ${YELLOW}- uploads/${NC}"
fi

if [[ -n "$PROJECT_NAME" ]]; then
    CONTAINER_COUNT=$(docker ps -a --format '{{.Names}}' | grep "^${PROJECT_NAME}-" | wc -l)
    if [[ $CONTAINER_COUNT -gt 0 ]]; then
        echo -e "  ${YELLOW}- Docker containers (${CONTAINER_COUNT}):${NC}"
        docker ps -a --format '  {{.Names}}' | grep "^${PROJECT_NAME}-" | sed 's/^/    /'
    fi

    VOLUME_COUNT=$(docker volume ls --format '{{.Name}}' | grep "^${PROJECT_NAME}-" | wc -l)
    if [[ $VOLUME_COUNT -gt 0 ]]; then
        echo -e "  ${YELLOW}- Docker volumes (${VOLUME_COUNT}):${NC}"
        docker volume ls --format '  {{.Name}}' | grep "^${PROJECT_NAME}-" | sed 's/^/    /'
    fi
fi

# Database backups in home directory
BACKUP_FILES=$(find "$HOME" -maxdepth 1 -name "*.sql" -o -name "*.sql.gz" 2>/dev/null | wc -l)
if [[ $BACKUP_FILES -gt 0 ]]; then
    echo -e "  ${YELLOW}- Database backup files in ~/ (${BACKUP_FILES})${NC}"
fi

echo ""
echo -e "${RED}═══════════════════════════════════════════════════════${NC}"
read -p "$(echo -e ${RED}Are you sure you want to proceed? [y/N]: ${NC})" -n 1 -r
echo
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${GREEN}Cleanup cancelled${NC}"
    exit 0
fi

echo -e "${BLUE}Starting cleanup...${NC}"
echo ""

# Step 1: Stop and remove Docker containers
if [[ -n "$PROJECT_NAME" ]]; then
    echo -e "${BLUE}Step 1: Stopping and removing Docker containers...${NC}"

    CONTAINERS=$(docker ps -a --format '{{.Names}}' | grep "^${PROJECT_NAME}-" || echo "")
    if [[ -n "$CONTAINERS" ]]; then
        while IFS= read -r container; do
            echo -e "  Stopping: ${container}"
            docker stop "$container" >/dev/null 2>&1 || true
            echo -e "  Removing: ${container}"
            docker rm "$container" >/dev/null 2>&1 || true
            echo -e "  ${GREEN}✓${NC} Removed: ${container}"
        done <<< "$CONTAINERS"
    else
        echo -e "  ${YELLOW}No containers found${NC}"
    fi

    echo ""

    # Step 2: Remove Docker volumes
    echo -e "${BLUE}Step 2: Removing Docker volumes...${NC}"

    VOLUMES=$(docker volume ls --format '{{.Name}}' | grep "^${PROJECT_NAME}-" || echo "")
    if [[ -n "$VOLUMES" ]]; then
        while IFS= read -r volume; do
            echo -e "  Removing: ${volume}"
            docker volume rm "$volume" >/dev/null 2>&1 || true
            echo -e "  ${GREEN}✓${NC} Removed: ${volume}"
        done <<< "$VOLUMES"
    else
        echo -e "  ${YELLOW}No volumes found${NC}"
    fi

    echo ""

    # Step 2b: Remove Docker networks
    echo -e "${BLUE}Step 2b: Removing Docker networks...${NC}"

    NETWORKS=$(docker network ls --format '{{.Name}}' | grep "${PROJECT_NAME}" || echo "")
    if [[ -n "$NETWORKS" ]]; then
        while IFS= read -r network; do
            echo -e "  Removing: ${network}"
            docker network rm "$network" >/dev/null 2>&1 || true
            echo -e "  ${GREEN}✓${NC} Removed: ${network}"
        done <<< "$NETWORKS"
    else
        echo -e "  ${YELLOW}No networks found${NC}"
    fi

    echo ""

    # Step 2c: Remove project Docker images
    echo -e "${BLUE}Step 2c: Removing project Docker images...${NC}"

    IMAGES=$(docker images --format '{{.Repository}}:{{.Tag}}' | grep "${PROJECT_NAME}" || echo "")
    if [[ -n "$IMAGES" ]]; then
        while IFS= read -r image; do
            echo -e "  Removing: ${image}"
            docker rmi -f "$image" >/dev/null 2>&1 || true
            echo -e "  ${GREEN}✓${NC} Removed: ${image}"
        done <<< "$IMAGES"
    else
        echo -e "  ${YELLOW}No project images found${NC}"
    fi

    echo ""

    # Step 2d: Remove dangling images
    echo -e "${BLUE}Step 2d: Removing dangling/orphaned images...${NC}"

    DANGLING=$(docker images -f "dangling=true" -q | wc -l)
    if [[ $DANGLING -gt 0 ]]; then
        docker image prune -f >/dev/null 2>&1
        echo -e "  ${GREEN}✓${NC} Removed $DANGLING dangling images"
    else
        echo -e "  ${YELLOW}No dangling images found${NC}"
    fi

    echo ""

    # Step 2e: Offer to clean build cache
    echo -e "${BLUE}Step 2e: Docker build cache cleanup${NC}"
    read -p "$(echo -e ${YELLOW}Clean Docker build cache? This will speed up future builds. [y/N]: ${NC})" -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "  Cleaning build cache..."
        docker builder prune -f >/dev/null 2>&1
        echo -e "  ${GREEN}✓${NC} Build cache cleaned"
    else
        echo -e "  ${YELLOW}Skipped build cache cleanup${NC}"
    fi

    echo ""
else
    echo -e "${YELLOW}Skipping Docker cleanup (project name not found)${NC}"
    echo ""
fi

# Step 3: Remove generated files
echo -e "${BLUE}Step 3: Removing generated files...${NC}"

if [[ -f "docker-compose.yml" ]]; then
    rm -f docker-compose.yml
    echo -e "  ${GREEN}✓${NC} Removed docker-compose.yml"
fi

if [[ -d "docker" ]]; then
    rm -rf docker/
    echo -e "  ${GREEN}✓${NC} Removed docker/"
fi

echo ""

# Step 4: Clean plugins directory
echo -e "${BLUE}Step 4: Cleaning plugins directory...${NC}"

if [[ -d "plugins" ]]; then
    # Fix ownership of Docker-created files using Docker itself
    if ! rm -rf plugins/* 2>/dev/null; then
        echo -e "  ${YELLOW}Fixing ownership of Docker-created files...${NC}"
        docker run --rm -v "${PROJECT_ROOT}/plugins:/cleanup" alpine chown -R $(id -u):$(id -g) /cleanup 2>/dev/null || true
    fi

    # Now remove everything
    rm -rf plugins/*

    # Recreate index.php
    if [[ ! -f "plugins/index.php" ]]; then
        echo "<?php" > plugins/index.php
        echo "// Silence is golden." >> plugins/index.php
    fi

    echo -e "  ${GREEN}✓${NC} Cleaned plugins/"
else
    echo -e "  ${YELLOW}plugins/ not found${NC}"
fi

echo ""

# Step 5: Remove uploads directory
echo -e "${BLUE}Step 5: Removing uploads directory...${NC}"

if [[ -d "uploads" ]]; then
    # Fix ownership of Docker-created files using Docker itself
    if ! rm -rf uploads/ 2>/dev/null; then
        echo -e "  ${YELLOW}Fixing ownership of Docker-created files...${NC}"
        docker run --rm -v "${PROJECT_ROOT}/uploads:/cleanup" alpine chown -R $(id -u):$(id -g) /cleanup 2>/dev/null || true
    fi

    # Now remove
    rm -rf uploads/

    if [[ ! -d "uploads" ]]; then
        echo -e "  ${GREEN}✓${NC} Removed uploads/"
    else
        echo -e "  ${RED}✗${NC} Failed to remove uploads/"
    fi
else
    echo -e "  ${YELLOW}uploads/ not found${NC}"
fi

echo ""

# Step 5b: Clean mu-plugins directory
echo -e "${BLUE}Step 5b: Cleaning mu-plugins directory...${NC}"

if [[ -d "mu-plugins" ]]; then
    # Fix ownership of Docker-created files using Docker itself
    if ! rm -rf mu-plugins/* 2>/dev/null; then
        echo -e "  ${YELLOW}Fixing ownership of Docker-created files...${NC}"
        docker run --rm -v "${PROJECT_ROOT}/mu-plugins:/cleanup" alpine chown -R $(id -u):$(id -g) /cleanup 2>/dev/null || true
    fi

    # Now remove everything
    rm -rf mu-plugins/*

    echo -e "  ${GREEN}✓${NC} Cleaned mu-plugins/"
else
    echo -e "  ${YELLOW}mu-plugins/ not found${NC}"
fi

echo ""

# Step 6: Clean database backups
echo -e "${BLUE}Step 6: Cleaning database backups...${NC}"

read -p "$(echo -e ${YELLOW}Remove database backup files from home directory? [y/N]: ${NC})" -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    REMOVED_COUNT=0
    while IFS= read -r backup_file; do
        if [[ -n "$backup_file" ]]; then
            rm -f "$backup_file"
            echo -e "  ${GREEN}✓${NC} Removed: $(basename "$backup_file")"
            ((REMOVED_COUNT++))
        fi
    done < <(find "$HOME" -maxdepth 1 \( -name "*.sql" -o -name "*.sql.gz" \) 2>/dev/null)

    if [[ $REMOVED_COUNT -gt 0 ]]; then
        echo -e "  ${GREEN}✓${NC} Removed ${REMOVED_COUNT} backup file(s)"
    else
        echo -e "  ${YELLOW}No backup files found${NC}"
    fi
else
    echo -e "  ${YELLOW}Skipped backup cleanup${NC}"
fi

echo ""

# Step 7: Clean temporary files
echo -e "${BLUE}Step 7: Cleaning temporary files...${NC}"

TEMP_CLEANED=0
while IFS= read -r temp_dir; do
    if [[ -n "$temp_dir" ]] && [[ -d "$temp_dir" ]]; then
        rm -rf "$temp_dir"
        echo -e "  ${GREEN}✓${NC} Removed: $(basename "$temp_dir")"
        ((TEMP_CLEANED++))
    fi
done < <(find /tmp -maxdepth 1 -type d -name "${PROJECT_NAME}-*" 2>/dev/null)

if [[ $TEMP_CLEANED -gt 0 ]]; then
    echo -e "  ${GREEN}✓${NC} Cleaned ${TEMP_CLEANED} temporary directories"
else
    echo -e "  ${YELLOW}No temporary files found${NC}"
fi

echo ""

# Final summary
echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}    Cleanup completed successfully!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${CYAN}Your project is now in a clean state.${NC}"
echo ""
echo -e "${BLUE}Preserved files:${NC}"
echo -e "  ${GREEN}✓${NC} local-config.yml"
echo -e "  ${GREEN}✓${NC} themes/"
echo -e "  ${GREEN}✓${NC} .gitignore"
echo -e "  ${GREEN}✓${NC} .wpengine-local/ (submodule)"
echo ""
echo -e "${CYAN}To set up again, run:${NC} ${GREEN}./setup.sh${NC}"
echo ""
