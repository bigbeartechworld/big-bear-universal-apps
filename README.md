# Big Bear Universal Apps Repository

🚀 **Private Universal App Store Repository with Automated Cross-Repository Deployment**

This repository serves as the single source of truth for all Big Bear apps and automatically deploys them to platform-specific repositories via GitHub Actions workflows.

## 🏗️ Architecture

```
big-bear-universal-apps (Private)
├── Apps/                           # Original CasaOS format apps
├── universal-app-store/            # Standardized universal format  
├── config/platforms.json           # Platform repository configuration
├── .github/workflows/              # Automated deployment workflows
├── scripts/                        # Conversion and validation scripts
└── docs/                          # Documentation and guides
```

### 📤 Automated Deployments

When changes are pushed to this repository, GitHub Actions automatically:

1. **Detects changed apps** from git diff analysis
2. **Validates app structure** and metadata
3. **Converts apps** to platform-specific formats
4. **Creates pull requests** in target repositories:
   - `bigbeartechworld/big-bear-casaos`
   - `bigbeartechworld/big-bear-portainer`
   - `bigbeartechworld/big-bear-dockge`
   - `bigbeartechworld/big-bear-runtipi`
   - `bigbeartechworld/big-bear-cosmos`

## 🚀 Quick Start

### Prerequisites

1. **Node.js 20+** installed
2. **Personal Access Token** configured (see [PAT Setup Guide](docs/PAT-SETUP-GUIDE.md))
3. **Repository secrets** configured in GitHub

### Setup

```bash
# Install dependencies
npm install

# Validate apps
node scripts/validate-apps.js

# Run standardization (creates universal-app-store/)
node standardize-apps.js

# Test conversions
node convert-to-casaos.js
node convert-to-portainer.js
node convert-to-dockge.js
node convert-to-runtipi.js
node convert-to-cosmos.js
```

## 🔧 Platform Converters

| Platform | Script | Output Format | Target Repo |
|----------|--------|---------------|-------------|
| **CasaOS** | `convert-to-casaos.js` | Apps/ directories with config.json | big-bear-casaos |
| **Portainer** | `convert-to-portainer.js` | templates.json master file | big-bear-portainer |
| **Dockge** | `convert-to-dockge.js` | Individual stack directories | big-bear-dockge |
| **Runtipi** | `convert-to-runtipi.js` | Official app store format | big-bear-runtipi |
| **Cosmos** | `convert-to-cosmos.js` | servApps format | big-bear-cosmos |

### ✅ Conversion Success Rate: **100%** (206/206 apps)

## 🤖 GitHub Actions Workflows

### 1. Deploy to Platforms (`deploy-to-platforms.yml`)

**Triggers:**
- Push to `main`/`master` with app changes
- Manual workflow dispatch

**Features:**
- Smart change detection
- Matrix deployment strategy
- Automatic pull request creation
- Detailed deployment summaries
- Error handling and rollback

### 2. Validate Apps (`validate-apps.yml`) 

**Triggers:**
- Pull requests with app changes
- Manual workflow dispatch

**Features:**
- Structure validation
- Metadata consistency checks
- Conversion testing
- Comprehensive reporting

## 📋 Manual Operations

### 🚀 Manual Deployment (No GitHub Actions Required)

**Quick Deploy:**
```bash
# Deploy all apps to all platforms
npm run deploy

# Preview deployment (dry run)
npm run deploy:dry-run

# Deploy to specific platforms
npm run deploy:casaos
npm run deploy:portainer dockge
```

**Advanced Manual Deploy:**
```bash
# Deploy specific apps to specific platforms
node scripts/deploy-manual.js --platforms=casaos,portainer --apps=dockpeek,nextcloud

# Emergency deployment (skip validation)
node scripts/deploy-manual.js --force --platforms=casaos

# Preview what would be deployed
node scripts/deploy-manual.js --dry-run
```

📖 **Complete Manual Guide**: [Manual Deployment Guide](docs/MANUAL-DEPLOYMENT.md)

### Validate Apps
```bash
# Validate single app
npm run validate:app dockpeek

# Validate multiple apps  
npm run validate:app "dockpeek,nextcloud,plex"

# Validate all apps
npm run validate
```

### Convert Apps Only
```bash
# Convert to all formats
npm run convert:all

# Convert to specific platforms
npm run convert:casaos
npm run convert:portainer
```

