#!/bin/bash

# Big Bear Universal Apps - Platform Converter
# Converts Universal App format to multiple platform formats
# Supports: CasaOS, Portainer, Runtipi, Dockge, Cosmos, Umbrel

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print colored output
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Default configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNIVERSAL_REPO="$(dirname "$SCRIPT_DIR")"
APPS_DIR="$UNIVERSAL_REPO/apps"
OUTPUT_DIR="$UNIVERSAL_REPO/converted"
PLATFORMS=("casaos" "portainer" "runtipi" "dockge" "cosmos" "umbrel")

# Variables
SPECIFIC_APP=""
DRY_RUN=false
VERBOSE=false
VALIDATE=false

# Counters
TOTAL_CONVERTED=0
TOTAL_SKIPPED=0
TOTAL_ERRORS=0

# Usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Convert Universal App format to multiple platform formats.

OPTIONS:
    -h, --help              Show this help message
    -i, --input DIR         Input directory containing universal apps (default: ./apps)
    -o, --output DIR        Output directory for converted apps (default: ./converted)
    -p, --platforms LIST    Comma-separated list of platforms to convert to
                           Available: casaos,portainer,runtipi,dockge,cosmos,umbrel (default: all)
    -a, --app NAME          Convert specific app only
    --dry-run              Show what would be converted without actually converting
    --validate             Validate existing conversions
    -v, --verbose          Verbose output

EXAMPLES:
    $0                                    # Convert all apps to all platforms
    $0 -p casaos,portainer               # Convert to CasaOS and Portainer only
    $0 -a jellyseerr                     # Convert only jellyseerr app
    $0 --dry-run                         # Preview conversion without changes

REPOSITORY STRUCTURE:
    big-bear-universal-apps/
    ├── apps/
    │   ├── jellyseerr/
    │   │   ├── app.json
    │   │   └── docker-compose.yml
    │   └── ...
    ├── converted/
    │   ├── casaos/
    │   ├── portainer/
    │   ├── runtipi/
    │   ├── dockge/
    │   ├── cosmos/
    │   └── umbrel/
    └── scripts/
        └── convert-to-platforms.sh (this script)

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -i|--input)
            APPS_DIR="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -p|--platforms)
            IFS=',' read -ra PLATFORMS <<< "$2"
            shift 2
            ;;
        -a|--app)
            SPECIFIC_APP="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --validate)
            VALIDATE=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        *)
            print_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Check dependencies
check_dependencies() {
    local deps=("jq" "yq")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        print_error "Missing required dependencies: ${missing[*]}"
        print_info "Install missing dependencies:"
        for dep in "${missing[@]}"; do
            case "$dep" in
                jq)
                    print_info "  - jq: apt-get install jq  # or brew install jq"
                    ;;
                yq)
                    print_info "  - yq: brew install yq  # or wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64"
                    ;;
            esac
        done
        exit 1
    fi
    
    # Check for optional image conversion tools
    local has_image_converter=false
    if command -v convert &> /dev/null; then
        has_image_converter=true
    elif command -v ffmpeg &> /dev/null; then
        has_image_converter=true
    elif command -v sips &> /dev/null; then
        has_image_converter=true
    fi
    
    if [[ "$has_image_converter" == "false" ]]; then
        print_warning "No image conversion tool found (ImageMagick, ffmpeg, or sips)"
        print_info "Install ImageMagick: apt-get install imagemagick  # or brew install imagemagick"
    fi
}

# Initialize output directories
init_directories() {
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "DRY RUN: Would create output directories"
        return
    fi
    
    mkdir -p "$OUTPUT_DIR"
    for platform in "${PLATFORMS[@]}"; do
        mkdir -p "$OUTPUT_DIR/$platform"
        if [[ "$platform" == "portainer" ]]; then
            # Initialize Portainer master template
            init_portainer_master_template
        fi
    done
    print_success "Created output directories in $OUTPUT_DIR"
}

