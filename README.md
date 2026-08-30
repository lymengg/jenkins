# Jenkins Infrastructure

Production-oriented Jenkins deployment using Docker Compose.

## Architecture

```
Internet
    ↓ (ports 80/443)
Caddy Reverse Proxy (automatic HTTPS via Let's Encrypt)
    ↓ (Docker network)
Jenkins Controller (official jenkins/jenkins image, port 8080 internal)
    ↓
Persistent Jenkins Volume (plugins, config, jobs, credentials)
```

### What is tracked in Git

- **Jenkins version** — pinned via `JENKINS_IMAGE_TAG` in `.env`, used as the image tag in `docker-compose.yml`
- **Infrastructure** — `docker-compose.yml` (ports, resource limits, health checks, volumes)
- **Operational scripts** — backup, restore, health check
- **Documentation** — architecture, operations, upgrade, backup/restore guides

### What is managed via UI (persisted in Docker volume)

- **Plugins** — installed and updated via Jenkins UI; Jenkins prompts you when updates are available
- **Jenkins configuration** — security realm, authorization, credentials, jobs
- **Build history and workspaces**

This approach avoids stale/deprecated plugin versions from a pinned `plugins.txt`. Plugin state is captured by `backup.sh` and restored by `restore.sh`.

## Initial Installation

1. Clone the repository:
   ```bash
   git clone <repository-url>
   cd jenkins
   ```

2. Create environment file:
   ```bash
   cp .env.example .env
   # Edit .env with your configuration
   ```

3. Start Jenkins:
   ```bash
   docker compose up -d
   ```

4. Complete the Jenkins setup wizard:
    - URL: https://jenkins.ouklymeng.qzz.io/
    - Get the initial admin password: `docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword`
    - Choose "Select plugins to install" or "Install suggested plugins"
    - Create your admin user

5. Install additional plugins as needed via **Manage Jenkins > Plugins**

## Daily Operations

### Check Status
```bash
docker compose ps
docker compose logs jenkins
./scripts/health-check.sh
```

### Restart Jenkins
```bash
docker compose restart jenkins
```

### View Logs
```bash
docker compose logs -f jenkins
```

## Docker Hub Credentials

For Jenkinsfiles that push Docker images, you need a `dockerhub` credential in Jenkins. Create it with:

```bash
./scripts/setup-dockerhub-credential.sh
```

This prompts for your Docker Hub username and access token, then creates/updates the `dockerhub` credential via the Jenkins Script Console.

