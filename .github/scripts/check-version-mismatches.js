#!/usr/bin/env bun

/**
 * Check for version mismatches between docker-compose.yml and app.json
 * This helps identify apps that need version synchronization
 */

const fs = require('fs');
const path = require('path');
const yaml = require('js-yaml');

async function checkVersionMismatches() {
  const appsDir = path.join(__dirname, '../../apps');
  const apps = fs.readdirSync(appsDir).filter(name => {
    const stat = fs.statSync(path.join(appsDir, name));
    return stat.isDirectory() && !name.startsWith('_');
  });

  console.log(`🔍 Checking ${apps.length} apps for version mismatches...\n`);

  const mismatches = [];
  const noVersion = [];
  const errors = [];

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
        noVersion.push({ appName, dockerVersion });
        continue;
      }
      
      // Check if version starts with digits or 'v' followed by digits
      if (!dockerVersion.match(/^(v)?\d+/)) {
        noVersion.push({ appName, dockerVersion });
        continue;
      }

      // Check for mismatch
      if (dockerVersion !== appJsonVersion) {
        mismatches.push({
          appName,
          dockerVersion,
          appJsonVersion,
          path: `apps/${appName}`
        });
      }

    } catch (error) {
      errors.push({ appName, error: error.message });
    }
  }

  // Report results
  console.log('📊 Results:');
  console.log('='.repeat(60));
  
  if (mismatches.length > 0) {
    console.log(`\n❌ Found ${mismatches.length} version mismatches:\n`);
    for (const m of mismatches) {
      console.log(`  ${m.appName}:`);
      console.log(`    docker-compose: ${m.dockerVersion}`);
      console.log(`    app.json:       ${m.appJsonVersion}`);
      console.log(`    path:           ${m.path}`);
      console.log('');
    }
  } else {
    console.log('\n✅ No version mismatches found!\n');
  }

  if (noVersion.length > 0) {
    console.log(`ℹ️  ${noVersion.length} apps using non-semver tags (latest, stable, etc.)`);
  }

  if (errors.length > 0) {
    console.log(`\n⚠️  ${errors.length} apps had errors during processing`);
  }

  // Summary
  console.log('\n' + '='.repeat(60));
  console.log(`Total apps checked: ${apps.length}`);
  console.log(`Mismatches found: ${mismatches.length}`);
  console.log(`Non-semver tags: ${noVersion.length}`);
  console.log(`Errors: ${errors.length}`);
  
  return mismatches;
}

// Run the check
checkVersionMismatches().then(mismatches => {
  if (mismatches.length > 0) {
    console.log('\n💡 To fix all mismatches, run:');
    console.log('   bun .github/scripts/fix-version-mismatches.js\n');
    process.exit(1);
  } else {
    console.log('');
    process.exit(0);
  }
});
