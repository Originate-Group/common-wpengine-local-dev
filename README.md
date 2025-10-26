# WP Engine Local Development Environment

A reusable, scalable Docker-based local development environment for WP Engine WordPress sites. Designed to work with 1 site or 1,000+ sites.

## Features

- **Reusable**: Single common repository used across all WP Engine projects
- **Scalable**: Dynamic port allocation supports multiple concurrent environments
- **Automated**: One-command setup syncs database, plugins, and uploads from WP Engine
- **Modular**: Separate scripts for database, plugin, and upload synchronization
- **API-Ready**: Architecture supports future API-driven configuration for thousands of clients
- **Cross-Platform**: Works on Linux, macOS, Windows (WSL2), and Raspberry Pi

## Architecture

```
your-wpengine-project/
├── .wpengine-local/              # Git submodule (this repo)
│   ├── setup.sh                  # Main setup script
│   ├── unsetup.sh                # Cleanup script
│   ├── scripts/
│   │   ├── sync-database.sh      # Database sync
│   │   ├── sync-plugins.sh       # Plugins sync
│   │   ├── sync-uploads.sh       # Uploads sync
│   │   └── lib/
│   │       └── config-parser.sh  # Configuration utilities
│   └── templates/
│       ├── docker-compose.yml.template
│       ├── local-config.yml.example
│       └── ...
├── local-config.yml              # Your project config (~100 lines)
├── docker-compose.yml            # Generated from template
├── docker/                       # Generated Docker configs
├── plugins/                      # Synced from WP Engine
├── themes/                       # Your custom themes (Git tracked)
├── mu-plugins/                   # Synced from WP Engine
└── uploads/                      # Synced from WP Engine (optional)
```

## Quick Start

### 1. Add to Your Project

```bash
cd your-wpengine-project
git submodule add https://github.com/Originate-Group/common-wpengine-local-dev.git .wpengine-local
```

### 2. Configure

```bash
cp .wpengine-local/templates/local-config.yml.example local-config.yml
```

Edit `local-config.yml` with your WP Engine details:

```yaml
client:
  project_name: myclient

wpengine:
  environment: myclientdev
  ssh_user: myclientdev
  ssh_host: myclientdev.ssh.wpengine.net
  ssh_key: ~/.ssh/wpengine_deploy

local:
  ports:
    wordpress: 8000
    phpmyadmin: 8001
    mysql: 3306
```

### 3. Setup

```bash
./.wpengine-local/setup.sh
```

That's it! Your local environment is now running.

### 4. Access

- **WordPress**: http://localhost:8000
- **phpMyAdmin**: http://localhost:8001
- **WP Admin**: http://localhost:8000/wp-admin

## Prerequisites

- **Docker** (20.10+) and Docker Compose (2.0+)
- **SSH** access to WP Engine
- **rsync** (for syncing plugins/uploads)
- **Git** (for managing the submodule)

### Installation

**macOS**:
```bash
brew install --cask docker
brew install rsync
```

**Linux (Ubuntu/Debian)**:
```bash
sudo apt update
sudo apt install docker.io docker-compose rsync
sudo usermod -aG docker $USER  # Log out and back in
```

**Windows**:
- Install Docker Desktop for Windows
- Enable WSL2 integration
- Use WSL2 terminal for all commands

## Configuration

The `local-config.yml` file controls your local environment. See [templates/local-config.yml.example](templates/local-config.yml.example) for all available options.

### Key Configuration Sections

#### Client Information
```yaml
client:
  id: my-client-unique-id
  name: "My Client Name"
  project_name: myclient  # Used for Docker container names
```

#### WP Engine Connection
```yaml
wpengine:
  environment: myclientdev
  ssh_user: myclientdev
  ssh_host: myclientdev.ssh.wpengine.net
  ssh_key: ~/.ssh/wpengine_deploy
```

#### Port Configuration
```yaml
local:
  ports:
    wordpress: 8000      # Change if port is in use
    phpmyadmin: 8001
    mysql: 3306
```

**Important**: Each project running simultaneously must use unique ports!

#### Sync Options
```yaml
sync:
  database: true    # Sync database from WP Engine
  plugins: true     # Sync plugins from WP Engine
  uploads: false    # Sync media files (can be LARGE!)
```

## Usage

### Daily Workflow

```bash
# Start containers
docker compose up -d

# Make changes to themes/plugins
# (changes are live-mounted, no sync needed)

# Stop containers
docker compose down
```

### Syncing Data

```bash
# Sync database (updates local DB from WP Engine)
./.wpengine-local/scripts/sync-database.sh

# Sync plugins (downloads latest plugins)
./.wpengine-local/scripts/sync-plugins.sh

# Sync uploads (downloads media files - can be large!)
./.wpengine-local/scripts/sync-uploads.sh
```

### WP-CLI Commands

```bash
# Run WP-CLI commands
docker compose run --rm wpcli wp plugin list
docker compose run --rm wpcli wp user list
docker compose run --rm wpcli wp cache flush
```

### Useful Docker Commands

```bash
# View logs
docker compose logs -f

# View specific service logs
docker compose logs -f wordpress

# Restart a service
docker compose restart wordpress

# Execute commands in container
docker compose exec wordpress bash
```

### Cleanup

```bash
# Complete cleanup (removes containers, volumes, generated files)
./.wpengine-local/unsetup.sh
```

## Multiple Projects

Running multiple WP Engine projects simultaneously? No problem!

### Port Strategy

Each project needs unique ports. Use this pattern:

