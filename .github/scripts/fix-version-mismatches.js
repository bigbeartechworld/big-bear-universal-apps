#!/usr/bin/env bun

/**
 * Fix all version mismatches between docker-compose.yml and app.json
 * This updates all app.json files to match their docker-compose.yml versions
 */

const fs = require('fs');
const path = require('path');
const yaml = require('js-yaml');

async function fixVersionMismatches() {
  const appsDir = path.join(__dirname, '../../apps');
  const apps = fs.readdirSync(appsDir).filter(name => {
    const stat = fs.statSync(path.join(appsDir, name));
    return stat.isDirectory() && !name.startsWith('_');
  });

  console.log(`🔧 Fixing version mismatches in ${apps.length} apps...\n`);

  let fixedCount = 0;
  const fixed = [];

  for (const appName of apps) {
    try {
      const appDir = path.join(appsDir, appName);
      const dockerComposePath = path.join(appDir, 'docker-compose.yml');
      const appJsonPath = path.join(appDir, 'app.json');

      if (!fs.existsSync(dockerComposePath) || !fs.existsSync(appJsonPath)) {
        continue;
      }

      // Read files
      const dockerComposeContent = fs.readFileSync(dockerComposePath, 'utf8');
      const dockerCompose = yaml.load(dockerComposeContent);
      const appJson = JSON.parse(fs.readFileSync(appJsonPath, 'utf8'));

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
        continue;
      }

      // Extract version
      const versionMatch = imageTag.match(/:([^:]+)$/);
      if (!versionMatch) {
        continue;
      }

      const dockerVersion = versionMatch[1];
      const appJsonVersion = appJson.metadata?.version;

      // Skip if version is "latest" or "stable"
      if (dockerVersion === 'latest' || dockerVersion === 'stable') {
        continue;
      }
      
      // Check if version starts with digits or 'v' followed by digits
      if (!dockerVersion.match(/^(v)?\d+/)) {
        continue;
      }

      // Check for mismatch and fix
      if (dockerVersion !== appJsonVersion) {
        appJson.metadata.version = dockerVersion;
        appJson.metadata.updated = new Date().toISOString();

        fs.writeFileSync(
          appJsonPath,
          JSON.stringify(appJson, null, 2) + '\n',
          'utf8'
        );

        console.log(`✅ ${appName}: ${appJsonVersion} → ${dockerVersion}`);
        fixed.push({ appName, from: appJsonVersion, to: dockerVersion });
        fixedCount++;
      }

    } catch (error) {
      console.error(`❌ Error processing ${appName}: ${error.message}`);
    }
  }

  // Summary
  console.log('\n' + '='.repeat(60));
  console.log(`✅ Fixed ${fixedCount} version mismatches`);
  
  if (fixedCount > 0) {
    console.log('\n💡 Next steps:');
    console.log('   1. Review the changes: git diff');
    console.log('   2. Commit the changes: git add apps/*/app.json');
    console.log('   3. Create a PR: git commit -m "chore: sync app.json versions with docker-compose.yml"');
  }
  
  console.log('');
}

// Run the fix
fixVersionMismatches();