### GitHub Actions Deployment
```bash
# Deploy via GitHub CLI (requires repository setup)
gh workflow run deploy-to-platforms.yml \
  -f platforms="casaos,portainer" \
  -f apps="dockpeek,nextcloud"
```

### Add New Platform

1. **Update `config/platforms.json`**:
```json
{
  "new-platform": {
    "repo": "bigbeartechworld/big-bear-new-platform",
    "branch": "main",
    "base_path": "apps",
    "converter_script": "convert-to-new-platform.js",
    "output_dir": "new-platform-apps"
  }
}
```

2. **Create converter script** following existing patterns
3. **Test conversion** with sample apps
4. **Update workflows** to include new platform

## 🔐 Security & Authentication  

### Personal Access Token (PAT)

This repository uses a **Fine-Grained Personal Access Token** for cross-repository operations:

- **Token Name**: `big-bear-universal-apps-deployment`
- **Scope**: Selected repositories only
- **Permissions**: Contents (write), Pull requests (write), Metadata (read)
- **Storage**: GitHub repository secret `PAT_CROSS_REPO_TOKEN`

📖 **Full Setup Instructions**: [PAT Setup Guide](docs/PAT-SETUP-GUIDE.md)

## 📊 Repository Statistics

- **Total Apps**: 206
- **Platform Coverage**: 5 platforms
- **Conversion Success Rate**: 100%
- **Multi-Service Apps**: ~20 apps
- **Average Conversion Time**: <2 minutes per platform

## 🛠️ Development

### App Format Standards

**Universal Format** (`universal-app-store/apps/[app-name]/`):
- `metadata.json` - Complete app metadata
- `docker-compose.yml` - Container definitions
- `README.md` - App documentation
- `screenshots/` - App screenshots (optional)

**Validation Requirements**:
- Valid JSON syntax
- Required fields: `name`, `version`
- Valid Docker Compose YAML
- Port mappings for web interfaces
- Consistent naming across files

### Adding New Apps

1. **Create app directory** in `Apps/[app-name]/`
2. **Add required files**:
   - `config.json` (CasaOS format)
   - `docker-compose.yml`
   - `README.md`
3. **Validate app**: `node scripts/validate-apps.js [app-name]`
4. **Test conversion**: Run all converter scripts
5. **Commit changes** - automation handles the rest

### Troubleshooting

#### Common Issues

**❌ Conversion Script Errors**
```bash
# Check if universal format exists
ls universal-app-store/apps/

# Re-run standardization
node standardize-apps.js
```

**❌ Validation Failures**
```bash
# Check specific app
node scripts/validate-apps.js [app-name]

# Common fixes:
# - Add missing required fields
# - Fix JSON/YAML syntax errors  
# - Ensure proper service definitions
```

**❌ GitHub Actions Failures**
- Check PAT token expiration
- Verify repository permissions
- Review workflow logs in Actions tab

## 📖 Documentation

- [PAT Setup Guide](docs/PAT-SETUP-GUIDE.md) - Complete token setup walkthrough
- [Platform Configuration](config/platforms.json) - Repository mappings
- [Validation Reference](scripts/validate-apps.js) - App structure requirements

## 🤝 Contributing

### For Big Bear Team

1. **Add/modify apps** in `Apps/` directory
2. **Run validation**: `node scripts/validate-apps.js`
3. **Create pull request** - automated deployment will handle the rest
4. **Review generated PRs** in target repositories

### Workflow

```
Developer Changes → PR to Universal Repo → Auto-Validation → 
Merge → Auto-Deploy → PRs in Platform Repos → Review & Merge
```

## 📈 Future Enhancements

- [ ] **Additional Platforms**: Umbrel, Cosmos Pro, TrueNAS SCALE
- [ ] **Advanced Validation**: Docker image availability checks
- [ ] **Automated Testing**: Deploy validation in staging environments  
- [ ] **Metrics Dashboard**: Deployment success rates and timing
- [ ] **Conflict Resolution**: Smart handling of concurrent changes

---

## 📞 Support

**Issues**: Report problems in this repository's Issues tab  
**Questions**: Contact the Big Bear team  
**Security**: Report security issues privately to the maintainers

---

**🎯 Mission**: Streamline app deployment across all self-hosted platforms while maintaining quality, security, and developer productivity.

*Last updated: September 2025*