| Project | WordPress | phpMyAdmin | MySQL |
|---------|-----------|------------|-------|
| Client 1 | 8000 | 8001 | 3306 |
| Client 2 | 8010 | 8011 | 3316 |
| Client 3 | 8020 | 8021 | 3326 |
| Client 4 | 8030 | 8031 | 3336 |

Configure in each project's `local-config.yml`:

```yaml
local:
  ports:
    wordpress: 8010  # Different for each project
    phpmyadmin: 8011
    mysql: 3316
```

### Project Names

Ensure each project has a unique `project_name`:

```yaml
client:
  project_name: client1  # Must be unique!
```

This creates uniquely named containers:
- `client1-wordpress`
- `client1-mysql`
- `client2-wordpress`
- `client2-mysql`

## Scalability Features

This architecture is designed to scale from 1 to 1,000+ clients:

### Current Mode: Standalone

- Configuration in `local-config.yml` file
- Manual setup per project
- Works great for 1-50 projects

### Future Mode: API-Driven

The architecture supports future API-driven configuration:

```yaml
mode: api  # Switch to API mode

platform:
  api_url: https://devops.originate.com/api
  api_key: your-api-key
  client_id: auto-fetched-from-api
```

In API mode:
- Central database stores all client configurations
- Dynamic port allocation prevents conflicts
- One-click provisioning via web UI
- Automated client onboarding

## File Structure

```
common-wpengine-local-dev/
├── README.md                          # This file
├── LICENSE                            # MIT License
├── setup.sh                           # Main setup script
├── unsetup.sh                         # Cleanup script
├── scripts/
│   ├── sync-database.sh               # Database sync
│   ├── sync-plugins.sh                # Plugins sync
│   ├── sync-uploads.sh                # Uploads sync
│   └── lib/
│       └── config-parser.sh           # Config utilities
├── templates/
│   ├── local-config.yml.example       # Config template
│   ├── docker-compose.yml.template    # Docker Compose template
│   ├── php.ini.template               # PHP config template
│   ├── .dockerignore.template         # Docker ignore template
│   └── .gitignore.template            # Git ignore template
└── .github/
    └── workflows/
        └── ...                        # CI/CD workflows
```

## Troubleshooting

### Port Already in Use

**Error**: `Bind for 0.0.0.0:8000 failed: port is already allocated`

**Solution**: Change ports in `local-config.yml`:

```yaml
local:
  ports:
    wordpress: 8010  # Use a different port
```

### MySQL Won't Start

**Error**: Container exits immediately

**Solution**:
```bash
# Remove volumes and start fresh
docker compose down -v
./.wpengine-local/setup.sh
```

### SSH Connection Failed

**Error**: `Permission denied (publickey)`

**Solution**:
1. Verify SSH key exists: `ls -la ~/.ssh/wpengine_deploy`
2. Test connection: `ssh -i ~/.ssh/wpengine_deploy user@host.ssh.wpengine.net`
3. Add key to WP Engine: [WP Engine SSH Keys Guide](https://wpengine.com/support/ssh-gateway/)

### rsync Failed

**Error**: `rsync: command not found`

**Solution**:
```bash
# macOS
brew install rsync

# Linux
sudo apt install rsync

# Windows (WSL2)
sudo apt install rsync
```

### WordPress Shows Database Connection Error

**Solution**:
```bash
# Wait for MySQL to be ready
docker compose logs mysql

# If needed, restart WordPress container
docker compose restart wordpress
```

### Permission Issues (Linux)

**Error**: Files owned by root, can't edit

**Solution**:
```bash
# Fix permissions
sudo chown -R $USER:$USER themes/ plugins/

# Or run Docker without sudo
sudo usermod -aG docker $USER  # Log out and back in
```

## Best Practices

### Development Workflow

1. **Never edit plugins downloaded from WP Engine** (they'll be overwritten on next sync)
2. **Custom plugins**: Add to `.gitignore` exceptions:
   ```
   # .gitignore
   plugins/*
   !plugins/index.php
   !plugins/my-custom-plugin/  # Track this
   ```
3. **Themes**: Keep in Git, develop locally, deploy via Git
4. **Database changes**: Make in WP admin, export with WP-CLI if needed
5. **Uploads**: Don't commit to Git (sync from WP Engine as needed)

### Performance Tips

1. **uploads/**: Only sync if you need media files (can be GBs)
2. **Docker**: Use native Docker on Linux for best performance
3. **WSL2**: Store project files in WSL filesystem, not Windows drives
4. **macOS**: Consider increasing Docker Desktop resources

### Security

1. **SSH Keys**: Never commit private keys to Git
2. **Database Passwords**: Use strong passwords in `local-config.yml`
3. **local-config.yml**: Add to `.gitignore` if it contains secrets
4. **WP-CLI**: Always use `--allow-root` with caution

## Contributing

Improvements welcome! This is a shared resource for the Originate Group organization.

### Development

```bash
git clone https://github.com/Originate-Group/common-wpengine-local-dev.git
cd common-wpengine-local-dev

# Test changes
./setup.sh
```

### Updating Projects

When you update this common repo, all projects using it as a submodule can update:

```bash
cd your-project
git submodule update --remote .wpengine-local
git add .wpengine-local
git commit -m "Update common-wpengine-local-dev"
```

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Support

- **Issues**: [GitHub Issues](https://github.com/Originate-Group/common-wpengine-local-dev/issues)
- **Docs**: [WP Engine Documentation](https://wpengine.com/support/)
- **Internal**: Contact DevOps team

---

**Built with ❤️ by Originate Group**
