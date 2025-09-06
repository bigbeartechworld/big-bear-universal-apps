# Manual Deployment Guide

This guide shows you how to deploy apps to platform repositories manually, without using GitHub Actions. This is useful for testing, emergency deployments, or when you prefer direct control over the process.

## 🚀 Quick Start

### Prerequisites

1. **Node.js 20+** and npm installed
2. **GitHub CLI** (`gh`) installed and authenticated
3. **Git** configured with your credentials  
4. **Repository access** to all target platform repositories

### Installation

```bash
# Install dependencies
npm install

# Test your setup
npm run validate
```

## 📋 Manual Deployment Options

### 1. Quick Deployment (Recommended)

Use the simple npm scripts for common scenarios:

```bash
# Deploy all apps to all platforms
npm run deploy

# Preview what would be deployed (dry run)
npm run deploy:dry-run

# Deploy to specific platforms
npm run deploy:casaos
npm run deploy:portainer  
npm run deploy:dockge
npm run deploy:runtipi
npm run deploy:cosmos

# Deploy to multiple specific platforms
npm run deploy casaos portainer
```

### 2. Advanced Deployment

For more control, use the advanced manual deployment script:

```bash
# Full deployment with all options
node scripts/deploy-manual.js

# Deploy specific apps to specific platforms
node scripts/deploy-manual.js --platforms=casaos,portainer --apps=dockpeek,nextcloud

# Dry run to preview changes
node scripts/deploy-manual.js --dry-run

# Skip validation (emergency use only)
node scripts/deploy-manual.js --force

# Keep temporary files for debugging
node scripts/deploy-manual.js --keep-temp
```

### 3. Step-by-Step Deployment

For maximum control, run each step individually:

```bash
# 1. Validate apps
npm run validate

# 2. Create universal format
npm run standardize

# 3. Convert to platform formats
npm run convert:all

# 4. Deploy manually using the converted files
# (Copy files and create PRs manually)
```

## 🔧 Command Reference

### Quick Deploy Commands

| Command | Description |
|---------|-------------|
| `npm run deploy` | Deploy all apps to all platforms |
| `npm run deploy:dry-run` | Preview deployment without changes |
| `npm run deploy:casaos` | Deploy to CasaOS only |
| `npm run deploy:portainer` | Deploy to Portainer only |
| `npm run deploy:dockge` | Deploy to Dockge only |
| `npm run deploy:runtipi` | Deploy to Runtipi only |
| `npm run deploy:cosmos` | Deploy to Cosmos only |

### Advanced Deploy Options

```bash
node scripts/deploy-manual.js [options]

Options:
  --platforms=LIST    Comma-separated platforms (casaos,portainer,dockge,runtipi,cosmos)
  --apps=LIST         Comma-separated specific apps to deploy  
  --dry-run           Preview changes without deploying
  --force             Skip app validation
  --keep-temp         Keep temporary files for debugging
  --help              Show detailed help
```

### Validation Commands

| Command | Description |
|---------|-------------|
| `npm run validate` | Validate all apps |
| `npm run validate:app dockpeek` | Validate specific app |
| `npm run validate:app "app1,app2"` | Validate multiple apps |

### Conversion Commands

| Command | Description |
|---------|-------------|
| `npm run convert:all` | Convert to all platform formats |
| `npm run convert:casaos` | Convert to CasaOS format only |
| `npm run convert:portainer` | Convert to Portainer templates |
| `npm run convert:dockge` | Convert to Dockge stacks |
| `npm run convert:runtipi` | Convert to Runtipi apps |
| `npm run convert:cosmos` | Convert to Cosmos servApps |

## 📋 Deployment Process

When you run a manual deployment, the script:

1. **Validates** all apps for syntax and consistency errors
2. **Converts** apps to platform-specific formats
3. **Clones** target platform repositories
4. **Copies** converted files to appropriate directories
5. **Creates** a new branch with changes
6. **Commits** changes with descriptive message
7. **Pushes** branch to GitHub
8. **Creates** pull request with detailed information

## 🎯 Common Use Cases

### Deploy Single App

```bash
# Validate and deploy single app to all platforms
npm run validate:app dockpeek
npm run deploy

# Or deploy to specific platforms
npm run deploy casaos portainer
```

### Emergency Deployment

