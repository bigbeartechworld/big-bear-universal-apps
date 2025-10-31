# Universal App Format Schema

This document describes the canonical Universal App Format used in Big Bear Universal Apps.

## Directory Structure

```
big-bear-universal-apps/
├── apps/
│   ├── jellyseerr/
│   │   ├── app.json              # Main metadata and configuration
│   │   ├── docker-compose.yml    # Standard Docker Compose file
│   │   └── README.md             # App-specific documentation (optional)
│   ├── plex/
│   │   ├── app.json
│   │   ├── docker-compose.yml
│   │   └── README.md
│   └── ...
├── schemas/
│   └── app-schema-v1.json        # JSON Schema for validation
├── scripts/
│   ├── convert-to-platforms.sh   # Convert universal → all platforms
│   ├── migrate-from-casaos.sh    # Migrate CasaOS → universal
│   └── validate-apps.sh          # Validate app.json files
└── README.md
```

## app.json Format

The `app.json` file is the source of truth for all app metadata and configuration.

### Example app.json

```json
{
  "spec_version": "1.0",
  "metadata": {
    "id": "jellyseerr",
    "name": "Jellyseerr",
    "description": "Jellyseerr is a free and open source software application for managing requests for your media library. It is a fork of Overseerr built to bring support for Jellyfin & Emby media servers!",
    "tagline": "Media request management for Jellyfin & Emby",
    "version": "2.7.3",
    "author": "BigBearCommunity",
    "developer": "Fallenbagel",
    "category": "Media",
    "license": "MIT",
    "homepage": "https://github.com/Fallenbagel/jellyseerr",
    "source": "big-bear-universal",
    "created": "2024-01-01T00:00:00Z",
    "updated": "2024-10-26T00:00:00Z"
  },
  "visual": {
    "icon": "https://cdn.jsdelivr.net/gh/selfhst/icons/png/jellyseerr.png",
    "thumbnail": "https://cdn.jsdelivr.net/gh/IceWhaleTech/CasaOS-AppStore@main/Apps/Jellyseerr/thumbnail.jpg",
    "screenshots": [],
    "logo": "https://cdn.jsdelivr.net/gh/selfhst/icons/png/jellyseerr.png"
  },
  "resources": {
    "youtube": "",
    "documentation": "https://docs.jellyseerr.dev/",
    "repository": "https://github.com/Fallenbagel/jellyseerr",
    "issues": "https://github.com/Fallenbagel/jellyseerr/issues",
    "support": "https://community.bigbeartechworld.com/"
  },
  "technical": {
    "architectures": ["amd64", "arm64"],
    "platform": "linux",
    "main_service": "app",
    "default_port": "5055",
    "main_image": "fallenbagel/jellyseerr",
    "compose_file": "docker-compose.yml"
  },
  "deployment": {
    "environment_variables": [
      {
        "name": "LOG_LEVEL",
        "default": "debug",
        "description": "Log level for the application",
        "required": false
      },
      {
        "name": "TZ",
        "default": "UTC",
        "description": "Timezone for the application",
        "required": false
      }
    ],
    "volumes": [
      {
        "container": "/app/config",
        "description": "Configuration directory"
      }
    ],
    "ports": [
      {
        "container": "5055",
        "host": "5055",
        "protocol": "tcp",
        "description": "Web UI"
      }
    ]
  },
  "ui": {
    "scheme": "http",
    "path": "",
    "tips": {}
  },
  "compatibility": {
    "casaos": {
      "supported": true,
      "port_map": "5055"
    },
    "portainer": {
      "supported": true,
      "template_type": 2,
      "categories": ["Media", "selfhosted"],
      "administrator_only": false
    },
    "runtipi": {
      "supported": true,
      "tipi_version": 1,
      "supported_architectures": ["amd64", "arm64"]
    },
    "dockge": {
      "supported": true,
      "file_based": true
    },
    "cosmos": {
      "supported": true,
      "servapp": true,
      "routes_required": true
    },
    "umbrel": {
      "supported": true,
      "manifest_version": 1,
      "volume_mappings": {
        "jellyseerr_data_config": "config",
        "jellyseerr_data_cache": "cache/data"
      }
    }
  },
  "tags": [
    "selfhosted",
    "docker",
    "bigbear",
    "media",
    "jellyfin",
    "emby",
    "requests"
  ]
}
```