# Load metadata from app.json
load_app_metadata() {
    local app_dir="$1"
    local app_json="$app_dir/app.json"
    
    if [[ ! -f "$app_json" ]]; then
        print_error "app.json not found in $app_dir"
        return 1
    fi
    
    # Validate JSON syntax
    if ! jq empty "$app_json" 2>/dev/null; then
        print_error "Invalid JSON in $app_json"
        return 1
    fi
    
    # Extract all metadata fields into environment variables
    export APP_ID=$(jq -r '.metadata.id' "$app_json")
    export APP_NAME=$(jq -r '.metadata.name' "$app_json")
    export APP_DESCRIPTION=$(jq -r '.metadata.description // ""' "$app_json")
    export APP_TAGLINE=$(jq -r '.metadata.tagline // ""' "$app_json")
    export APP_VERSION=$(jq -r '.metadata.version' "$app_json")
    export APP_AUTHOR=$(jq -r '.metadata.author // "BigBearCommunity"' "$app_json")
    export APP_DEVELOPER=$(jq -r '.metadata.developer // ""' "$app_json")
    export APP_CATEGORY=$(jq -r '.metadata.category // "Other"' "$app_json")
    export APP_LICENSE=$(jq -r '.metadata.license // ""' "$app_json")
    export APP_HOMEPAGE=$(jq -r '.metadata.homepage // ""' "$app_json")
    
    export APP_ICON=$(jq -r '.visual.icon // ""' "$app_json")
    export APP_THUMBNAIL=$(jq -r '.visual.thumbnail // ""' "$app_json")
    export APP_LOGO=$(jq -r '.visual.logo // ""' "$app_json")
    
    export APP_YOUTUBE=$(jq -r '.resources.youtube // ""' "$app_json")
    export APP_DOCS=$(jq -r '.resources.documentation // ""' "$app_json")
    export APP_REPOSITORY=$(jq -r '.resources.repository // ""' "$app_json")
    export APP_ISSUES=$(jq -r '.resources.issues // ""' "$app_json")
    export APP_SUPPORT=$(jq -r '.resources.support // ""' "$app_json")
    
    export APP_ARCHITECTURES=$(jq -c '.technical.architectures // ["amd64", "arm64"]' "$app_json")
    export APP_MAIN_SERVICE=$(jq -r '.technical.main_service // "app"' "$app_json")
    export APP_DEFAULT_PORT=$(jq -r '.technical.default_port // "8080"' "$app_json")
    export APP_MAIN_IMAGE=$(jq -r '.technical.main_image' "$app_json")
    export APP_COMPOSE_FILE=$(jq -r '.technical.compose_file // "docker-compose.yml"' "$app_json")
    
    export APP_ENV_VARS=$(jq -c '.deployment.environment_variables // []' "$app_json")
    export APP_VOLUMES=$(jq -c '.deployment.volumes // []' "$app_json")
    export APP_PORTS=$(jq -c '.deployment.ports // []' "$app_json")
    
    export APP_UI_SCHEME=$(jq -r '.ui.scheme // "http"' "$app_json")
    export APP_UI_PATH=$(jq -r '.ui.path // ""' "$app_json")
    export APP_TIPS=$(jq -c '.ui.tips // {}' "$app_json")
    
    export APP_TAGS=$(jq -c '.tags // []' "$app_json")
    
    # Platform compatibility flags
    export COMPAT_CASAOS=$(jq -r '.compatibility.casaos.supported // true' "$app_json")
    export COMPAT_PORTAINER=$(jq -r '.compatibility.portainer.supported // true' "$app_json")
    export COMPAT_RUNTIPI=$(jq -r '.compatibility.runtipi.supported // true' "$app_json")
    export COMPAT_DOCKGE=$(jq -r '.compatibility.dockge.supported // true' "$app_json")
    export COMPAT_COSMOS=$(jq -r '.compatibility.cosmos.supported // true' "$app_json")
    export COMPAT_UMBREL=$(jq -r '.compatibility.umbrel.supported // true' "$app_json")
}