Prerequisites:
- Jenkins running (`docker compose up -d`)
- `JENKINS_USER` and `JENKINS_API_TOKEN` set in `.env` (see [Initial Installation](#initial-installation))

## Agents

Build agents are separate hosts that execute Jenkins jobs. The recommended launch method is **SSH** (controller connects to the agent on port 22, key-based auth, no inbound port on the controller).

### Prepare an agent host

Run the setup script on the Linux agent host (as root/sudo). It creates a dedicated `jenkins` user, installs Java 21, sets up `~jenkins/.ssh` with correct permissions, and prints the remaining steps (key generation, Jenkins UI node registration):

```bash
sudo ./scripts/setup-agent.sh
```

### Full setup guide

See [docs/agents.md](docs/agents.md) for the complete guide covering:
- SSH launch method (recommended)
- WebSocket fallback (for agents behind NAT)
- JNLP/TCP legacy method (discouraged, opt-in)
- Security hardening checklist
- Troubleshooting

## Backup

### Create Backup
```bash
./scripts/backup.sh
```

Backups are stored in the `backup/` directory with timestamped filenames. The script puts Jenkins into quiet-down mode before backing up for a more consistent snapshot, then resumes Jenkins.

### What Backups Include

- All plugins (including versions and configurations)
- All job configurations and build history
- All credentials
- Jenkins system configuration
- User accounts

### Backup Strategy

- Timestamped backups for easy identification
- Automatic cleanup of old backups based on retention policy (`BACKUP_RETENTION_DAYS`)
- **Important**: Copy backups to external/object storage for production use

## Restore

### Restore from Backup
```bash
./scripts/restore.sh -f backup/jenkins-2024-01-01-120000.tar.gz
```

### Restore Options
- `-f <backup-file>`: Path to backup file (required)
- `-t <target>`: Target container name (default: jenkins)
- `-y`: Skip confirmation prompt (use with caution)

**WARNING**: Restore is a destructive operation that overwrites the current Jenkins home.

## Restore Testing

### Test a Backup
```bash
./scripts/restore-test.sh -f backup/jenkins-2024-01-01-120000.tar.gz
```

This creates an isolated test environment to verify backup integrity without affecting production.

## Upgrade

See [docs/upgrade.md](docs/upgrade.md) for detailed upgrade procedures.

### Quick Upgrade Steps

1. Review Jenkins release notes and security advisories
2. Update `JENKINS_IMAGE_TAG` in `.env` (e.g. `2.568.2-jdk21` → `2.578.1-jdk21`)
3. Test in non-production environment
4. Create backup: `./scripts/backup.sh`
5. Deploy: `docker compose up -d`
6. Verify: `./scripts/health-check.sh`
7. After Jenkins starts, check **Manage Jenkins > Plugins** for any plugin updates needed

### Plugin Updates After Upgrade

Since plugins are UI-managed, after a Jenkins upgrade:
1. Go to **Manage Jenkins > Plugins > Updates**
2. Install available plugin updates
3. Restart Jenkins if prompted
4. Create a new backup: `./scripts/backup.sh`

## CI Validation

The repository includes a GitHub Actions CI workflow (`.github/workflows/ci.yml`) that runs on every push and pull request to `main`. It validates:
- docker-compose configuration
- Jenkins image pulls and starts successfully
- Jenkins responds to health checks

## Disaster Recovery

1. Provision new server with Docker
2. Clone repository
3. Copy `.env.example` to `.env` and configure
4. Copy backup to new server
5. Start Jenkins: `docker compose up -d`
6. Restore backup: `./scripts/restore.sh -f <backup-file>`
7. Verify: `./scripts/health-check.sh`

## Security Considerations

- No Docker socket mounted (use dedicated build agents instead)
- Resource limits enforced via Docker Compose (`deploy.resources`)
- Caddy reverse proxy provides automatic HTTPS via Let's Encrypt
- Jenkins port 8080 is not exposed to the host — only accessible via Caddy on the Docker network
- Regular security updates for Jenkins and plugins (check UI for updates)
- Backup encryption recommended for sensitive data
- Restricted access to backup files

## EC2 Security Group Requirements

| Port | Protocol | Source | Purpose |
|------|----------|--------|---------|
| 22 | TCP | Your IP | SSH access for administration |
| 80 | TCP | 0.0.0.0/0 | HTTP (Caddy auto-redirects to HTTPS) |
| 443 | TCP | 0.0.0.0/0 | HTTPS (Caddy reverse proxy to Jenkins) |

## Deployment

### First-time setup

```bash
git clone <repository-url>
cd jenkins
cp .env.example .env   # Edit with your configuration
docker compose up -d
```

### Verify the stack

```bash
# Check containers are running
docker compose ps

# Check Caddy logs for certificate acquisition
docker compose logs caddy

# Verify HTTPS is working
curl -I https://jenkins.ouklymeng.qzz.io/

# Check Jenkins health
./scripts/health-check.sh
```

### DNS configuration

Ensure your DNS provider has:

| Type | Name | Value |
|------|------|-------|
| A | jenkins | `<EC2 Elastic IP>` |

## Documentation

- [Architecture](docs/architecture.md)
- [Agents](docs/agents.md)
- [Operations](docs/operations.md)
- [Backup and Restore](docs/backup-and-restore.md)
- [Upgrade Guide](docs/upgrade.md)

## License

MIT
