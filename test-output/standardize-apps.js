#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const yaml = require('js-yaml');

// Simple version for testing
function standardizeApp(appId) {
    const appDir = path.join('Apps', appId);
    const outputAppDir = path.join('apps', appId);
    
    if (!fs.existsSync(appDir) || !fs.statSync(appDir).isDirectory() || appId === '__tests__') {
        return null;
    }
    
    try {
        console.log(`✅ Processing ${appId}...`);
        
        // Create output directory for universal repo
        const universalRepoDir = './universal-app-store';
        const universalAppsDir = path.join(universalRepoDir, 'apps');
        const finalOutputDir = path.join(universalAppsDir, appId);
        
        if (!fs.existsSync(universalRepoDir)) fs.mkdirSync(universalRepoDir);
        if (!fs.existsSync(universalAppsDir)) fs.mkdirSync(universalAppsDir);
        if (!fs.existsSync(finalOutputDir)) fs.mkdirSync(finalOutputDir, { recursive: true });
        
        // Read config.json
        const configPath = path.join(appDir, 'config.json');
        const config = fs.existsSync(configPath) ? JSON.parse(fs.readFileSync(configPath, 'utf8')) : {};
        
        // Read docker-compose.yml
        const dockerComposePath = path.join(appDir, 'docker-compose.yml');
        if (!fs.existsSync(dockerComposePath)) {
            console.warn(`⚠️ Skipping ${appId}: No docker-compose.yml`);
            return null;
        }
        
        const dockerCompose = yaml.load(fs.readFileSync(dockerComposePath, 'utf8'));
        const casaOS = dockerCompose['x-casaos'] || {};
        
        // Extract service-level x-casaos metadata from ALL services
        const allServicesMetadata = {};
        if (dockerCompose.services) {
            Object.keys(dockerCompose.services).forEach(serviceName => {
                const service = dockerCompose.services[serviceName];
                if (service['x-casaos']) {
                    allServicesMetadata[serviceName] = service['x-casaos'];
                }
            });
        }
        
        // Create simplified universal metadata
        const metadata = {
            id: appId,
            name: casaOS.title?.en_us || appId,
            description: casaOS.description?.en_us || '',
            tagline: casaOS.tagline?.en_us || '',
            version: config.version || '1.0.0',
            image: config.image || '',
            developer: casaOS.developer || '',
            author: casaOS.author || 'BigBearTechWorld',
            icon: casaOS.icon || '',
            thumbnail: casaOS.thumbnail || '',
            screenshots: casaOS.screenshot_link || [],
            category: casaOS.category || 'BigBearCasaOS',
            architectures: casaOS.architectures || ['amd64'],
            main_service: casaOS.main || 'app',
            port_map: casaOS.port_map || '',
            tips: casaOS.tips || {},
            services_metadata: allServicesMetadata,
            links: {
                big_bear_casaos_youtube: config.youtube || '',
                docs: config.docs_link || '',
                big_bear_cosmos_youtube: config.big_bear_cosmos_youtube || ''
            }
        };
        
        // Save metadata
        fs.writeFileSync(path.join(finalOutputDir, 'metadata.json'), JSON.stringify(metadata, null, 2));
        
        // Copy clean docker-compose
        const cleanCompose = { ...dockerCompose };
        delete cleanCompose['x-casaos'];
        if (cleanCompose.services) {
            Object.keys(cleanCompose.services).forEach(svc => {
                delete cleanCompose.services[svc]['x-casaos'];
            });
        }
        fs.writeFileSync(path.join(finalOutputDir, 'docker-compose.yml'), yaml.dump(cleanCompose));
        
        // Copy or create README
        const readmePath = path.join(appDir, 'README.md');
        if (fs.existsSync(readmePath)) {
            fs.copyFileSync(readmePath, path.join(finalOutputDir, 'README.md'));
        } else {
            fs.writeFileSync(path.join(finalOutputDir, 'README.md'), `# ${metadata.name}\n\n${metadata.description}\n`);
        }
        
        return { id: appId, name: metadata.name, success: true };
        
    } catch (error) {
        console.error(`❌ Error processing ${appId}:`, error.message);
        return { id: appId, success: false, error: error.message };
    }
}

if (require.main === module) {
    console.log('🚀 Starting full standardization to universal repo...\n');
    
    const apps = fs.readdirSync('Apps');
    let processed = 0;
    let failed = 0;
    
    // Create universal repo structure
    const universalRepoDir = './universal-app-store';
    
    // Create README for the universal repo
    const repoReadme = `# Universal App Store Repository

This repository contains apps in a standardized universal format that can be converted to multiple self-hosted platforms.

## Repository Structure

\`\`\`
apps/
├── [app-name]/
│   ├── metadata.json          # Universal metadata
│   ├── docker-compose.yml     # Standard Docker Compose
│   └── README.md             # App documentation
\`\`\`

## Supported Target Platforms

- CasaOS
- Portainer
- Dockge  
- Runtipi

## Generated from

This repository was auto-generated from [big-bear-casaos](https://github.com/bigbeartechworld/big-bear-casaos) on ${new Date().toISOString()}.

Total apps: ${apps.length - 1} (excluding __tests__)
`;

    if (!fs.existsSync(universalRepoDir)) {
        fs.mkdirSync(universalRepoDir);
        fs.writeFileSync(path.join(universalRepoDir, 'README.md'), repoReadme);
    }
    
    apps.forEach(appId => {
        const result = standardizeApp(appId);
        if (result?.success) {
            processed++;
        } else if (result?.error) {
            failed++;
        }
    });
    
    console.log(`\n📊 Standardization Complete!`);
    console.log(`   ✅ Success: ${processed}`);
    console.log(`   ❌ Failed: ${failed}`);
    console.log(`   📁 Output: ${universalRepoDir}/`);
    console.log(`\n🚀 Ready to move to new repository!`);
}

module.exports = { standardizeApp };