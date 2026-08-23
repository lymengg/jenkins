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

- URL: http://localhost:8080
- Login with admin credentials
- Check dashboard for any warnings or errors

## Common Tasks

### Install Additional Plugins

1. Edit `plugins.txt` to add new plugins
2. Rebuild the image: `docker compose build`
3. Restart Jenkins: `docker compose up -d`

### Update JCasC Configuration

1. Edit `casc/jenkins.yaml`
2. Restart Jenkins: `docker compose restart jenkins`
3. Verify configuration loaded correctly

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
docker stats jenkins-controller

# Disk usage
docker exec jenkins-controller df -h /var/jenkins_home

# Memory usage
docker exec jenkins-controller free -m
```

## Troubleshooting

### Jenkins Won't Start

1. Check logs: `docker compose logs jenkins`
2. Verify disk space: `df -h`
3. Check permissions on Jenkins home
4. Verify plugin compatibility

### Slow Performance

1. Check resource usage: `docker stats`
2. Review Jenkins logs for warnings
3. Consider increasing memory limits
4. Check disk I/O performance

### Configuration Issues

1. Verify JCasC syntax
2. Check environment variables
3. Review Jenkins system logs
4. Validate plugin configurations

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

1. Update `JENKINS_VERSION` in `.env`
2. Rebuild image: `docker compose build`
3. Test in non-production
4. Deploy to production

### Update Plugins

1. Update versions in `plugins.txt`
2. Rebuild image: `docker compose build`
3. Test plugin compatibility
4. Deploy to production

### Rotate Secrets

1. Update environment variables
2. Restart Jenkins: `docker compose restart jenkins`
3. Verify functionality

## Maintenance

### Regular Tasks

- Weekly: Review Jenkins logs
- Monthly: Check for updates
- Quarterly: Review security settings
- Annually: Disaster recovery test

### Disk Cleanup

```bash
# Clean old builds
docker exec jenkins-controller find /var/jenkins_home/jobs -name "lastStable" -exec rm -rf {} \;

# Clean workspace
docker exec jenkins-controller find /var/jenkins_home/workspace -type d -mtime +30 -exec rm -rf {} \;
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

build:
  script:
    - docker compose build

test:
  script:
    - ./scripts/health-check.sh

deploy:
  script:
    - ./scripts/backup.sh
    - docker compose up -d
    - ./scripts/health-check.sh
```

### Required Environment Variables

- `JENKINS_VERSION`: Jenkins LTS version
- `JENKINS_JAVA_OPTS`: Java options
- `JENKINS_PORT`: HTTP port
- `JENKINS_AGENT_PORT`: Agent port