# Initialize Portainer master template file
init_portainer_master_template() {
    local master_file="$OUTPUT_DIR/portainer/templates.json"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        return
    fi
    
    cat > "$master_file" << 'EOF'
{
  "version": "3",
  "templates": [
EOF
    
    echo "1" > "$OUTPUT_DIR/portainer/.template_id_counter"
}

# Finalize Portainer master template file
finalize_portainer_master_template() {
    local master_file="$OUTPUT_DIR/portainer/templates.json"
    
    if [[ "$DRY_RUN" == "true" ]] || [[ ! -f "$master_file" ]]; then
        return
    fi
    
    # Remove trailing comma from last entry and close JSON
    sed -i.bak '$ s/,$//' "$master_file"
    cat >> "$master_file" << 'EOF'
  ]
}
EOF
    rm -f "${master_file}.bak"
    print_success "Finalized Portainer master template"
}

# Create a placeholder logo.jpg image
create_placeholder_logo() {
    local output_file="$1"
    
    if command -v convert &> /dev/null; then
        convert -size 512x512 xc:gray "$output_file" 2>/dev/null || touch "$output_file"
    else
        touch "$output_file"
    fi
}

# Validate app directory and files
validate_app() {
    local app_name="$1"
    local app_dir="$APPS_DIR/$app_name"
    
    if [[ ! -d "$app_dir" ]]; then
        print_error "App directory not found: $app_dir"
        return 1
    fi
    
    if [[ ! -f "$app_dir/app.json" ]]; then
        print_error "app.json not found for $app_name"
        return 1
    fi
    
    if [[ ! -f "$app_dir/docker-compose.yml" ]]; then
        print_error "docker-compose.yml not found for $app_name"
        return 1
    fi
    
    # Validate JSON syntax
    if ! jq empty "$app_dir/app.json" 2>/dev/null; then
        print_error "Invalid JSON in app.json for $app_name"
        return 1
    fi
    
    return 0
}

# Helper function to adjust docker-compose for platform-specific needs
adjust_compose_for_platform() {
    local input_file="$1"
    local output_file="$2"
    local platform="$3"
    local app_name="$4"
    
    case "$platform" in
        casaos)
            # Copy compose and add x-casaos sections
            cp "$input_file" "$output_file"
            # Will add x-casaos extensions in convert_to_casaos function
            ;;
        portainer)
            # Convert to named volumes for Portainer
            yq eval '.services[] |= (
                if .volumes then
                    .volumes |= map(
                        if (. | type) == "!!str" and (. | test("^\\./")) then
                            ("'$app_name'_" + (. | sub("^\\./", "") | sub("/", "_")) + ":" + (. | split(":")[1]))
                        else
                            .
                        end
                    )
                else
                    .
                end
            )' "$input_file" > "$output_file"
            # Add volumes section
            local volumes_section=$(yq eval '.services[].volumes[]?' "$output_file" | \
                grep -E '^[a-zA-Z0-9_-]+:' | cut -d':' -f1 | sort -u | \
                awk '{print "  " $1 ": {}"}')
            if [[ -n "$volumes_section" ]]; then
                yq eval ".volumes = {}" -i "$output_file"
                while IFS= read -r vol; do
                    vol_name=$(echo "$vol" | xargs | cut -d':' -f1)
                    yq eval ".volumes.\"$vol_name\" = {}" -i "$output_file"
                done <<< "$volumes_section"
            fi
            ;;
        runtipi)
            # Copy compose, add runtipi.managed label and tipi_main_network
            cp "$input_file" "$output_file"
            # Will be modified in convert_to_runtipi function
            ;;
        dockge|cosmos|umbrel)
            # Use clean compose as-is
            cp "$input_file" "$output_file"
            ;;
    esac
}

