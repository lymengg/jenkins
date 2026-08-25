# Backup and Restore Guide

## Backup Strategy

### What is Backed Up

- Complete Jenkins home directory
- All job configurations
- Plugin configurations
- User data and credentials
- Build history
- System configuration

### What is NOT Backed Up

- Docker container itself
- Docker image
- Environment variables (stored in `.env`)
- Jenkins version and infrastructure config (stored in Git: `.env`, `docker-compose.yml`)

### Backup Location

- Local: `backup/` directory
- **Production**: Should be copied to external/object storage
- Examples: AWS S3, Google Cloud Storage, Azure Blob Storage, NFS

### Retention Policy

- Default retention: 30 days
- Configurable via `BACKUP_RETENTION_DAYS` in `.env`
- Old backups are automatically cleaned up

## Creating Backups

### Manual Backup

```bash
./scripts/backup.sh
```

### Authenticated Backup (Required After Setup Wizard)

After completing the Jenkins setup wizard, security is enabled and the
backup/restore scripts need credentials to call the Jenkins API (quietDown,
safeExit). Set these in `.env`:

```env
JENKINS_USER=admin
JENKINS_API_TOKEN=<your-api-token>
```

Create an API token in Jenkins: **User > Configure > API Token**.

Without auth, the script will skip quiet down mode and warn (backups still work,
but may capture inconsistent state if builds are running).

### Backup Process

1. Acquires a lock to prevent concurrent backups
2. Checks if Jenkins container is running
3. Puts Jenkins into quiet down mode (pauses new builds for consistency)
4. Creates tarball of Jenkins home directory
5. Verifies backup integrity (tar validation)
6. Resumes Jenkins (cancels quiet down)
7. Cleans up old backups based on retention policy

### Backup File Format

- Filename: `jenkins-YYYY-MM-DD-HHMMSS.tar.gz`
- Example: `jenkins-2024-01-01-120000.tar.gz`
- Format: Gzipped tar archive

### Verifying Backups

```bash
# List backups
ls -lh backup/

# Check backup contents
tar -tzf backup/jenkins-2024-01-01-120000.tar.gz | head -20

# Check backup size
du -h backup/jenkins-2024-01-01-120000.tar.gz
```

## Restoring Backups

### Restore Process

```bash
./scripts/restore.sh -f backup/jenkins-2024-01-01-120000.tar.gz
```

### Restore Options

- `-f <backup-file>`: Path to backup file (required)
- `-t <target>`: Target container name (default: jenkins)
- `-y`: Skip confirmation prompt (use with caution)

### Restore Safety Features

1. **Integrity Check**: Verifies backup file is a valid tar.gz before proceeding
2. **Confirmation Prompt**: Requires explicit confirmation
3. **Safety Backup**: Creates backup of current state before restore (aborts if this fails)
4. **Graceful Shutdown**: Stops Jenkins cleanly via HTTP API before restore
5. **Permission Fixing**: Ensures correct file ownership (UID 1000)
6. **Post-Restore Verification**: Waits for Jenkins to respond after restart

### Restore Process Steps

1. Verify backup file integrity (tar validation)
2. Check container is running
3. Resolve Docker volume name
4. Prompt for confirmation (unless `-y` used)
5. Create safety backup (aborts on failure)
6. Stop Jenkins gracefully via HTTP API
7. Restore backup to Jenkins home
8. Fix file permissions
9. Start Jenkins
10. Wait for Jenkins to respond

### Important Warnings

- **Restore is destructive**: Overwrites current Jenkins home
- **No undo**: Cannot easily revert a restore
- **Data loss**: Any changes since last backup will be lost
- **Plugin compatibility**: Ensure backup is from compatible Jenkins version

## Restore Testing

### Test Backup Integrity

```bash
# Interactive mode (keeps test instance running for 5 minutes for manual verification)
./scripts/restore-test.sh -f backup/jenkins-2024-01-01-120000.tar.gz

# CI/automation mode (cleans up immediately after verification)
./scripts/restore-test.sh -f backup/jenkins-2024-01-01-120000.tar.gz --no-wait
```

### What Restore Test Does

1. Verifies backup file integrity (tar validation)
2. Checks test ports are available
3. Creates isolated test environment with unique volume/container names
4. Restores backup to test volume
5. Starts Jenkins test instance
6. Waits for Jenkins to respond
7. Performs health checks (HTTP, config, plugins, jobs, API)
8. Cleans up test environment

### Restore Test Verification

- Jenkins starts successfully
- Jenkins home is readable
- Configuration is present
- Plugins load correctly
- HTTP health check passes
- API is accessible

### Restore Test Limitations

- Does not test all Jenkins functionality
- Does not verify job execution
- Does not test plugin interactions
- Limited to basic health checks

## Disaster Recovery

### Recovery Procedure

1. **Provision New Server**
   - Install Docker and Docker Compose
   - Ensure sufficient disk space
   - Configure network access

2. **Clone Repository**
   ```bash
   git clone <repository-url>
   cd jenkins
   ```

3. **Configure Environment**
   ```bash
   cp .env.example .env
   # Edit .env with production settings
   ```

4. **Restore Backup**
   ```bash
   ./scripts/restore.sh -f /path/to/backup/jenkins-2024-01-01-120000.tar.gz
   ```

5. **Start Jenkins**
   ```bash
   docker compose up -d
   ```

6. **Verify Functionality**
   ```bash
   ./scripts/health-check.sh
   ```

### Recovery Time Objectives

- **RTO (Recovery Time Objective)**: < 1 hour
- **RPO (Recovery Point Objective)**: Based on backup frequency

### Backup Storage Requirements

- **Production**: External object storage (S3, GCS, Azure Blob)
- **Retention**: Minimum 30 days
- **Encryption**: Recommended for sensitive data
- **Access Control**: Restrict backup access

## Best Practices

### Backup Best Practices

1. **Regular Backups**: Schedule daily backups
2. **External Storage**: Never rely on local storage alone
3. **Test Restores**: Regularly verify backup integrity
4. **Monitor Backups**: Ensure backups complete successfully
5. **Document Procedures**: Keep recovery steps updated

### Restore Best Practices

1. **Test First**: Always test restore in non-production
2. **Create Safety Backup**: Always backup current state before restore
3. **Verify Version**: Ensure backup is from compatible Jenkins version
4. **Check Plugins**: Verify plugin compatibility after restore
5. **Monitor Logs**: Watch for errors after restore

### Security Considerations

1. **Encrypt Backups**: Use encryption for sensitive data
2. **Access Control**: Restrict who can create/restore backups
3. **Audit Trail**: Log all backup/restore operations
4. **Secure Storage**: Use secure storage for backups
5. **Regular Rotation**: Rotate backup encryption keys

## Troubleshooting

### Backup Fails

- Check disk space
- Verify container is running
- Check container logs
- Ensure proper permissions

### Restore Fails

- Verify backup file integrity
- Check Jenkins version compatibility
- Ensure sufficient disk space
- Check container logs

### Jenkins Won't Start After Restore

- Check Jenkins logs
- Verify plugin compatibility
- Check file permissions
- Verify configuration files

### Data Corruption

- Restore from known good backup
- Verify backup integrity
- Check for disk issues
- Contact support if persistent
