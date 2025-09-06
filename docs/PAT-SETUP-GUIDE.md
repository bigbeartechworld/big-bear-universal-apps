# Personal Access Token Setup Guide

This guide walks you through setting up a Fine-Grained Personal Access Token (PAT) for automated cross-repository pull requests in the Universal App Store Repository.

## Overview

The automated deployment system requires a Personal Access Token with specific permissions to:
- Clone target platform repositories
- Create new branches
- Push changes 
- Create pull requests
- Manage repository metadata

## Step 1: Create Fine-Grained Personal Access Token

### 1.1 Navigate to GitHub Settings

1. Click your profile picture in the top-right corner of GitHub
2. Select **Settings**
3. In the left sidebar, click **Developer settings**
4. Click **Personal access tokens**
5. Select **Fine-grained tokens**

### 1.2 Generate New Token

1. Click **Generate new token**
2. Fill in the token details:

#### Basic Information
- **Token name**: `big-bear-universal-apps-deployment`
- **Description**: `Automated deployment token for Universal App Store cross-repository operations`
- **Expiration**: `1 year` (maximum allowed)
- **Resource owner**: `bigbeartechworld` (or your organization)

#### Repository Access
Select **Selected repositories** and choose the following repositories:
- `bigbeartechworld/big-bear-casaos`
- `bigbeartechworld/big-bear-portainer`
- `bigbeartechworld/big-bear-dockge`
- `bigbeartechworld/big-bear-runtipi`
- `bigbeartechworld/big-bear-cosmos`

> ⚠️ **Important**: Do NOT select "All repositories" - this follows the principle of least privilege.

#### Permissions

For each selected repository, configure these permissions:

**Repository Permissions:**
- **Contents**: `Read and write` (Required to clone, read, and modify repository files)
- **Pull requests**: `Write` (Required to create pull requests)
- **Metadata**: `Read` (Required for basic repository operations)

**Optional Permissions (if needed):**
- **Issues**: `Write` (Only if you want the token to manage issues)
- **Actions**: `Read` (Only if you need to trigger workflows)

### 1.3 Generate and Copy Token