# Convert to CasaOS format
convert_to_casaos() {
    local app_name="$1"
    local app_dir="$2"
    local output_dir="$OUTPUT_DIR/casaos/$app_name"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "DRY RUN: Would convert $app_name to CasaOS format"
        return
    fi
    
    if [[ "$COMPAT_CASAOS" != "true" ]]; then
        print_warning "Skipping $app_name for CasaOS (not marked as compatible)"
        return
    fi
    
    mkdir -p "$output_dir"
    load_app_metadata "$app_dir"
    
    # Start with clean compose
    cp "$app_dir/docker-compose.yml" "$output_dir/docker-compose.yml"
    local compose_file="$output_dir/docker-compose.yml"
    
    # Add x-casaos sections to compose file
    # Add top-level x-casaos
    yq eval ".x-casaos.architectures = $APP_ARCHITECTURES" -i "$compose_file"
    yq eval ".x-casaos.main = \"$APP_MAIN_SERVICE\"" -i "$compose_file"
    yq eval ".x-casaos.description.en_us = \"$APP_DESCRIPTION\"" -i "$compose_file"
    yq eval ".x-casaos.tagline.en_us = \"$APP_TAGLINE\"" -i "$compose_file"
    yq eval ".x-casaos.developer = \"$APP_DEVELOPER\"" -i "$compose_file"
    yq eval ".x-casaos.author = \"$APP_AUTHOR\"" -i "$compose_file"
    yq eval ".x-casaos.icon = \"$APP_ICON\"" -i "$compose_file"
    yq eval ".x-casaos.thumbnail = \"$APP_THUMBNAIL\"" -i "$compose_file"
    yq eval ".x-casaos.title.en_us = \"$APP_NAME\"" -i "$compose_file"
    yq eval ".x-casaos.category = \"$APP_CATEGORY\"" -i "$compose_file"
    yq eval ".x-casaos.port_map = \"$APP_DEFAULT_PORT\"" -i "$compose_file"
    
    # Add service-level x-casaos for environment variables
    local env_count=$(echo "$APP_ENV_VARS" | jq 'length')
    for ((i=0; i<env_count; i++)); do
        local env_name=$(echo "$APP_ENV_VARS" | jq -r ".[$i].name")
        local env_desc=$(echo "$APP_ENV_VARS" | jq -r ".[$i].description")
        yq eval ".services.$APP_MAIN_SERVICE.x-casaos.envs[$i].container = \"$env_name\"" -i "$compose_file"
        yq eval ".services.$APP_MAIN_SERVICE.x-casaos.envs[$i].description.en_us = \"$env_desc\"" -i "$compose_file"
    done
    
    # Add volume descriptions
    local vol_count=$(echo "$APP_VOLUMES" | jq 'length')
    for ((i=0; i<vol_count; i++)); do
        local vol_path=$(echo "$APP_VOLUMES" | jq -r ".[$i].container")
        local vol_desc=$(echo "$APP_VOLUMES" | jq -r ".[$i].description")
        yq eval ".services.$APP_MAIN_SERVICE.x-casaos.volumes[$i].container = \"$vol_path\"" -i "$compose_file"
        yq eval ".services.$APP_MAIN_SERVICE.x-casaos.volumes[$i].description.en_us = \"$vol_desc\"" -i "$compose_file"
    done
    
    # Add port descriptions
    local port_count=$(echo "$APP_PORTS" | jq 'length')
    for ((i=0; i<port_count; i++)); do
        local port_num=$(echo "$APP_PORTS" | jq -r ".[$i].container")
        local port_desc=$(echo "$APP_PORTS" | jq -r ".[$i].description")
        yq eval ".services.$APP_MAIN_SERVICE.x-casaos.ports[$i].container = \"$port_num\"" -i "$compose_file"
        yq eval ".services.$APP_MAIN_SERVICE.x-casaos.ports[$i].description.en_us = \"$port_desc\"" -i "$compose_file"
    done
    
    # Adjust volume paths for CasaOS
    yq eval '.services[] |= (
        if .volumes then
            .volumes |= map(
                if (. | type) == "!!str" and (. | test("^\\./")) then
                    ("/DATA/AppData/$AppID/" + (. | sub("^\\./", "")) + ":" + (. | split(":")[1]))
                else
                    .
                end
            )
        else
            .
        end
    )' -i "$compose_file"
    
    # Create config.json for CasaOS
    cat > "$output_dir/config.json" << EOF
{
  "id": "$APP_ID",
  "version": "$APP_VERSION",
  "image": "$APP_MAIN_IMAGE",
  "youtube": "$APP_YOUTUBE",
  "docs_link": "$APP_DOCS"
}
EOF
    
    print_success "Converted $app_name for CasaOS"
}

