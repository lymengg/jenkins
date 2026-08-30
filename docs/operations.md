# Operations Guide

## Daily Operations

### Check Jenkins Status

```bash
# Check container status
docker compose ps

# Check Jenkins health
./scripts/health-check.sh

# View recent logs
docker compose logs --tail=50 jenkins
```

### Restart Jenkins

```bash
# Graceful restart
docker compose restart jenkins

# Full restart (stop and start)
docker compose down
docker compose up -d
```

### Access Jenkins UI

- URL: https://jenkins.ouklymeng.qzz.io/
- Login with admin credentials
- Check dashboard for any warnings or errors

## Common Tasks

### Install or Update Plugins

1. Go to **Manage Jenkins > Plugins**
2. Install new plugins from the **Available** tab
3. Update existing plugins from the **Updates** tab
4. Restart Jenkins if prompted
5. Create a backup: `./scripts/backup.sh`

### Configure Jenkins Settings

1. Go to **Manage Jenkins > System**
2. Configure as needed (URL, email, executors, etc.)
3. Save changes
4. Create a backup: `./scripts/backup.sh`

### View Jenkins Logs

```bash
# Real-time logs
docker compose logs -f jenkins

# Last 100 lines
docker compose logs --tail=100 jenkins

# Logs from specific time
docker compose logs --since="2024-01-01T00:00:00" jenkins
```

## Monitoring

### Health Checks

- Automated health checks via `./scripts/health-check.sh`
- Docker health check configured in compose file
- Monitor container resource usage

### Resource Monitoring

```bash
# Container resource usage
docker stats jenkins

# Disk usage
docker exec jenkins df -h /var/jenkins_home

# Memory usage
docker exec jenkins free -m
```

## Troubleshooting

### Jenkins Won't Start

1. Check logs: `docker compose logs jenkins`
2. Verify disk space: `df -h`
3. Check permissions on Jenkins home
4. Verify plugin compatibility (check logs for plugin load errors)

### Slow Performance

1. Check resource usage: `docker stats`
2. Review Jenkins logs for warnings
3. Consider increasing memory limits in `docker-compose.yml`
4. Check disk I/O performance

### Plugin Issues

1. Check **Manage Jenkins > Plugins > Installed** for warnings
2. Review Jenkins logs for plugin errors
3. Try updating the problematic plugin via UI
4. If a plugin prevents startup, disable it:
   ```bash
   docker exec jenkins mv /var/jenkins_home/plugins/<plugin-name>.jpi /var/jenkins_home/plugins/<plugin-name>.jpi.disabled
   docker compose restart jenkins
   ```

## Backup Operations

### Create Backup

```bash
./scripts/backup.sh
```

### List Backups

```bash
ls -lh backup/
```

### Clean Old Backups

```bash
find backup/ -name "jenkins-*.tar.gz" -mtime +30 -delete
```

## Security Operations

### Update Jenkins Version

1. Update `JENKINS_IMAGE_TAG` in `.env`
2. Test in non-production: `docker compose up -d`
3. Deploy to production: `docker compose up -d`
4. Check **Manage Jenkins > Plugins > Updates** for plugin updates

### Update Plugins

1. Go to **Manage Jenkins > Plugins > Updates**
2. Select plugins to update
3. Click "Download and apply after restart" or "Download now and install after restart"
4. Restart Jenkins if prompted
5. Create a backup: `./scripts/backup.sh`

### Rotate Secrets

1. Update credentials in **Manage Jenkins > Credentials**
2. Restart Jenkins if needed: `docker compose restart jenkins`
3. Verify functionality

## Maintenance

### Regular Tasks

- Weekly: Review Jenkins logs
- Monthly: Check for plugin and Jenkins updates via UI
- Quarterly: Review security settings
- Annually: Disaster recovery test

### Disk Cleanup

```bash
# Clean old builds
docker exec jenkins find /var/jenkins_home/jobs -name "lastStable" -exec rm -rf {} \;

# Clean workspace
docker exec jenkins find /var/jenkins_home/workspace -type d -mtime +30 -exec rm -rf {} \;
```

## CI/CD Integration

### Automated Deployment

The repository is structured for CI/CD deployment:

```yaml
# Example GitLab CI/CD pipeline
stages:
  - validate
  - build
  - test
  - deploy

validate:
  script:
    - docker compose config

test:
  script:
    - ./scripts/health-check.sh

deploy:
  script:
    - ./scripts/backup.sh
    - docker compose up -d
    - ./scripts/health-check.sh
```

### Environment Variables

See `.env.example` for the full list. Key variables:

- `JENKINS_IMAGE_TAG`: Full base image tag, e.g. `2.568.2-jdk21` (used in docker-compose.yml)
- `JENKINS_JAVA_OPTS`: JVM flags passed via JAVA_OPTS
- `JENKINS_AGENT_PORT`: Agent port (host mapping)
- `BACKUP_RETENTION_DAYS`: Backup retention period in days
