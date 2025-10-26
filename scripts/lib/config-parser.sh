#!/bin/bash
# YAML Configuration Parser
# Parses local-config.yml and extracts values

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse YAML file and extract value
# Usage: get_config_value "wpengine.environment" "default_value"
get_config_value() {
    local key="$1"
    local default="$2"
    local config_file="${CONFIG_FILE:-local-config.yml}"

    if [[ ! -f "$config_file" ]]; then
        echo "$default"
        return
    fi

    # Convert dot notation to YAML path (e.g., "wpengine.environment" -> "wpengine:" then "  environment:")
    IFS='.' read -ra PARTS <<< "$key"
    local pattern=""
    local indent=0

    for part in "${PARTS[@]}"; do
        if [[ -z "$pattern" ]]; then
            pattern="^${part}:"
        else
            pattern="${pattern}.*\n[[:space:]]{${indent}}${part}:"
            ((indent+=2))
        fi
    done

    # Simple YAML parser for flat key-value pairs
    # This is a simplified version - for production, consider using yq or python
    local section=""
    local value=""

    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue

        # Check if this is a section header (no indentation, ends with :)
        if [[ "$line" =~ ^([a-z_]+):[[:space:]]*$ ]]; then
            section="${BASH_REMATCH[1]}"
            continue
        fi

        # Check if this is a subsection (2 spaces indentation)
        if [[ "$line" =~ ^[[:space:]]{2}([a-z_]+):[[:space:]]*(.*)$ ]]; then
            subsection="${BASH_REMATCH[1]}"
            subvalue="${BASH_REMATCH[2]}"

            # If we're looking for section.subsection
            if [[ "$key" == "${section}.${subsection}" ]]; then
                value="$subvalue"
                break
            fi
            continue
        fi

        # Check if this is a value in a subsection (4 spaces indentation)
        if [[ "$line" =~ ^[[:space:]]{4}([a-z_]+):[[:space:]]*(.*)$ ]]; then
            subkey="${BASH_REMATCH[1]}"
            subvalue="${BASH_REMATCH[2]}"

            # If we're looking for section.subsection.key
            if [[ "$key" == "${section}.${subsection}.${subkey}" ]]; then
                value="$subvalue"
                break
            fi
            continue
        fi
    done < "$config_file"

    # Return value or default
    if [[ -n "$value" ]]; then
        echo "$value"
    else
        echo "$default"
    fi
}

# Check if required config values exist
# Usage: require_config "wpengine.environment" "wpengine.ssh_user"
require_config() {
    local missing=()

    for key in "$@"; do
        local value=$(get_config_value "$key" "")
        if [[ -z "$value" ]]; then
            missing+=("$key")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo -e "${RED}Error: Missing required configuration values:${NC}"
        for key in "${missing[@]}"; do
            echo -e "  ${RED}✗${NC} $key"
        done
        return 1
    fi

    return 0
}

