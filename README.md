# Jenkins Infrastructure

Production-oriented Jenkins deployment using Docker Compose with Configuration as Code (JCasC).

## Architecture

```
Git Repository
    ↓
Dockerfile + Compose + JCasC + plugins
    ↓
Jenkins Controller
    ↓
Persistent Jenkins Volume
```

### Components

- **Dockerfile**: Custom Jenkins LTS image with pinned version and essential plugins
- **docker-compose.yml**: Production-oriented container orchestration
- **casc/jenkins.yaml**: Jenkins Configuration as Code
- **plugins.txt**: Minimal set of required plugins
- **scripts/**: Operational scripts for backup, restore, and health checks

## Initial Installation

1. Clone the repository:
   ```bash
   git clone <repository-url>
   cd jenkins-infrastructure
   ```

2. Create environment file:
   ```bash
   cp .env.example .env
   # Edit .env with your configuration
   ```

3. Build and start Jenkins:
   ```bash
   docker compose build
   docker compose up -d
   ```

4. Access Jenkins:
   - URL: http://localhost:8080
   - Default admin password: Check container logs or use configured password

## Initial Jenkins Setup

After first deployment:

1. Complete the initial setup wizard
2. Configure admin credentials
3. Set up SCM credentials for pipelines
4. Configure any additional settings in `casc/jenkins.yaml`

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

## Backup

### Create Backup
```bash
./scripts/backup.sh
```

Backups are stored in the `backup/` directory with timestamped filenames.

### Backup Strategy

- Backups include the entire Jenkins home directory
- Timestamped backups for easy identification
- Automatic cleanup of old backups based on retention policy
- **Important**: Copy backups to external/object storage for production use

## Restore

### Restore from Backup
```bash
./scripts/restore.sh -f backup/jenkins-2024-01-01-120000.tar.gz
```

### Restore Options
- `-f <backup-file>`: Path to backup file (required)
- `-t <target>`: Target container name (default: jenkins-controller)
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

1. Review Jenkins release notes
2. Update `JENKINS_VERSION` in `.env`
3. Update plugins in `plugins.txt` if needed
4. Build new image: `docker compose build`
5. Test in non-production environment
6. Create backup: `./scripts/backup.sh`
7. Deploy: `docker compose up -d`
8. Verify: `./scripts/health-check.sh`

## Disaster Recovery

1. Provision new server with Docker
2. Clone repository
3. Copy backup to new server
4. Follow installation steps
5. Restore backup: `./scripts/restore.sh -f <backup-file>`
6. Verify functionality

## Security Considerations

- No Docker socket mounted (use dedicated build agents instead)
- Secrets stored in environment variables, not in Git
- Reverse proxy recommended for production (not included)
- Regular security updates for Jenkins and plugins
- Backup encryption recommended for sensitive data
- Restricted access to backup files

## Documentation

- [Architecture](docs/architecture.md)
- [Operations](docs/operations.md)
- [Backup and Restore](docs/backup-and-restore.md)
- [Upgrade Guide](docs/upgrade.md)

## License

[Add your license here]
