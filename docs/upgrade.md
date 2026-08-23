# Upgrade Guide

## Overview

This guide covers upgrading Jenkins to a new version. Upgrades should be treated as potentially stateful operations that require careful planning and testing.

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

- Check plugin compatibility matrix
- Verify required plugins support new version
- Note any plugins that need updates
- Check for plugin deprecations

### 4. Update Pinned Version

1. Edit `.env` file
2. Update `JENKINS_VERSION` to new LTS version
3. Verify Java version compatibility
4. Check base image availability

### 5. Update Plugins (if required)

1. Edit `plugins.txt`
2. Update plugin versions if needed
3. Add new plugins if required
4. Remove deprecated plugins

### 6. Commit Changes

```bash
git add .
git commit -m "Update Jenkins to version X.Y.Z"
git push
```

### 7. Build New Image

```bash
docker compose build
```

### 8. Test in Non-Production

1. Deploy to staging environment
2. Run health checks
3. Test critical functionality
4. Verify plugin compatibility
5. Check logs for warnings

### 9. Backup Production

```bash
./scripts/backup.sh
```

### 10. Deploy to Production

```bash
docker compose up -d
```

### 11. Health Check

```bash
./scripts/health-check.sh
```

### 12. Functional Verification

1. Check Jenkins UI
2. Verify jobs are accessible
3. Test pipeline execution
4. Check plugin functionality
5. Review system logs

## Upgrade Strategies

### Rolling Upgrade (Recommended)

1. Build new image with updated version
2. Stop current container
3. Start new container with same volume
4. Verify functionality

### Blue-Green Deployment

1. Deploy new version alongside old
2. Test new version
3. Switch traffic to new version
4. Keep old version as rollback

### Canary Deployment

1. Deploy to small subset of users
2. Monitor for issues
3. Gradually increase traffic
4. Full deployment if successful

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

3. **Rebuild Previous Version**
   ```bash
   docker compose build
   ```

4. **Restore Backup (if needed)**
   ```bash
   ./scripts/restore.sh -f backup/jenkins-pre-upgrade-*.tar.gz
   ```

5. **Start Previous Version**
   ```bash
   docker compose up -d
   ```

6. **Verify Functionality**
   ```bash
   ./scripts/health-check.sh
   ```

### Rollback Considerations

- **Data Compatibility**: Jenkins data migrations may not be backward-compatible
- **Plugin Versions**: Plugin versions may not be compatible with older Jenkins
- **Configuration Format**: JCasC format may differ between versions
- **Build History**: Build history may be affected by version changes

## Version Compatibility

### LTS Versions

- Jenkins LTS versions are supported for extended periods
- Upgrade to latest LTS for security patches
- Test thoroughly before upgrading

### Java Version

- Jenkins LTS versions have specific Java requirements
- Check Java compatibility before upgrading
- Update Java if required

### Plugin Compatibility

- Some plugins may not support older Jenkins versions
- Check plugin documentation for version requirements
- Update plugins as needed

## Upgrade Checklist

### Pre-Upgrade

- [ ] Review release notes
- [ ] Check security advisories
- [ ] Verify plugin compatibility
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
- [ ] Check plugin functionality
- [ ] Review system logs
- [ ] Monitor performance
- [ ] Update documentation

## Common Upgrade Issues

### Plugin Compatibility Issues

- **Symptom**: Plugins fail to load
- **Solution**: Update plugins to compatible versions
- **Prevention**: Test plugin compatibility before upgrade

### Configuration Format Changes

- **Symptom**: JCasC configuration errors
- **Solution**: Update configuration to new format
- **Prevention**: Review JCasC changelog before upgrade

### Data Migration Issues

- **Symptom**: Jobs or configuration missing
- **Solution**: Restore from backup
- **Prevention**: Always backup before upgrade

### Performance Issues

- **Symptom**: Slow response times
- **Solution**: Monitor resource usage, adjust limits
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

1. Update `README.md` with new version
2. Update `docs/architecture.md` if needed
3. Update `docs/operations.md` if needed
4. Document any new procedures
5. Update rollback documentation