1. Click **Generate token**
2. **IMMEDIATELY COPY THE TOKEN** - you won't be able to see it again
3. Store it securely (you'll need it in the next step)

## Step 2: Add Token to Repository Secrets

### 2.1 Navigate to Your Private Repository

1. Go to your `big-bear-universal-apps` repository
2. Click **Settings** tab
3. In the left sidebar, click **Secrets and variables**
4. Select **Actions**

### 2.2 Create Repository Secret

1. Click **New repository secret**
2. **Name**: `PAT_CROSS_REPO_TOKEN`
3. **Secret**: Paste the token you copied in Step 1.3
4. Click **Add secret**

> ✅ **Verification**: You should see `PAT_CROSS_REPO_TOKEN` listed in your repository secrets.

## Step 3: Verify Token Permissions

### 3.1 Test Token Access

You can test your token has proper access using GitHub CLI or API:

```bash
# Test with GitHub CLI (if you have it installed)
gh auth login --with-token < your_token_file
gh repo view bigbeartechworld/big-bear-casaos

# Test with curl
curl -H "Authorization: token YOUR_TOKEN_HERE" \
     https://api.github.com/repos/bigbeartechworld/big-bear-casaos
```

### 3.2 Expected Response

You should receive repository information without errors. If you get a 403 or 404 error, double-check your token permissions.

## Step 4: Token Security Best Practices

### 4.1 Token Storage
- ✅ **DO**: Store in GitHub repository secrets
- ✅ **DO**: Use environment variables in local development
- ❌ **DON'T**: Hardcode in source code
- ❌ **DON'T**: Share in plain text files
- ❌ **DON'T**: Commit to version control

### 4.2 Token Scope
- ✅ **DO**: Use fine-grained tokens with minimal required permissions
- ✅ **DO**: Scope to specific repositories only
- ❌ **DON'T**: Use classic tokens with broad scopes
- ❌ **DON'T**: Grant unnecessary permissions

### 4.3 Token Rotation
- 📅 **Set Calendar Reminder**: Token expires in 1 year
- 🔄 **Rotation Process**: Generate new token ~1 month before expiration
- 🗑️ **Cleanup**: Revoke old tokens after successful rotation

## Step 5: Troubleshooting

### Common Issues and Solutions

#### 5.1 "Resource not accessible by personal access token"
**Cause**: Token doesn't have required permissions
**Solution**: 
1. Go to token settings
2. Add missing permissions (usually `Contents: Write` or `Pull requests: Write`)
3. Update the token in repository secrets

#### 5.2 "Bad credentials" or 403 errors
**Cause**: Token is invalid or expired
**Solution**:
1. Check if token is correctly copied to secrets
2. Verify token hasn't expired
3. Generate new token if needed

#### 5.3 "Repository not found" errors
**Cause**: Token doesn't have access to target repositories
**Solution**:
1. Edit token settings
2. Add missing repositories to the token's scope
3. Ensure repositories exist and you have access

#### 5.4 Workflow fails with permission errors
**Cause**: GitHub Actions permissions may be restricted
**Solution**:
1. Go to repository Settings → Actions → General
2. Under "Workflow permissions", ensure "Allow GitHub Actions to create and approve pull requests" is enabled

## Step 6: Monitoring and Maintenance

### 6.1 Regular Checks
- Monthly review of token usage in GitHub's audit log
- Quarterly review of token permissions
- Annual token rotation

### 6.2 Usage Monitoring
Monitor token usage through:
- GitHub's audit log: Settings → Audit log
- Repository insights and pull request activity
- GitHub Actions workflow logs

### 6.3 Security Monitoring
Watch for:
- Unexpected repository access
- Failed authentication attempts
- Unusual pull request patterns
- Token usage from unexpected locations

## Step 7: Emergency Procedures

### 7.1 Token Compromise
If you suspect the token has been compromised:

1. **IMMEDIATELY REVOKE** the token:
   - Go to Settings → Developer settings → Personal access tokens
   - Find the token and click "Delete"

2. **Generate new token** following steps above

3. **Update repository secret** with new token

4. **Review recent activity** for any unauthorized changes

### 7.2 Workflow Failures
If automated deployments fail:

1. Check workflow logs in Actions tab
2. Verify token permissions and expiration
3. Test token access manually
4. Check target repository permissions

## Appendix: Token Configuration Reference

### Complete Token Configuration

```json
{
  "name": "big-bear-universal-apps-deployment",
  "expiration": "1 year",
  "repositories": [
    "bigbeartechworld/big-bear-casaos",
    "bigbeartechworld/big-bear-portainer", 
    "bigbeartechworld/big-bear-dockge",
    "bigbeartechworld/big-bear-runtipi",
    "bigbeartechworld/big-bear-cosmos"
  ],
  "permissions": {
    "contents": "write",
    "pull_requests": "write", 
    "metadata": "read"
  }
}
```

### Required GitHub Repository Settings

For the **private Universal Apps repository**:
- Repository secret: `PAT_CROSS_REPO_TOKEN`
- Actions permissions: "Allow GitHub Actions to create and approve pull requests"

For each **target platform repository**:
- Allow pull requests from external contributors
- Branch protection rules (recommended)
- Required reviewers (recommended)

---

## Quick Setup Checklist

- [ ] Create fine-grained PAT with correct permissions
- [ ] Add PAT to repository secrets as `PAT_CROSS_REPO_TOKEN`
- [ ] Test token access to all target repositories
- [ ] Enable GitHub Actions to create pull requests
- [ ] Set calendar reminder for token renewal (11 months from now)
- [ ] Test automated workflow with sample app

**Setup Complete!** Your Universal App Store Repository can now automatically create pull requests to all platform repositories.

---

*Last updated: September 2025*  
*Token expiration reminder: Set for September 2026*