# Load all configuration into environment variables
# This makes it easier to use in docker-compose and other scripts
load_config() {
    local config_file="${1:-local-config.yml}"

    if [[ ! -f "$config_file" ]]; then
        echo -e "${RED}Error: Configuration file not found: $config_file${NC}"
        return 1
    fi

    export CONFIG_FILE="$config_file"

    # Client information
    export CLIENT_ID=$(get_config_value "client.id" "")
    export CLIENT_NAME=$(get_config_value "client.name" "")
    export PROJECT_NAME=$(get_config_value "client.project_name" "")

    # WP Engine configuration
    export WPENGINE_ENV=$(get_config_value "wpengine.environment" "")
    export WPENGINE_SSH_USER=$(get_config_value "wpengine.ssh_user" "")
    export WPENGINE_SSH_HOST=$(get_config_value "wpengine.ssh_host" "")
    export WPENGINE_SSH_KEY=$(get_config_value "wpengine.ssh_key" "~/.ssh/wpengine_deploy")
    export WPENGINE_SITE_PATH=$(get_config_value "wpengine.site_path" "sites/${WPENGINE_ENV}")

    # Expand tilde in SSH key path
    WPENGINE_SSH_KEY="${WPENGINE_SSH_KEY/#\~/$HOME}"
    export WPENGINE_SSH_KEY

    # Local ports
    export WORDPRESS_PORT=$(get_config_value "local.ports.wordpress" "8000")
    export PHPMYADMIN_PORT=$(get_config_value "local.ports.phpmyadmin" "8001")
    export MYSQL_PORT=$(get_config_value "local.ports.mysql" "3306")
    export SITE_URL=$(get_config_value "local.site_url" "http://localhost:${WORDPRESS_PORT}")
    export WP_DEBUG=$(get_config_value "local.wp_debug" "true")

    # Database configuration
    export DB_NAME=$(get_config_value "database.name" "wordpress_db")
    export DB_USER=$(get_config_value "database.user" "wordpress_user")
    export DB_PASSWORD=$(get_config_value "database.password" "wordpress_pass")
    export DB_ROOT_PASSWORD=$(get_config_value "database.root_password" "root_pass")

    # Sync options
    export SYNC_DATABASE=$(get_config_value "sync.database" "true")
    export SYNC_PLUGINS=$(get_config_value "sync.plugins" "true")
    export SYNC_UPLOADS=$(get_config_value "sync.uploads" "false")
    export SYNC_URL_REPLACEMENT=$(get_config_value "sync.url_replacement" "true")

    # PHP configuration
    export PHP_MEMORY_LIMIT=$(get_config_value "php.memory_limit" "256M")
    export PHP_UPLOAD_MAX_FILESIZE=$(get_config_value "php.upload_max_filesize" "64M")
    export PHP_POST_MAX_SIZE=$(get_config_value "php.post_max_size" "64M")
    export PHP_MAX_EXECUTION_TIME=$(get_config_value "php.max_execution_time" "300")

    # Docker configuration
    export RESTART_POLICY=$(get_config_value "docker.restart_policy" "unless-stopped")
    export MYSQL_VERSION=$(get_config_value "docker.mysql_version" "8.0")
    export WORDPRESS_VERSION=$(get_config_value "docker.wordpress_version" "latest")
    export PHPMYADMIN_VERSION=$(get_config_value "docker.phpmyadmin_version" "latest")

    # Set paths
    export PROJECT_ROOT="$(pwd)"
    export DOCKER_PATH="${PROJECT_ROOT}/docker"

    return 0
}

# Validate configuration
validate_config() {
    echo -e "${BLUE}Validating configuration...${NC}"

    # Check required fields
    if ! require_config \
        "client.project_name" \
        "wpengine.environment" \
        "wpengine.ssh_user" \
        "wpengine.ssh_host"; then
        return 1
    fi

    # Check SSH key exists
    if [[ ! -f "$WPENGINE_SSH_KEY" ]]; then
        echo -e "${RED}Error: SSH key not found: $WPENGINE_SSH_KEY${NC}"
        echo -e "${YELLOW}Please generate an SSH key and add it to WP Engine${NC}"
        return 1
    fi

    # Check ports are not in use
    local ports_to_check=("$WORDPRESS_PORT" "$PHPMYADMIN_PORT" "$MYSQL_PORT")
    local ports_in_use=()

    for port in "${ports_to_check[@]}"; do
        if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1 || netstat -tuln 2>/dev/null | grep -q ":$port "; then
            ports_in_use+=("$port")
        fi
    done

    if [[ ${#ports_in_use[@]} -gt 0 ]]; then
        echo -e "${YELLOW}Warning: The following ports are already in use:${NC}"
        for port in "${ports_in_use[@]}"; do
            echo -e "  ${YELLOW}⚠${NC} Port $port"
        done
        echo -e "${YELLOW}Please update local-config.yml with different ports or stop the conflicting services${NC}"
        return 1
    fi

    echo -e "${GREEN}✓ Configuration valid${NC}"
    return 0
}

# Display current configuration
show_config() {
    echo -e "${BLUE}Current Configuration:${NC}"
    echo -e "${BLUE}═══════════════════════════════════════${NC}"
    echo -e "  ${GREEN}Project:${NC} $PROJECT_NAME"
    echo -e "  ${GREEN}Client:${NC} $CLIENT_NAME ($CLIENT_ID)"
    echo -e ""
    echo -e "  ${GREEN}WP Engine Environment:${NC} $WPENGINE_ENV"
    echo -e "  ${GREEN}SSH:${NC} $WPENGINE_SSH_USER@$WPENGINE_SSH_HOST"
    echo -e ""
    echo -e "  ${GREEN}WordPress:${NC} http://localhost:$WORDPRESS_PORT"
    echo -e "  ${GREEN}phpMyAdmin:${NC} http://localhost:$PHPMYADMIN_PORT"
    echo -e "  ${GREEN}MySQL:${NC} localhost:$MYSQL_PORT"
    echo -e ""
    echo -e "  ${GREEN}Database:${NC} $DB_NAME"
    echo -e "  ${GREEN}DB User:${NC} $DB_USER"
    echo -e "${BLUE}═══════════════════════════════════════${NC}"
}