# Convert to Portainer format
convert_to_portainer() {
    local app_name="$1"
    local app_dir="$2"
    local output_dir="$OUTPUT_DIR/portainer/$app_name"
    local master_file="$OUTPUT_DIR/portainer/templates.json"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "DRY RUN: Would convert $app_name to Portainer format"
        return
    fi
    
    if [[ "$COMPAT_PORTAINER" != "true" ]]; then
        print_warning "Skipping $app_name for Portainer (not marked as compatible)"
        return
    fi
    
    mkdir -p "$output_dir"
    load_app_metadata "$app_dir"
    
    # Create docker-compose with named volumes
    adjust_compose_for_platform "$app_dir/docker-compose.yml" "$output_dir/docker-compose.yml" "portainer" "$app_name"
    
    # Get template ID
    local template_id
    if [[ -f "$OUTPUT_DIR/portainer/.template_id_counter" ]]; then
        template_id=$(cat "$OUTPUT_DIR/portainer/.template_id_counter")
        echo $((template_id + 1)) > "$OUTPUT_DIR/portainer/.template_id_counter"
    else
        template_id=1
        echo "2" > "$OUTPUT_DIR/portainer/.template_id_counter"
    fi
    
    # Escape JSON strings
    local title_json="${APP_NAME//\"/\\\"}"
    local desc_json="${APP_DESCRIPTION//\"/\\\"}"
    local tag_json="${APP_TAGLINE//\"/\\\"}"
    
    # Build environment variables JSON
    local env_json=""
    local env_count=$(echo "$APP_ENV_VARS" | jq 'length')
    for ((i=0; i<env_count; i++)); do
        local env_name=$(echo "$APP_ENV_VARS" | jq -r ".[$i].name")
        local env_default=$(echo "$APP_ENV_VARS" | jq -r ".[$i].default // \"\"")
        local env_desc=$(echo "$APP_ENV_VARS" | jq -r ".[$i].description")
        env_default="${env_default//\\/\\\\}"
        env_default="${env_default//\"/\\\"}"
        env_desc="${env_desc//\"/\\\"}"
        
        if [[ $i -gt 0 ]]; then
            env_json+=",
"
        fi
        env_json+="        {\"name\": \"$env_name\", \"label\": \"$env_name\", \"description\": \"$env_desc\", \"default\": \"$env_default\"}"
    done
    
    # Create template entry
    local template_entry=$(cat << EOF
    {
      "id": $template_id,
      "type": 3,
      "title": "$title_json",
      "name": "$APP_ID",
      "description": "$desc_json",
      "note": "$tag_json",
      "categories": ["$APP_CATEGORY", "selfhosted"],
      "platform": "linux",
      "logo": "$APP_ICON",
      "repository": {
        "url": "https://github.com/bigbeartechworld/big-bear-portainer",
        "stackfile": "Apps/$app_name/docker-compose.yml"
      }$(if [[ -n "$env_json" ]]; then echo ",
      \"env\": [
$env_json
      ]"; fi)
    }
EOF
)
    
    # Save individual template
    echo "{\"version\": \"3\", \"templates\": [$template_entry]}" > "$output_dir/template.json"
    
    # Append to master template
    echo "$template_entry," >> "$master_file"
    
    print_success "Converted $app_name for Portainer"
}