## docker-compose.yml Format

The `docker-compose.yml` file should be a **clean, standard Docker Compose file** without any platform-specific extensions (no x-casaos, no custom labels, etc.).

### Example docker-compose.yml

```yaml
name: jellyseerr

services:
  app:
    image: fallenbagel/jellyseerr:2.7.3
    container_name: jellyseerr
    ports:
      - "5055:5055"
    volumes:
      - ./config:/app/config
    environment:
      - LOG_LEVEL=debug
      - TZ=UTC
    restart: unless-stopped
    network_mode: bridge
```

### Key Principles

1. **Clean and Standard**: No platform-specific extensions
2. **Portable**: Works with standard Docker Compose
3. **Relative Paths**: Use relative paths for volumes (e.g., `./config`)
4. **Explicit Versions**: Always specify image versions
5. **Container Names**: Include container names for clarity

## Conversion Process

The universal format is converted to platform-specific formats:

### CasaOS
- Adds `x-casaos` extensions to docker-compose.yml
- Creates config.json with version info
- Adjusts volume paths to `/DATA/AppData/$AppID/`

### Portainer
- Creates templates.json with all app metadata
- Converts environment variables to Portainer format
- Adds categories and descriptions

### Runtipi
- Creates config.json with app metadata
- Creates docker-compose.json with dynamic configuration
- Converts volumes to named volumes with app prefix
- Downloads/converts icon to logo.jpg

### Dockge
- Uses clean docker-compose.yml
- Creates metadata.json with app info

### Cosmos
- Creates cosmos-compose.json with routes
- Creates description.json with metadata

### Umbrel
- Creates umbrel-app.yml manifest
- Uses clean docker-compose.yml
- Adds gallery images and icon
- Supports volume mapping overrides via `compatibility.umbrel.volume_mappings`

#### Volume Mapping Overrides

By default, named volumes are converted automatically:
- App name prefix is removed: `jellyseerr_data` → `data`
- Underscores become slashes: `data_config` → `data/config`

To preserve specific paths for backward compatibility, add volume mapping overrides:

```json
"compatibility": {
  "umbrel": {
    "supported": true,
    "manifest_version": 1,
    "volume_mappings": {
      "appname_data_config": "config",
      "appname_media_movies": "media/movies",
      "appname_cache": "data/cache"
    }
  }
}
```

**Use cases for overrides:**
- Migrating existing apps with established data paths
- Complex multi-level directory structures
- When automatic conversion produces unexpected paths
- Ensuring exact path compatibility with existing Umbrel deployments

#### Port Override Support

By default, all platforms use the port specified in `technical.default_port`. However, you can override the port for specific platforms to maintain backward compatibility with existing deployments:

```json
"compatibility": {
  "casaos": {
    "supported": true,
    "port": "3000"
  },
  "runtipi": {
    "supported": true,
    "port": "3000"
  },
  "umbrel": {
    "supported": true,
    "port": "10123"
  },
  "cosmos": {
    "supported": true,
    "port": "8080"
  }
}
```

**Platform-specific behavior:**
- **CasaOS**: Uses `port` value directly for `port_map` in x-casaos metadata
- **Runtipi**: Uses `port` value, but still remaps ports < 1000 (e.g., 80 → 8080)
- **Umbrel**: Uses `port` value and skips automatic 10000+ remapping
- **Cosmos**: Uses `port` value in route target URLs
- **Portainer/Dockge**: Uses `port` value in templates

**Use cases for port overrides:**
- Preserving existing port assignments when migrating to universal format
- Avoiding port conflicts across different platforms
- Meeting platform-specific port requirements (e.g., Umbrel 10000+ range)
- Maintaining consistency with existing user deployments

## Validation

Apps can be validated using JSON Schema validation against `schemas/app-schema-v1.json`.

Required validations:
- ✅ Valid JSON syntax
- ✅ Required fields present
- ✅ Version format matches semver
- ✅ URLs are valid
- ✅ Architectures are valid values
- ✅ docker-compose.yml exists and is valid YAML

