const fs = require('fs');
const path = require('path');
const yaml = require('js-yaml');

/**
 * Updates app.json version based on docker-compose.yml image version
 * This script is run automatically when Renovate updates docker-compose.yml files
 */

async function updateAppVersion() {
  try {
    // Get the list of changed files from GitHub Actions
    const changedFiles = process.env.CHANGED_FILES?.split('\n').filter(Boolean) || [];
    
    console.log('Changed files:', changedFiles);

    const dockerComposeFiles = changedFiles.filter(file => 
      file.includes('docker-compose.yml') && 
      file.startsWith('apps/')
    );

    if (dockerComposeFiles.length === 0) {
      console.log('No docker-compose.yml files found in apps directory');
      return;
    }

    let hasChanges = false;

    for (const dockerComposePath of dockerComposeFiles) {
      try {
        // Extract app directory
        const appDir = path.dirname(dockerComposePath);
        const appJsonPath = path.join(appDir, 'app.json');

        console.log(`Processing: ${dockerComposePath}`);
        console.log(`App directory: ${appDir}`);
        console.log(`App JSON path: ${appJsonPath}`);

        // Check if app.json exists
        if (!fs.existsSync(appJsonPath)) {
          console.log(`No app.json found at ${appJsonPath}, skipping`);
          continue;
        }

        // Read docker-compose.yml
        const dockerComposeContent = fs.readFileSync(dockerComposePath, 'utf8');
        const dockerCompose = yaml.load(dockerComposeContent);

        // Read app.json
        const appJsonContent = fs.readFileSync(appJsonPath, 'utf8');
        const appJson = JSON.parse(appJsonContent);

        // Find the service with the versioned image
        // Priority: 1) main_image from app.json, 2) main_service, 3) first service
        let targetService = null;
        let imageTag = null;
        
        // Try to match by main_image if it exists
        if (appJson.technical?.main_image) {
          const mainImageName = appJson.technical.main_image;
          
          for (const [serviceName, service] of Object.entries(dockerCompose.services || {})) {
            if (service.image?.startsWith(mainImageName)) {
              targetService = serviceName;
              imageTag = service.image;
              break;
            }
          }
        }
        
        // Fall back to main_service if main_image didn't match
        if (!targetService) {
          const mainService = appJson.technical?.main_service || Object.keys(dockerCompose.services || {})[0];
          
          if (mainService && dockerCompose.services?.[mainService]) {
            targetService = mainService;
            imageTag = dockerCompose.services[mainService].image;
          }
        }

        if (!imageTag) {
          console.log('No image tag found');
          continue;
        }

        console.log(`Target service: ${targetService}`);
        console.log(`Image tag: ${imageTag}`);

        // Extract version from image tag (e.g., "budibase/budibase:3.22.4" -> "3.22.4")
        const versionMatch = imageTag.match(/:([^:]+)$/);
        
        if (!versionMatch) {
          console.log('Could not extract version from image tag');
          continue;
        }

        let newVersion = versionMatch[1];
        console.log(`Extracted version: ${newVersion}`);

        // Skip if version is "latest" or "stable"
        if (newVersion === 'latest' || newVersion === 'stable') {
          console.log(`Skipping non-semver version tag: ${newVersion}`);
          continue;
        }
        
        // Check if version starts with digits or 'v' followed by digits
        if (!newVersion.match(/^(v)?\d+/)) {
          console.log(`Skipping non-semver version tag: ${newVersion}`);
          continue;
        }

        const currentVersion = appJson.metadata?.version;
        console.log(`Current version in app.json: ${currentVersion}`);

        // Update version if it has changed
        if (currentVersion !== newVersion) {
          appJson.metadata.version = newVersion;
          appJson.metadata.updated = new Date().toISOString();

          // Write updated app.json with proper formatting
          fs.writeFileSync(
            appJsonPath,
            JSON.stringify(appJson, null, 2) + '\n',
            'utf8'
          );

          console.log(`✅ Updated ${appJsonPath}: ${currentVersion} -> ${newVersion}`);
          hasChanges = true;
        } else {
          console.log(`Version already up to date: ${currentVersion}`);
        }
      } catch (error) {
        console.error(`Error processing ${dockerComposePath}:`, error.message);
      }
    }

    // Set output for GitHub Actions
    if (hasChanges) {
      console.log('\n✅ Version updates completed successfully');
      // Write to GITHUB_OUTPUT if available
      if (process.env.GITHUB_OUTPUT) {
        fs.appendFileSync(process.env.GITHUB_OUTPUT, `has_changes=true\n`);
      }
    } else {
      console.log('\nℹ️  No version updates needed');
      if (process.env.GITHUB_OUTPUT) {
        fs.appendFileSync(process.env.GITHUB_OUTPUT, `has_changes=false\n`);
      }
    }

  } catch (error) {
    console.error('Error in updateAppVersion:', error);
    process.exit(1);
  }
}

// Run the script
updateAppVersion();