# Convert to Runtipi format
convert_to_runtipi() {
    local app_name="$1"
    local app_dir="$2"
    local output_dir="$OUTPUT_DIR/runtipi/$app_name"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "DRY RUN: Would convert $app_name to Runtipi format"
        return
    fi
    
    if [[ "$COMPAT_RUNTIPI" != "true" ]]; then
        print_warning "Skipping $app_name for Runtipi (not marked as compatible)"
        return
    fi
    
    mkdir -p "$output_dir/metadata"
    load_app_metadata "$app_dir"
    
    # Copy and modify docker-compose
    cp "$app_dir/docker-compose.yml" "$output_dir/docker-compose.yml"
    local compose_file="$output_dir/docker-compose.yml"
    
    # Rename main service to app_name
    local services=$(yq eval '.services | keys | .[0]' "$compose_file")
    if [[ "$services" != "$app_name" ]]; then
        yq eval ".services.\"$app_name\" = .services.\"$services\" | del(.services.\"$services\")" -i "$compose_file"
    fi
    
    # Set container name
    yq eval ".services[\"$app_name\"].container_name = \"$app_name\"" -i "$compose_file"
    
    # Add runtipi.managed label
    yq eval ".services[\"$app_name\"].labels.\"runtipi.managed\" = \"true\"" -i "$compose_file"
    
    # Add tipi_main_network (skip for certain apps)
    local network_exceptions=("pihole" "tailscale" "homeassistant" "plex")
    local skip_network=false
    for exception in "${network_exceptions[@]}"; do
        if [[ "$app_name" == "$exception" ]]; then
            skip_network=true
            break
        fi
    done
    
    if [[ "$skip_network" == "false" ]]; then
        yq eval ".services[\"$app_name\"].networks = [\"tipi_main_network\"]" -i "$compose_file"
        yq eval '.networks.tipi_main_network.external = true' -i "$compose_file"
    fi
    
    # Determine port
    local runtipi_port="$APP_DEFAULT_PORT"
    if [[ "$runtipi_port" -le 999 ]]; then
        case "$runtipi_port" in
            80) runtipi_port=8080 ;;
            443) runtipi_port=8443 ;;
            *) runtipi_port=$((runtipi_port + 8000)) ;;
        esac
    fi
    
    # Create docker-compose.json
    cat > "$output_dir/docker-compose.json" << EOF
{
  "schemaVersion": 2,
  "services": [
    {
      "name": "$app_name",
      "image": "$APP_MAIN_IMAGE:$APP_VERSION",
      "internalPort": $runtipi_port,
      "isMain": true
    }
  ]
}
EOF
    
    # Escape strings for JSON
    local desc_escaped="${APP_DESCRIPTION//\\/\\\\}"
    desc_escaped="${desc_escaped//\"/\\\"}"
    desc_escaped="${desc_escaped//$'\n'/\\n}"
    
    local tag_escaped="${APP_TAGLINE//\\/\\\\}"
    tag_escaped="${tag_escaped//\"/\\\"}"
    
    # Create config.json
    local current_timestamp=$(($(date +%s) * 1000))
    cat > "$output_dir/config.json" << EOF
{
  "name": "$APP_NAME",
  "available": true,
  "port": $runtipi_port,
  "exposable": true,
  "dynamic_config": true,
  "id": "$APP_ID",
  "description": "$desc_escaped",
  "tipi_version": 1,
  "version": "$APP_VERSION",
  "categories": ["$(echo "$APP_CATEGORY" | tr '[:upper:]' '[:lower:]')"],
  "short_desc": "$tag_escaped",
  "author": "$APP_DEVELOPER",
  "source": "$APP_REPOSITORY",
  "website": "$APP_HOMEPAGE",
  "supported_architectures": $(echo "$APP_ARCHITECTURES" | jq -c '.'),
  "created_at": $current_timestamp,
  "updated_at": $current_timestamp,
  "\$schema": "../app-info-schema.json",
  "min_tipi_version": "4.5.0"
}
EOF
    
    # Create description
    echo "$APP_DESCRIPTION" > "$output_dir/metadata/description.md"
    
    # Download and convert icon
    if [[ -n "$APP_ICON" ]]; then
        if curl -fsSL "$APP_ICON" -o "$output_dir/metadata/logo_temp" 2>/dev/null; then
            if command -v convert &> /dev/null; then
                convert "$output_dir/metadata/logo_temp" "$output_dir/metadata/logo.jpg" 2>/dev/null
                rm -f "$output_dir/metadata/logo_temp"
            else
                mv "$output_dir/metadata/logo_temp" "$output_dir/metadata/logo.jpg"
            fi
        else
            create_placeholder_logo "$output_dir/metadata/logo.jpg"
        fi
    else
        create_placeholder_logo "$output_dir/metadata/logo.jpg"
    fi
    
    print_success "Converted $app_name for Runtipi"
}

