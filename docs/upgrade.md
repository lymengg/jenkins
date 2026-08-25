# Upgrade Guide

## Overview

This guide covers upgrading Jenkins to a new version. Upgrades should be treated as potentially stateful operations that require careful planning and testing.

Since plugins are UI-managed (not pinned in Git), upgrading Jenkins only requires changing the image tag. Plugin updates are handled separately via the Jenkins UI after the upgrade.

## Upgrade Process

### 1. Review Jenkins Release

- Read the release notes for the new version
- Check for breaking changes
- Review deprecated features
- Note any required migration steps

### 2. Review Security Advisories

- Check for security vulnerabilities
- Review patched issues
- Assess risk to your installation
- Prioritize security updates

### 3. Review Plugin Compatibility

- Go to **Manage Jenkins > Plugins > Installed** and note current plugin versions
- Check if any installed plugins are incompatible with the new Jenkins version
- Review the Jenkins plugin compatibility matrix online if needed

### 4. Update Jenkins Version

1. Edit `.env` file
2. Update `JENKINS_IMAGE_TAG` to the new tag (e.g. `2.568.2-jdk21` → `2.578.1-jdk21`)
   - This variable is used as the image tag in `docker-compose.yml`
   - Verify the tag exists on Docker Hub: https://hub.docker.com/r/jenkins/jenkins/tags
3. Verify Java version compatibility (the JDK in the tag must be supported by the Jenkins version)
   - Jenkins 2.568+ requires Java 21 (jdk17 images are no longer published)
   - Older LTS versions may support jdk17

### 5. Commit Changes

```bash
git add .env
git commit -m "Update Jenkins to version X.Y.Z"
git push
```

### 6. Test in Non-Production

1. Deploy to staging environment
2. Run health checks
3. Test critical functionality
4. Check **Manage Jenkins > Plugins** for any warnings
5. Check logs for warnings

### 7. Backup Production

```bash
./scripts/backup.sh
```

### 8. Deploy to Production

```bash
docker compose up -d
```

### 9. Health Check

```bash
./scripts/health-check.sh
```

### 10. Update Plugins via UI

1. Go to **Manage Jenkins > Plugins > Updates**
2. Install any available plugin updates
3. Restart Jenkins if prompted
4. Create a new backup: `./scripts/backup.sh`

### 11. Functional Verification

1. Check Jenkins UI
2. Verify jobs are accessible
3. Test pipeline execution
4. Check plugin functionality
5. Review system logs

## Upgrade Strategies

### Rolling Upgrade (Recommended)

1. Update `JENKINS_IMAGE_TAG` in `.env`
2. Stop current container: `docker compose down`
3. Start new container with same volume: `docker compose up -d`
4. Verify functionality

### Blue-Green Deployment

1. Deploy new version alongside old
2. Test new version
3. Switch traffic to new version
4. Keep old version as rollback

## Rollback Procedure

### When to Rollback

- Health checks fail
- Critical functionality broken
- Performance issues
- Security concerns

### Rollback Steps

1. **Stop Current Version**
   ```bash
   docker compose down
   ```

2. **Revert Git Changes**
   ```bash
   git revert HEAD
   git push
   ```

3. **Restore Backup (if needed)**
   ```bash
   ./scripts/restore.sh -f backup/jenkins-pre-upgrade-*.tar.gz
   ```

4. **Start Previous Version**
   ```bash
   docker compose up -d
   ```

5. **Verify Functionality**
   ```bash
   ./scripts/health-check.sh
   ```

### Rollback Considerations

- **Data Compatibility**: Jenkins data migrations may not be backward-compatible
- **Plugin Versions**: Plugin versions updated via UI may not be compatible with older Jenkins
- **Build History**: Build history may be affected by version changes

## Version Compatibility

### LTS Versions

- Jenkins LTS versions are supported for extended periods
- Upgrade to latest LTS for security patches
- Test thoroughly before upgrading

### Java Version

- Jenkins LTS versions have specific Java requirements
- The JDK is encoded in `JENKINS_IMAGE_TAG` (e.g. `2.568.2-jdk21`, `2.578.1-jdk21`)
- Check Java compatibility before upgrading

### Plugin Compatibility

- Some plugins may not support older Jenkins versions
- After upgrade, check **Manage Jenkins > Plugins** for warnings
- Update plugins via UI as needed

## Upgrade Checklist

### Pre-Upgrade

- [ ] Review release notes
- [ ] Check security advisories
- [ ] Note current plugin versions (Manage Jenkins > Plugins > Installed)
- [ ] Test in staging environment
- [ ] Create backup
- [ ] Document rollback procedure
- [ ] Notify stakeholders

### During Upgrade

- [ ] Stop Jenkins gracefully
- [ ] Deploy new version
- [ ] Start Jenkins
- [ ] Monitor startup logs
- [ ] Verify health checks

### Post-Upgrade

- [ ] Verify Jenkins UI
- [ ] Test critical jobs
- [ ] Update plugins via UI (Manage Jenkins > Plugins > Updates)
- [ ] Review system logs
- [ ] Monitor performance
- [ ] Create post-upgrade backup

## Common Upgrade Issues

### Plugin Compatibility Issues

- **Symptom**: Plugins fail to load or show warnings in **Manage Jenkins > Plugins**
- **Solution**: Update plugins to compatible versions via UI
- **Prevention**: Test plugin compatibility before upgrade

### Data Migration Issues

- **Symptom**: Jobs or configuration missing
- **Solution**: Restore from backup
- **Prevention**: Always backup before upgrade

### Performance Issues

- **Symptom**: Slow response times
- **Solution**: Monitor resource usage, adjust limits in `docker-compose.yml`
- **Prevention**: Test performance in staging

## Monitoring After Upgrade

### Key Metrics to Watch

- Jenkins response time
- Build queue length
- Agent connectivity
- Plugin load times
- Memory usage
- Disk usage

### Warning Signs

- Error logs increasing
- Slow job execution
- Agent disconnections
- Plugin failures
- Memory warnings

## Documentation Updates

After successful upgrade:

1. Update `.env` with the new `JENKINS_IMAGE_TAG` (already done during upgrade)
2. Update `docs/architecture.md` if needed
3. Update `docs/operations.md` if needed
4. Document any new procedures