```bash
# Skip validation and deploy immediately
node scripts/deploy-manual.js --force

# Or for specific urgent fix
node scripts/deploy-manual.js --platforms=casaos --apps=critical-app --force
```

### Test Deployment

```bash
# Preview what would happen
npm run deploy:dry-run

# Or with specific apps
node scripts/deploy-manual.js --apps=test-app --dry-run
```

### Bulk Updates

```bash
# Deploy all apps after major changes
npm run validate
npm run deploy

# Or deploy multiple specific apps
node scripts/deploy-manual.js --apps="app1,app2,app3"
```

## 🔍 Debugging

### Check Validation Issues

```bash
# Validate specific problematic app
npm run validate:app problematic-app

# Check all apps for issues
npm run validate
```

### Inspect Converted Files

```bash
# Generate all platform formats
npm run convert:all

# Check generated files
ls -la casaos-apps/
ls -la portainer-templates/
ls -la dockge-stacks/
ls -la runtipi-apps/
ls -la cosmos-servapps/
```

### Debug Deployment

```bash
# Keep temporary files for inspection
node scripts/deploy-manual.js --keep-temp --dry-run

# Check temp files
ls -la scripts/temp-repos/
```

## ⚠️ Troubleshooting

### Common Issues

#### "GitHub CLI not found"
```bash
# Install GitHub CLI
# macOS:
brew install gh

# Or download from: https://cli.github.com/
```

#### "Authentication failed"
```bash
# Authenticate with GitHub
gh auth login

# Check authentication
gh auth status
```

#### "Permission denied"
```bash
# Ensure you have access to target repositories
gh repo view bigbeartechworld/big-bear-casaos
gh repo view bigbeartechworld/big-bear-portainer
# etc.
```

#### "Validation failed"
```bash
# Check specific app
npm run validate:app problematic-app

# Fix issues in Apps/[app-name]/ directory
# Common fixes: JSON syntax, missing fields, invalid YAML
```

#### "Conversion failed"
```bash
# Ensure universal format exists
npm run standardize

# Try converting individual platforms
npm run convert:casaos
# Check for errors in specific converter
```

#### "Git operation failed"
```bash
# Ensure git is configured
git config --global user.name "Your Name"
git config --global user.email "your.email@example.com"

# Check repository access
git clone https://github.com/bigbeartechworld/big-bear-casaos.git temp-test
rm -rf temp-test
```

### Getting Help

**Validation Issues**: Check app structure and required fields
**Conversion Issues**: Verify universal format exists
**Git/GitHub Issues**: Check authentication and repository access
**Permission Issues**: Ensure proper repository access rights

## 📊 Deployment Reports

After deployment, you'll see a summary like this:

```
📊 DEPLOYMENT SUMMARY
============================================================
🔍 Deployment ID: manual-1693901234567
🔍 Total platforms: 5
✅ Successful: 4
❌ Failed: 1

✅ SUCCESSFUL DEPLOYMENTS:
  1. casaos
     PR: https://github.com/bigbeartechworld/big-bear-casaos/pull/123
     Branch: auto-update-manual-1693901234567-casaos
  2. portainer
     PR: https://github.com/bigbeartechworld/big-bear-portainer/pull/45
     Branch: auto-update-manual-1693901234567-portainer

❌ FAILED DEPLOYMENTS:
  1. dockge: Authentication failed

🎉 DEPLOYMENT COMPLETED WITH SOME ISSUES
============================================================
```

## 🔄 Workflow Integration

### Manual + Automated Hybrid

You can use manual deployment alongside GitHub Actions:

1. **Use manual deployment** for urgent fixes and testing
2. **Use GitHub Actions** for regular automated updates
3. **Both create PRs** for review before merging

### Best Practices

- ✅ **Always run validation** before deployment
- ✅ **Use dry-run** to preview changes  
- ✅ **Review generated PRs** before merging
- ✅ **Test in staging** before production deployment
- ❌ **Don't skip validation** unless emergency
- ❌ **Don't deploy untested changes** to production

---

## 📞 Support

**Issues**: Check the troubleshooting section above  
**Advanced Help**: Use `node scripts/deploy-manual.js --help`  
**GitHub Issues**: Report problems in the repository  

**🎯 Goal**: Give you complete control over app deployments with the flexibility to deploy manually when needed.