# Convert to Dockge format
convert_to_dockge() {
    local app_name="$1"
    local app_dir="$2"
    local output_dir="$OUTPUT_DIR/dockge/$app_name"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "DRY RUN: Would convert $app_name to Dockge format"
        return
    fi
    
    if [[ "$COMPAT_DOCKGE" != "true" ]]; then
        print_warning "Skipping $app_name for Dockge (not marked as compatible)"
        return
    fi
    
    mkdir -p "$output_dir"
    load_app_metadata "$app_dir"
    
    # Copy compose as-is
    cp "$app_dir/docker-compose.yml" "$output_dir/compose.yaml"
    
    # Create metadata.json
    cat > "$output_dir/metadata.json" << EOF
{
  "name": "$APP_NAME",
  "description": "$APP_DESCRIPTION",
  "version": "$APP_VERSION",
  "author": "$APP_AUTHOR",
  "icon": "$APP_ICON",
  "category": "$APP_CATEGORY",
  "port": "$APP_DEFAULT_PORT",
  "documentation": "$APP_DOCS",
  "source": "$APP_REPOSITORY"
}
EOF
    
    print_success "Converted $app_name for Dockge"
}

# Convert to Cosmos format
convert_to_cosmos() {
    local app_name="$1"
    local app_dir="$2"
    local output_dir="$OUTPUT_DIR/cosmos/$app_name"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "DRY RUN: Would convert $app_name to Cosmos format"
        return
    fi
    
    if [[ "$COMPAT_COSMOS" != "true" ]]; then
        print_warning "Skipping $app_name for Cosmos (not marked as compatible)"
        return
    fi
    
    mkdir -p "$output_dir"
    load_app_metadata "$app_dir"
    
    # Create cosmos-compose.json with routes
    local routes=""
    if [[ -n "$APP_DEFAULT_PORT" ]]; then
        routes="\"routes\": [
        {
          \"name\": \"$APP_NAME\",
          \"description\": \"Web UI\",
          \"useHost\": true,
          \"target\": \"http://$app_name:$APP_DEFAULT_PORT\",
          \"mode\": \"SERVAPP\",
          \"Timeout\": 14400000,
          \"ThrottlePerMinute\": 12000,
          \"BlockCommonBots\": true,
          \"BlockAPIAbuse\": true
        }
      ],"
    fi
    
    cat > "$output_dir/cosmos-compose.json" << EOF
{
  "cosmos-installer": {
    $routes
    "services": {
      "$app_name": "$(jq -c ".services.$APP_MAIN_SERVICE // .services | to_entries[0].value" "$app_dir/docker-compose.yml")"
    }
  }
}
EOF
    
    # Create description.json
    cat > "$output_dir/description.json" << EOF
{
  "name": "$APP_NAME",
  "description": "$APP_DESCRIPTION",
  "url": "$APP_HOMEPAGE",
  "longDescription": "$APP_DESCRIPTION",
  "tags": $(echo "$APP_TAGS" | jq -c '.')
}
EOF
    
    print_success "Converted $app_name for Cosmos"
}

# Convert to Umbrel format
convert_to_umbrel() {
    local app_name="$1"
    local app_dir="$2"
    local output_dir="$OUTPUT_DIR/umbrel/$app_name"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "DRY RUN: Would convert $app_name to Umbrel format"
        return
    fi
    
    if [[ "$COMPAT_UMBREL" != "true" ]]; then
        print_warning "Skipping $app_name for Umbrel (not marked as compatible)"
        return
    fi
    
    mkdir -p "$output_dir"
    load_app_metadata "$app_dir"
    
    # Copy compose
    cp "$app_dir/docker-compose.yml" "$output_dir/docker-compose.yml"
    
    # Create umbrel-app.yml
    cat > "$output_dir/umbrel-app.yml" << EOF
manifestVersion: 1
id: $APP_ID
category: $APP_CATEGORY
name: $APP_NAME
version: "$APP_VERSION"
tagline: $APP_TAGLINE
description: >-
  $APP_DESCRIPTION
releaseNotes: >-
  This version includes various improvements and bug fixes.
developer: $APP_DEVELOPER
website: $APP_HOMEPAGE
dependencies: []
repo: https://github.com/bigbeartechworld/big-bear-universal-apps
support: https://github.com/bigbeartechworld/big-bear-universal-apps/issues
port: $APP_DEFAULT_PORT
gallery:
  - 1.jpg
  - 2.jpg
  - 3.jpg
path: ""
defaultUsername: ""
defaultPassword: ""
icon: $APP_ICON
submitter: BigBearTechWorld
submission: https://github.com/bigbeartechworld/big-bear-universal-apps
EOF
    
    # Create placeholder gallery images
    for i in 1 2 3; do
        create_placeholder_logo "$output_dir/$i.jpg"
    done
    
    print_success "Converted $app_name for Umbrel"
}

# Convert a single app to all platforms
convert_app() {
    local app_name="$1"
    local app_dir="$APPS_DIR/$app_name"
    
    if ! validate_app "$app_name"; then
        TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
        return 1
    fi
    
    print_info "Converting $app_name..."
    
    # Convert to each platform
    for platform in "${PLATFORMS[@]}"; do
        case "$platform" in
            casaos)
                convert_to_casaos "$app_name" "$app_dir"
                ;;
            portainer)
                convert_to_portainer "$app_name" "$app_dir"
                ;;
            runtipi)
                convert_to_runtipi "$app_name" "$app_dir"
                ;;
            dockge)
                convert_to_dockge "$app_name" "$app_dir"
                ;;
            cosmos)
                convert_to_cosmos "$app_name" "$app_dir"
                ;;
            umbrel)
                convert_to_umbrel "$app_name" "$app_dir"
                ;;
            *)
                print_warning "Unknown platform: $platform"
                ;;
        esac
    done
    
    TOTAL_CONVERTED=$((TOTAL_CONVERTED + 1))
}

# Print summary
print_summary() {
    echo ""
    echo "========================================"
    echo "       CONVERSION SUMMARY"
    echo "========================================"
    echo -e "${GREEN}Converted:${NC} $TOTAL_CONVERTED apps"
    echo -e "${YELLOW}Skipped:${NC}   $TOTAL_SKIPPED apps"
    echo -e "${RED}Errors:${NC}    $TOTAL_ERRORS apps"
    echo "========================================"
    echo ""
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "This was a dry run. Use without --dry-run to apply changes."
    fi
}

# Main function
main() {
    echo ""
    echo "========================================"
    echo "  Universal to Platform Converter"
    echo "========================================"
    echo ""
    
    print_info "Input directory:  $APPS_DIR"
    print_info "Output directory: $OUTPUT_DIR"
    print_info "Platforms:        ${PLATFORMS[*]}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_warning "DRY RUN MODE - No changes will be made"
    fi
    
    echo ""
    
    # Check dependencies
    check_dependencies
    
    # Initialize directories
    init_directories
    
    # Convert apps
    if [[ -n "$SPECIFIC_APP" ]]; then
        convert_app "$SPECIFIC_APP"
    else
        while IFS= read -r -d '' app_dir; do
            app_name=$(basename "$app_dir")
            convert_app "$app_name"
        done < <(find "$APPS_DIR" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)
    fi
    
    # Finalize platform-specific files
    if [[ " ${PLATFORMS[*]} " =~ " portainer " ]]; then
        finalize_portainer_master_template
    fi
    
    # Print summary
    print_summary
    
    # Exit with error if there were errors
    if [[ $TOTAL_ERRORS -gt 0 ]]; then
        exit 1
    fi
}

# Run main
main "$@"
