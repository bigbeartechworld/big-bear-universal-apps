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
    local deps=("jq" "yq" "perl")
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
                perl)
                    print_info "  - perl: apt-get install perl  # or brew install perl (usually pre-installed)"
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
    
    # Platform-specific port overrides
    export PORT_CASAOS=$(jq -r '.compatibility.casaos.port // empty' "$app_json")
    export PORT_PORTAINER=$(jq -r '.compatibility.portainer.port // empty' "$app_json")
    export PORT_RUNTIPI=$(jq -r '.compatibility.runtipi.port // empty' "$app_json")
    export PORT_DOCKGE=$(jq -r '.compatibility.dockge.port // empty' "$app_json")
    export PORT_COSMOS=$(jq -r '.compatibility.cosmos.port // empty' "$app_json")
    export PORT_UMBREL=$(jq -r '.compatibility.umbrel.port // empty' "$app_json")
    export COMPAT_UMBREL=$(jq -r '.compatibility.umbrel.supported // true' "$app_json")
}

# Get folder name for a specific platform (with override support)
get_platform_folder_name() {
    local app_dir="$1"
    local platform="$2"
    local app_json="$app_dir/app.json"
    
    # Try to get platform-specific folder_name override
    local folder_name=$(jq -r ".compatibility.$platform.folder_name // empty" "$app_json" 2>/dev/null)
    
    # If no override, use the app ID
    if [[ -z "$folder_name" ]]; then
        folder_name=$(jq -r '.metadata.id' "$app_json")
    fi
    
    echo "$folder_name"
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
        portainer|dockge|cosmos)
            # Copy the compose file and add big-bear- prefix to volume names
            cp "$input_file" "$output_file"
            add_bigbear_volume_prefix "$output_file"
            ;;
        runtipi)
            # Copy compose, add runtipi.managed label and tipi_main_network
            cp "$input_file" "$output_file"
            # Will be modified in convert_to_runtipi function
            ;;
        umbrel)
            # Use clean compose as-is
            cp "$input_file" "$output_file"
            ;;
    esac
}

# Add big-bear- prefix to all named volumes
add_bigbear_volume_prefix() {
    local compose_file="$1"
    
    # Get list of named volumes
    local volume_names=$(yq eval '.volumes | keys | .[]' "$compose_file" 2>/dev/null || echo "")
    
    if [[ -z "$volume_names" ]]; then
        return
    fi
    
    # For each volume, add big-bear- prefix using sed
    while IFS= read -r vol_name; do
        [[ -z "$vol_name" ]] && continue
        
        local new_vol_name="big-bear-${vol_name}"
        
        # Use sed to replace all occurrences
        # 1. Replace in volumes section keys
        sed -i.bak "s/^  ${vol_name}:/  ${new_vol_name}:/g" "$compose_file"
        # 2. Replace volume name values
        sed -i.bak "s/name: ${vol_name}$/name: ${new_vol_name}/g" "$compose_file"
        # 3. Replace in service volume references (short form: - vol_name:)
        sed -i.bak "s/- ${vol_name}:/- ${new_vol_name}:/g" "$compose_file"
        # 4. Replace in service volume references (long form: source: vol_name)
        sed -i.bak "s/source: ${vol_name}$/source: ${new_vol_name}/g" "$compose_file"
        
        rm -f "$compose_file.bak"
    done <<< "$volume_names"
}

# Convert to CasaOS format
convert_to_casaos() {
    local app_name="$1"
    local app_dir="$2"
    
    local folder_name=$(get_platform_folder_name "$app_dir" "casaos")
    local output_dir="$OUTPUT_DIR/casaos/$folder_name"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "DRY RUN: Would convert $app_name to CasaOS format (folder: $folder_name)"
        return
    fi
    
    mkdir -p "$output_dir"
    
    # Start with clean compose
    cp "$app_dir/docker-compose.yml" "$output_dir/docker-compose.yml"
    local compose_file="$output_dir/docker-compose.yml"
    
    # Update the name to include big-bear- prefix for CasaOS
    local current_name=$(yq eval '.name' "$compose_file")
    if [[ "$current_name" != "big-bear-"* ]]; then
        yq eval ".name = \"big-bear-$current_name\"" -i "$compose_file"
    fi
    
    # Add x-casaos sections to compose file
    # Add top-level x-casaos
    yq eval ".x-casaos.architectures = $APP_ARCHITECTURES" -i "$compose_file"
    yq eval ".x-casaos.main = \"$APP_MAIN_SERVICE\"" -i "$compose_file"
    yq eval ".x-casaos.description.en_us = \"$APP_DESCRIPTION\"" -i "$compose_file"
    
    # Add screenshot_link if screenshots exist
    local screenshots=$(jq -c '.visual.screenshots // []' "$app_dir/app.json")
    local screenshot_count=$(echo "$screenshots" | jq 'length')
    if [[ "$screenshot_count" -gt 0 ]]; then
        yq eval ".x-casaos.screenshot_link = $screenshots" -i "$compose_file"
    fi
    
    yq eval ".x-casaos.tagline.en_us = \"$APP_TAGLINE\"" -i "$compose_file"
    yq eval ".x-casaos.developer = \"$APP_DEVELOPER\"" -i "$compose_file"
    yq eval ".x-casaos.author = \"$APP_AUTHOR\"" -i "$compose_file"
    yq eval ".x-casaos.icon = \"$APP_ICON\"" -i "$compose_file"
    yq eval ".x-casaos.thumbnail = \"$APP_THUMBNAIL\"" -i "$compose_file"
    
    # Add tips if they exist
    local tips_before_install=$(jq -r '.ui.tips.before_install.en_us // ""' "$app_dir/app.json")
    if [[ -n "$tips_before_install" && "$tips_before_install" != "null" ]]; then
        # Escape the multiline string for yq and use style="literal" for proper formatting
        local tips_json=$(jq -c '.ui.tips.before_install // {}' "$app_dir/app.json")
        yq eval ".x-casaos.tips.before_install = $tips_json" -i "$compose_file"
    fi
    
    yq eval ".x-casaos.title.en_us = \"$APP_NAME\"" -i "$compose_file"
    yq eval ".x-casaos.category = \"$APP_CATEGORY\"" -i "$compose_file"
    
    # Use platform-specific port if defined, otherwise use default
    local casaos_port="${PORT_CASAOS:-$APP_DEFAULT_PORT}"
    yq eval ".x-casaos.port_map = \"$casaos_port\"" -i "$compose_file"
    
    # Add descriptive comments to x-casaos section using perl (works on both macOS and Linux)
    # Add comment before architectures
    perl -i -pe 's/^x-casaos:/x-casaos:\n  # Supported CPU architectures for this application/' "$compose_file"
    
    # Add comment before main
    perl -i -pe 's/^  main:/  # Main service for this application\n  main:/' "$compose_file"
    
    # Add comment before description
    perl -i -pe 's/^  description:/  # Detailed description for the application\n  description:/' "$compose_file"
    
    # Add comment before screenshot_link (if it exists)
    perl -i -pe 's/^  screenshot_link:/  # Screenshot links for the application\n  screenshot_link:/' "$compose_file"
    
    # Add comment before tagline
    perl -i -pe 's/^  tagline:/  # Brief tagline for the application\n  tagline:/' "$compose_file"
    
    # Add comment before developer
    perl -i -pe 's/^  developer:/  # Developer'"'"'s information\n  developer:/' "$compose_file"
    
    # Add comment before author  
    perl -i -pe 's/^  author:/  # Author of this particular configuration\n  author:/' "$compose_file"
    
    # Add comment before icon
    perl -i -pe 's/^  icon:/  # Icon URL for the application\n  icon:/' "$compose_file"
    
    # Add comment before thumbnail
    perl -i -pe 's/^  thumbnail:/  # Thumbnail image for the application (if any)\n  thumbnail:/' "$compose_file"
    
    # Add comment before tips (if it exists)
    perl -i -pe 's/^  tips:/  # Installation tips\n  tips:/' "$compose_file"
    
    # Add comment before title
    perl -i -pe 's/^  title:/  # Title for the application\n  title:/' "$compose_file"
    
    # Add comment before category
    perl -i -pe 's/^  category:/  # Category under which the application falls\n  category:/' "$compose_file"
    
    # Add comment before port_map
    perl -i -pe 's/^  port_map:/  # Default port mapping for the application\n  port_map:/' "$compose_file"
    
    # Add service-level x-casaos for ALL services (not just main)
    # Get all service names
    local all_services=$(yq eval '.services | keys | .[]' "$compose_file")
    
    while IFS= read -r service_name; do
        [[ -z "$service_name" ]] && continue
        
        # Add environment variables for this service
        # Environment can be either an array of "KEY=VALUE" strings or an object {KEY: VALUE}
        local env_format=$(yq eval ".services[\"$service_name\"].environment | type" "$compose_file" 2>/dev/null || echo "null")
        local env_index=0
        
        if [[ "$env_format" == "!!seq" ]]; then
            # Array format: ["KEY=VALUE", ...]
            local service_envs=$(yq eval ".services[\"$service_name\"].environment | .[]" "$compose_file" 2>/dev/null || echo "")
            while IFS= read -r env_entry; do
                [[ -z "$env_entry" ]] && continue
                
                # Extract key from "KEY=VALUE" format
                local env_key="${env_entry%%=*}"
                
                # Skip if empty or invalid
                if [[ -z "$env_key" ]] || [[ "$env_key" == "null" ]] || [[ "$env_key" == "#"* ]]; then
                    continue
                fi
                
                # Add to x-casaos with proper escaping
                yq eval ".services.[\"$service_name\"].x-casaos.envs[$env_index].container = \"$env_key\"" -i "$compose_file" 2>/dev/null || true
                yq eval ".services.[\"$service_name\"].x-casaos.envs[$env_index].description.en_us = \"Container Variable: $env_key\"" -i "$compose_file" 2>/dev/null || true
                env_index=$((env_index + 1))
            done <<< "$service_envs"
        elif [[ "$env_format" == "!!map" ]]; then
            # Object format: {KEY: VALUE, ...}
            local service_envs=$(yq eval ".services[\"$service_name\"].environment | keys | .[]" "$compose_file" 2>/dev/null || echo "")
            while IFS= read -r env_key; do
                [[ -z "$env_key" ]] && continue
                
                # Skip if empty or invalid
                if [[ -z "$env_key" ]] || [[ "$env_key" == "null" ]] || [[ "$env_key" == "#"* ]]; then
                    continue
                fi
                
                # Add to x-casaos with proper escaping
                yq eval ".services.[\"$service_name\"].x-casaos.envs[$env_index].container = \"$env_key\"" -i "$compose_file" 2>/dev/null || true
                yq eval ".services.[\"$service_name\"].x-casaos.envs[$env_index].description.en_us = \"Container Variable: $env_key\"" -i "$compose_file" 2>/dev/null || true
                env_index=$((env_index + 1))
            done <<< "$service_envs"
        fi
        
        # Add volumes for this service
        local service_volumes=$(yq eval ".services[\"$service_name\"].volumes | .[]" "$compose_file" 2>/dev/null || echo "")
        local vol_index=0
        while IFS= read -r volume_entry; do
            [[ -z "$volume_entry" ]] && continue
            
            # Extract container path from volume entry (after the colon)
            local container_path="${volume_entry#*:}"
            # Remove any trailing options (e.g., :ro, :rw)
            container_path="${container_path%%:*}"
            
            # Skip if it's not a valid path
            if [[ -z "$container_path" ]] || [[ "$container_path" == "null" ]]; then
                continue
            fi
            
            # Add to x-casaos with proper escaping
            yq eval ".services.[\"$service_name\"].x-casaos.volumes[$vol_index].container = \"$container_path\"" -i "$compose_file" 2>/dev/null || true
            yq eval ".services.[\"$service_name\"].x-casaos.volumes[$vol_index].description.en_us = \"Container Path: $container_path\"" -i "$compose_file" 2>/dev/null || true
            vol_index=$((vol_index + 1))
        done <<< "$service_volumes"
        
        # Add ports for this service
        local service_ports=$(yq eval ".services[\"$service_name\"].ports | .[]" "$compose_file" 2>/dev/null || echo "")
        local port_index=0
        while IFS= read -r port_entry; do
            [[ -z "$port_entry" ]] && continue
            
            # Extract container port from port entry
            local container_port="${port_entry#*:}"
            # Remove any protocol suffix (e.g., /tcp, /udp)
            container_port="${container_port%%/*}"
            
            # Skip if it's not a valid port
            if [[ -z "$container_port" ]] || [[ "$container_port" == "null" ]]; then
                continue
            fi
            
            # Add to x-casaos with proper escaping
            yq eval ".services.[\"$service_name\"].x-casaos.ports[$port_index].container = \"$container_port\"" -i "$compose_file" 2>/dev/null || true
            yq eval ".services.[\"$service_name\"].x-casaos.ports[$port_index].description.en_us = \"Container Port: $container_port\"" -i "$compose_file" 2>/dev/null || true
            port_index=$((port_index + 1))
        done <<< "$service_ports"
        
    done <<< "$all_services"
    
    # Convert named volumes to CasaOS bind mounts
    # Only convert if there are named volumes defined at the top level
    local volume_names=$(yq eval '.volumes | keys | .[]' "$compose_file" 2>/dev/null || echo "")
    
    if [[ -n "$volume_names" ]]; then
        # Load platform-specific volume mappings from app.json if they exist
        local volume_mappings_json=$(jq -c '.compatibility.casaos.volume_mappings // {}' "$app_dir/app.json" 2>/dev/null)
        
        # Get all service names
        local all_services=$(yq eval '.services | keys | .[]' "$compose_file")
        
        # For each service
        while IFS= read -r service_name; do
            [[ -z "$service_name" ]] && continue
            
            # For each named volume, convert references in this service to CasaOS bind mounts
            while IFS= read -r vol_name; do
                [[ -z "$vol_name" ]] && continue
                
                # Get the count of volumes in this service
                local vol_count=$(yq eval ".services.$service_name.volumes | length" "$compose_file" 2>/dev/null || echo "0")
                
                for ((j=0; j<vol_count; j++)); do
                    local vol_entry=$(yq eval ".services.$service_name.volumes[$j]" "$compose_file")
                    
                    # Skip if this is already a bind mount (starts with / or ./)
                    if [[ "$vol_entry" == /* ]] || [[ "$vol_entry" == ./* ]]; then
                        continue
                    fi
                    
                    # Check if this volume entry uses the named volume
                    if [[ "$vol_entry" == "${vol_name}:"* ]]; then
                        # Extract container path
                        local container_path="${vol_entry#*:}"
                        # Remove any trailing options (e.g., :ro, :rw)
                        container_path="${container_path%%:*}"
                        
                        # Check if there's a custom mapping for this volume
                        local custom_mapping=$(echo "$volume_mappings_json" | jq -r --arg vol "$vol_name" '.[$vol] // empty')
                        
                        local casaos_path
                        if [[ -n "$custom_mapping" && "$custom_mapping" != "null" ]]; then
                            # Use the custom mapping from app.json
                            casaos_path="${custom_mapping}:${container_path}"
                        else
                            # Fall back to default conversion logic
                            # Convert volume name to a simple folder name (remove app prefix if exists)
                            local folder_suffix="${vol_name#*_}"  # Remove prefix before underscore
                            [[ "$folder_suffix" == "$vol_name" ]] && folder_suffix="${vol_name}"
                            
                            # Convert underscores to slashes for nested paths (e.g., data_work -> data/work)
                            folder_suffix="${folder_suffix//_//}"
                            
                            casaos_path="/DATA/AppData/\$AppID/${folder_suffix}:${container_path}"
                        fi
                        
                        # Replace the volume entry
                        yq eval ".services.$service_name.volumes[$j] = \"$casaos_path\"" -i "$compose_file"
                    fi
                done
            done <<< "$volume_names"
        done <<< "$all_services"
        
        # Remove the volumes section at the top level (named volumes are no longer needed)
        yq eval 'del(.volumes)' -i "$compose_file"
    fi
    
    # Get platform-specific YouTube (or fall back to global)
    local platform_youtube=$(jq -r '.compatibility.casaos.youtube // ""' "$app_dir/app.json")
    local youtube_url="${platform_youtube:-$APP_YOUTUBE}"
    
    # Create config.json for CasaOS
    cat > "$output_dir/config.json" << EOF
{
  "id": "$APP_ID",
  "version": "$APP_VERSION",
  "image": "$APP_MAIN_IMAGE",
  "youtube": "$youtube_url",
  "docs_link": "$APP_DOCS"
}
EOF
    
    print_success "Converted $app_name for CasaOS"
}

# Convert to Portainer format
convert_to_portainer() {
    local app_name="$1"
    local app_dir="$2"
    local master_file="$OUTPUT_DIR/portainer/templates.json"
    
    local folder_name=$(get_platform_folder_name "$app_dir" "portainer")
    local output_dir="$OUTPUT_DIR/portainer/$folder_name"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "DRY RUN: Would convert $app_name to Portainer format (folder: $folder_name)"
        return
    fi
    
    mkdir -p "$output_dir"
    
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
    
    # Escape JSON strings - order matters! Backslashes first, then quotes, then control chars
    local title_json="${APP_NAME}"
    local desc_json="${APP_DESCRIPTION}"
    local tag_json="${APP_TAGLINE}"
    
    # Escape backslashes first
    title_json="${title_json//\\/\\\\}"
    desc_json="${desc_json//\\/\\\\}"
    tag_json="${tag_json//\\/\\\\}"
    
    # Then escape quotes
    title_json="${title_json//\"/\\\"}"
    desc_json="${desc_json//\"/\\\"}"
    tag_json="${tag_json//\"/\\\"}"
    
    # Then escape control characters
    title_json="${title_json//$'\n'/\\n}"
    title_json="${title_json//$'\r'/\\r}"
    title_json="${title_json//$'\t'/\\t}"
    
    desc_json="${desc_json//$'\n'/\\n}"
    desc_json="${desc_json//$'\r'/\\r}"
    desc_json="${desc_json//$'\t'/\\t}"
    
    tag_json="${tag_json//$'\n'/\\n}"
    tag_json="${tag_json//$'\r'/\\r}"
    tag_json="${tag_json//$'\t'/\\t}"
    
    # Build environment variables JSON
    local env_json=""
    local env_count=$(echo "$APP_ENV_VARS" | jq 'length')
    for ((i=0; i<env_count; i++)); do
        local env_name=$(echo "$APP_ENV_VARS" | jq -r ".[$i].name")
        local env_default=$(echo "$APP_ENV_VARS" | jq -r ".[$i].default // \"\"")
        local env_desc=$(echo "$APP_ENV_VARS" | jq -r ".[$i].description")
        
        # Escape backslashes first
        env_default="${env_default//\\/\\\\}"
        env_desc="${env_desc//\\/\\\\}"
        
        # Then escape quotes
        env_default="${env_default//\"/\\\"}"
        env_desc="${env_desc//\"/\\\"}"
        
        # Then escape control characters
        env_default="${env_default//$'\n'/\\n}"
        env_default="${env_default//$'\r'/\\r}"
        env_default="${env_default//$'\t'/\\t}"
        
        env_desc="${env_desc//$'\n'/\\n}"
        env_desc="${env_desc//$'\r'/\\r}"
        env_desc="${env_desc//$'\t'/\\t}"
        
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
    
    local folder_name=$(get_platform_folder_name "$app_dir" "runtipi")
    local output_dir="$OUTPUT_DIR/runtipi/$folder_name"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "DRY RUN: Would convert $app_name to Runtipi format (folder: $folder_name)"
        return
    fi
    
    mkdir -p "$output_dir/metadata"
    
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
    
    # Convert labels from array to object format if needed (some apps use array syntax)
    # Check if labels exists and is an array
    local labels_type=$(yq eval ".services[\"$app_name\"].labels | type" "$compose_file" 2>/dev/null || echo "null")
    if [[ "$labels_type" == "!!seq" ]]; then
        # Convert array format (- key=value) to object format (key: value)
        local temp_labels=$(yq eval ".services[\"$app_name\"].labels" "$compose_file" | sed 's/^- //' | awk -F= '{print $1 ": \"" $2 "\""}' 2>/dev/null || echo "")
        if [[ -n "$temp_labels" ]]; then
            yq eval ".services[\"$app_name\"].labels = {}" -i "$compose_file"
            while IFS= read -r label; do
                if [[ -n "$label" && "$label" =~ : ]]; then
                    local key=$(echo "$label" | cut -d: -f1 | xargs)
                    local value=$(echo "$label" | cut -d: -f2- | xargs | sed 's/^"//' | sed 's/"$//')
                    if [[ -n "$key" ]]; then
                        yq eval ".services[\"$app_name\"].labels[\"$key\"] = \"$value\"" -i "$compose_file" 2>/dev/null || true
                    fi
                fi
            done <<< "$temp_labels"
        fi
    fi
    
    # Add runtipi.managed label to ALL services
    local all_services=$(yq eval '.services | keys | .[]' "$compose_file")
    while IFS= read -r service_name; do
        [[ -z "$service_name" ]] && continue
        yq eval ".services[\"$service_name\"].labels[\"runtipi.managed\"] = \"true\"" -i "$compose_file" 2>/dev/null || true
    done <<< "$all_services"
    
    # Replace all networks with tipi_main_network only (skip for certain apps)
    local network_exceptions=("pihole" "tailscale" "homeassistant" "plex")
    local skip_network=false
    for exception in "${network_exceptions[@]}"; do
        if [[ "$app_name" == "$exception" ]]; then
            skip_network=true
            break
        fi
    done
    
    if [[ "$skip_network" == "false" ]]; then
        # Remove all custom networks from services and set only tipi_main_network
        all_services=$(yq eval '.services | keys | .[]' "$compose_file")
        while IFS= read -r service_name; do
            [[ -z "$service_name" ]] && continue
            # Replace networks with only tipi_main_network
            yq eval ".services[\"$service_name\"].networks = [\"tipi_main_network\"]" -i "$compose_file"
        done <<< "$all_services"
        
        # Remove all custom networks and add only tipi_main_network
        yq eval 'del(.networks) | .networks.tipi_main_network.external = true' -i "$compose_file"
    fi
    
    # Convert named volumes to ${APP_DATA_DIR} bind mounts for Runtipi
    local volume_names=$(yq eval '.volumes | keys | .[]' "$compose_file" 2>/dev/null || echo "")
    
    if [[ -n "$volume_names" ]]; then
        # Load platform-specific volume mappings from app.json if they exist
        local volume_mappings_json=$(jq -c '.compatibility.runtipi.volume_mappings // {}' "$app_dir/app.json" 2>/dev/null)
        
        # Get all service names
        local all_services=$(yq eval '.services | keys | .[]' "$compose_file")
        
        # For each service
        while IFS= read -r service_name; do
            [[ -z "$service_name" ]] && continue
            
            # For each named volume, convert references in this service to Runtipi bind mounts
            while IFS= read -r vol_name; do
                [[ -z "$vol_name" ]] && continue
                
                # Get the count of volumes in this service
                local vol_count=$(yq eval ".services.$service_name.volumes | length" "$compose_file" 2>/dev/null || echo "0")
                
                for ((j=0; j<vol_count; j++)); do
                    # Check if this is long-form syntax (has a 'source' key)
                    local vol_source=$(yq eval ".services.$service_name.volumes[$j].source" "$compose_file" 2>/dev/null)
                    
                    if [[ -n "$vol_source" && "$vol_source" != "null" ]]; then
                        # Long-form syntax
                        if [[ "$vol_source" == "$vol_name" ]]; then
                            # Check if there's a custom mapping for this volume
                            local custom_mapping=$(echo "$volume_mappings_json" | jq -r --arg vol "$vol_name" '.[$vol] // empty')
                            
                            local runtipi_source
                            if [[ -n "$custom_mapping" && "$custom_mapping" != "null" ]]; then
                                # Use the custom mapping from app.json
                                runtipi_source="\${APP_DATA_DIR}/${custom_mapping}"
                            else
                                # Fall back to default conversion logic
                                runtipi_source="\${APP_DATA_DIR}/data/${vol_name}"
                            fi
                            
                            # This is a named volume reference, convert to ${APP_DATA_DIR}
                            yq eval ".services.$service_name.volumes[$j].source = \"$runtipi_source\"" -i "$compose_file"
                        fi
                    else
                        # Short-form syntax
                        local vol_entry=$(yq eval ".services.$service_name.volumes[$j]" "$compose_file")
                        
                        # Check if this volume entry uses the named volume
                        if [[ "$vol_entry" == "${vol_name}:"* ]]; then
                            # Extract container path
                            local container_path="${vol_entry#*:}"
                            # Remove any trailing options (e.g., :ro, :rw)
                            local mount_options=""
                            if [[ "$container_path" == *":ro" ]]; then
                                mount_options=":ro"
                                container_path="${container_path%:ro}"
                            elif [[ "$container_path" == *":rw" ]]; then
                                mount_options=":rw"
                                container_path="${container_path%:rw}"
                            fi
                            
                            # Check if there's a custom mapping for this volume
                            local custom_mapping=$(echo "$volume_mappings_json" | jq -r --arg vol "$vol_name" '.[$vol] // empty')
                            
                            local runtipi_path
                            if [[ -n "$custom_mapping" && "$custom_mapping" != "null" ]]; then
                                # Use the custom mapping from app.json
                                runtipi_path="\${APP_DATA_DIR}/${custom_mapping}:${container_path}${mount_options}"
                            else
                                # Fall back to default conversion logic
                                runtipi_path="\${APP_DATA_DIR}/data/${vol_name}:${container_path}${mount_options}"
                            fi
                            
                            # Replace the volume entry
                            yq eval ".services.$service_name.volumes[$j] = \"$runtipi_path\"" -i "$compose_file"
                        fi
                    fi
                done
            done <<< "$volume_names"
        done <<< "$all_services"
        
        # Remove the volumes section at the top level (named volumes are no longer needed)
        yq eval 'del(.volumes)' -i "$compose_file"
    fi
    
    # Convert relative path volumes to ${APP_DATA_DIR} format
    local all_services=$(yq eval '.services | keys | .[]' "$compose_file")
    while IFS= read -r service_name; do
        [[ -z "$service_name" ]] && continue
        
        local vol_count=$(yq eval ".services.$service_name.volumes | length" "$compose_file" 2>/dev/null || echo "0")
        
        for ((j=0; j<vol_count; j++)); do
            local vol_entry=$(yq eval ".services.$service_name.volumes[$j]" "$compose_file")
            
            # Check if this is a relative path volume (starts with ./)
            if [[ "$vol_entry" == "./"* ]]; then
                # Extract the path after ./
                local relative_path="${vol_entry#./}"
                local container_path="${relative_path#*:}"
                local host_path="${relative_path%%:*}"
                
                # Remove any trailing options (e.g., :ro, :rw)
                local mount_options=""
                if [[ "$container_path" == *":ro" ]]; then
                    mount_options=":ro"
                    container_path="${container_path%:ro}"
                elif [[ "$container_path" == *":rw" ]]; then
                    mount_options=":rw"
                    container_path="${container_path%:rw}"
                fi
                
                # Convert to ${APP_DATA_DIR} format
                local runtipi_path="\${APP_DATA_DIR}/${host_path}:${container_path}${mount_options}"
                
                # Replace the volume entry
                yq eval ".services.$service_name.volumes[$j] = \"$runtipi_path\"" -i "$compose_file"
            fi
        done
    done <<< "$all_services"
    
    # Convert ports to use ${APP_PORT} for the main service
    # Get all service names
    local all_services=$(yq eval '.services | keys | .[]' "$compose_file")
    while IFS= read -r service_name; do
        [[ -z "$service_name" ]] && continue
        
        # Only convert ports for the main service (app_name)
        if [[ "$service_name" == "$app_name" ]]; then
            local port_count=$(yq eval ".services.$service_name.ports | length" "$compose_file" 2>/dev/null || echo "0")
            
            for ((p=0; p<port_count; p++)); do
                # Check if this is long-form syntax (has a 'target' key)
                local port_target=$(yq eval ".services.$service_name.ports[$p].target" "$compose_file" 2>/dev/null)
                
                if [[ -n "$port_target" && "$port_target" != "null" ]]; then
                    # Long-form syntax - update the published port to use ${APP_PORT}
                    yq eval ".services.$service_name.ports[$p].published = \"\${APP_PORT}\"" -i "$compose_file"
                else
                    # Short-form syntax
                    local port_entry=$(yq eval ".services.$service_name.ports[$p]" "$compose_file")
                    
                    # Extract container port from port entry (after the colon)
                    local container_port="${port_entry#*:}"
                    # Remove any protocol suffix (e.g., /tcp, /udp)
                    local protocol=""
                    if [[ "$container_port" == *"/tcp" ]]; then
                        protocol="/tcp"
                        container_port="${container_port%/tcp}"
                    elif [[ "$container_port" == *"/udp" ]]; then
                        protocol="/udp"
                        container_port="${container_port%/udp}"
                    fi
                    
                    # Convert to ${APP_PORT}:container_port format
                    local runtipi_port="\${APP_PORT}:${container_port}${protocol}"
                    
                    # Replace the port entry
                    yq eval ".services.$service_name.ports[$p] = \"$runtipi_port\"" -i "$compose_file"
                fi
                
                # Only convert the first port mapping to use ${APP_PORT}
                break
            done
        fi
    done <<< "$all_services"
    
    # Determine port - use platform-specific port if defined, otherwise use default
    local runtipi_port="${PORT_RUNTIPI:-${APP_DEFAULT_PORT:-8080}}"
    # Only process port if it's a valid number and no platform-specific port is set
    if [[ -z "$PORT_RUNTIPI" ]] && [[ "$runtipi_port" =~ ^[0-9]+$ ]] && [[ "$runtipi_port" -le 999 ]]; then
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
    
    local folder_name=$(get_platform_folder_name "$app_dir" "dockge")
    local output_dir="$OUTPUT_DIR/dockge/$folder_name"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "DRY RUN: Would convert $app_name to Dockge format (folder: $folder_name)"
        return
    fi
    
    mkdir -p "$output_dir"
    
    # Copy compose and add big-bear- prefix to volumes
    adjust_compose_for_platform "$app_dir/docker-compose.yml" "$output_dir/compose.yaml" "dockge" "$app_name"
    
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
    
    local folder_name=$(get_platform_folder_name "$app_dir" "cosmos")
    local output_dir="$OUTPUT_DIR/cosmos/$folder_name"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "DRY RUN: Would convert $app_name to Cosmos format (folder: $folder_name)"
        return
    fi
    
    mkdir -p "$output_dir"
    
    # Create temporary compose file with big-bear- prefix
    local temp_compose=$(mktemp)
    adjust_compose_for_platform "$app_dir/docker-compose.yml" "$temp_compose" "cosmos" "$app_name"
    
    # Create cosmos-compose.json with routes
    local cosmos_port="${PORT_COSMOS:-$APP_DEFAULT_PORT}"
    local routes=""
    if [[ -n "$cosmos_port" ]]; then
        routes="\"routes\": [
        {
          \"name\": \"$APP_NAME\",
          \"description\": \"Web UI\",
          \"useHost\": true,
          \"target\": \"http://$app_name:$cosmos_port\",
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
      "$app_name": $(yq eval -o=json ".services.[\"$APP_MAIN_SERVICE\"] // (.services | to_entries[0].value)" "$temp_compose")
    }
  }
}
EOF
    
    # Clean up temporary file
    rm -f "$temp_compose"
    
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
    
    # Validate app_name is not empty
    if [[ -z "$app_name" ]]; then
        print_error "Cannot convert to Umbrel: app_name is empty"
        return 1
    fi
    
    # Get the folder name from compatibility settings (defaults to big-bear-umbrel-{app_id})
    local folder_name=$(get_platform_folder_name "$app_dir" "umbrel")
    
    # If no override, or if folder_name is empty/null, use the default Umbrel naming convention
    if [[ "$folder_name" == "$app_name" ]] || [[ -z "$folder_name" ]] || [[ "$folder_name" == "null" ]]; then
        folder_name="big-bear-umbrel-$app_name"
    fi
    
    # Final validation: ensure folder_name is valid
    if [[ -z "$folder_name" ]] || [[ "$folder_name" == "null" ]]; then
        print_error "Cannot convert $app_name to Umbrel: invalid folder_name"
        return 1
    fi
    
    local output_dir="$OUTPUT_DIR/umbrel/$folder_name"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "DRY RUN: Would convert $app_name to Umbrel format (folder: $folder_name)"
        return
    fi
    
    mkdir -p "$output_dir"
    
    # Check if main service uses network_mode: host early
    local uses_host_network=false
    local main_service_for_check="${APP_MAIN_SERVICE:-app}"
    if [[ -z "$main_service_for_check" || "$main_service_for_check" == "null" ]]; then
        main_service_for_check=$(yq eval '.services | keys | .[0]' "$app_dir/docker-compose.yml" 2>/dev/null || echo "app")
    fi
    local network_mode_check
    network_mode_check=$(yq eval ".services[\"$main_service_for_check\"].network_mode // \"\"" "$app_dir/docker-compose.yml" 2>/dev/null)
    if [[ "$network_mode_check" == "host" ]]; then
        uses_host_network=true
        echo "  ℹ App uses network_mode: host"
    fi
    
    # Umbrel base port for safer port allocation (avoids common 8000s conflicts)
    local UMBREL_BASE_PORT=10000
    
    # Check if platform-specific port override exists
    local use_port_override=false
    if [[ -n "$PORT_UMBREL" ]]; then
        use_port_override=true
    fi
    
    # Extract ports from docker-compose.yml if available
    # For Umbrel we need TWO ports:
    # 1. host_port (umbrel-app.yml "port" field) - unique public port
    # 2. container_port (APP_PORT in docker-compose.yml) - internal port app listens on
    local host_port="${PORT_UMBREL:-$APP_DEFAULT_PORT}"
    local container_port="$APP_DEFAULT_PORT"
    local port_spec=$(yq eval '.services[].ports[0]' "$app_dir/docker-compose.yml" 2>/dev/null | head -1)
    
    if [[ -n "$port_spec" && "$port_spec" != "null" ]]; then
        if [[ "$port_spec" =~ ^[0-9]+:[0-9]+$ ]]; then
            # Format: "host:container" - extract both sides
            if [[ "$use_port_override" == false ]]; then
                host_port=$(echo "$port_spec" | cut -d':' -f1)
            fi
            container_port=$(echo "$port_spec" | cut -d':' -f2)
        elif [[ "$port_spec" =~ ^[0-9]+$ ]]; then
            # Format: just the port number - use for both
            if [[ "$use_port_override" == false ]]; then
                host_port="$port_spec"
            fi
            container_port="$port_spec"
        else
            # Complex format (e.g., "8080:8000/tcp")
            local clean_spec=$(echo "$port_spec" | sed 's|/.*||')
            if [[ "$clean_spec" =~ : ]]; then
                if [[ "$use_port_override" == false ]]; then
                    host_port=$(echo "$clean_spec" | cut -d':' -f1)
                fi
                container_port=$(echo "$clean_spec" | cut -d':' -f2)
            fi
        fi
    fi
    
    # Remap host_port to safer 10000+ range to avoid common port conflicts (unless port override is set)
    # Keep container_port as-is (internal app port)
    if [[ "$use_port_override" == false ]] && [[ "$host_port" =~ ^[0-9]+$ ]] && [[ "$host_port" -lt "$UMBREL_BASE_PORT" ]]; then
        # Calculate sequential port from base
        local port_map_file="$OUTPUT_DIR/umbrel/.port_sequence"
        if [[ ! -f "$port_map_file" ]]; then
            echo "$UMBREL_BASE_PORT" > "$port_map_file"
        fi
        
        # Read next available port
        local next_port=$(cat "$port_map_file")
        host_port="$next_port"
        
        # Increment for next app
        echo $((next_port + 1)) > "$port_map_file"
    fi
    
    # Copy compose and process it
    cp "$app_dir/docker-compose.yml" "$output_dir/docker-compose.yml"
    
    local temp_compose="$output_dir/docker-compose.tmp.yml"
    
    # Step 1: Add version: "3.7" at the top and remove incompatible Umbrel fields
    # Remove: name, ports, container_name
    # For network_mode: only delete if NOT set to "host" (host networking is valid for Umbrel)
    yq eval 'del(.name) | 
             del(.services[].ports) | 
             del(.services[].container_name) | 
             (.services[] | select(.network_mode != "host") | .network_mode) |= null |
             del(.services[] | select(.network_mode == null) | .network_mode) |
             . = {"version": "3.7"} + .' "$output_dir/docker-compose.yml" > "$temp_compose"
    mv "$temp_compose" "$output_dir/docker-compose.yml"
    
    # Step 2: Remove all comments from the YAML file
    # Remove blank lines but preserve all content (including # in values like dns ports)
    # Comment removal was too aggressive and removed parts of values (e.g., 127.0.0.1#5353)
    sed -E '/^[[:space:]]*$/d' "$output_dir/docker-compose.yml" > "$temp_compose"
    mv "$temp_compose" "$output_dir/docker-compose.yml"
    
    # Get the main service name
    local main_service="${APP_MAIN_SERVICE:-app}"
    if [[ -z "$main_service" || "$main_service" == "null" ]]; then
        main_service=$(yq eval '.services | keys | .[0]' "$output_dir/docker-compose.yml" 2>/dev/null || echo "app")
    fi
    
    # Check if main service uses network_mode: host
    local uses_host_network=false
    local network_mode_value
    network_mode_value=$(yq eval ".services[\"$main_service\"].network_mode // \"\"" "$output_dir/docker-compose.yml" 2>/dev/null)
    if [[ "$network_mode_value" == "host" ]]; then
        uses_host_network=true
        echo "  ℹ App uses network_mode: host, skipping app_proxy service"
    fi
    
    # Step 3: Add or update app_proxy service (only if not using host networking)
    # APP_HOST: container name that proxy connects to
    # APP_PORT: container's internal port (what the app listens on inside the container)
    if [[ "$uses_host_network" == "false" ]]; then
        local has_app_proxy=$(yq eval '.services.app_proxy // "null"' "$output_dir/docker-compose.yml" 2>/dev/null)
        if [[ "$has_app_proxy" != "null" ]]; then
            # Update existing app_proxy and remove empty volumes if present
            yq eval "del(.services.app_proxy.volumes) | 
                     .services.app_proxy.environment.APP_HOST = \"${folder_name}_${main_service}_1\" | 
                     .services.app_proxy.environment.APP_PORT = \"$container_port\"" "$output_dir/docker-compose.yml" > "$temp_compose"
            mv "$temp_compose" "$output_dir/docker-compose.yml"
        else
            # Add new app_proxy service at the beginning of services
            yq eval ".services = {\"app_proxy\": {\"environment\": {\"APP_HOST\": \"${folder_name}_${main_service}_1\", \"APP_PORT\": \"$container_port\"}}} + .services" "$output_dir/docker-compose.yml" > "$temp_compose"
            mv "$temp_compose" "$output_dir/docker-compose.yml"
        fi
    fi
    
    # Convert named volumes to ${APP_DATA_DIR} bind mounts for Umbrel
    # First, get list of named volumes
    local named_volumes=$(yq eval '.volumes | keys | .[]' "$output_dir/docker-compose.yml" 2>/dev/null || echo "")
    
    # Check if there are volume mapping overrides in app.json compatibility.umbrel.volume_mappings
    local has_volume_overrides=false
    local volume_overrides=$(yq eval '.compatibility.umbrel.volume_mappings // {}' "$app_dir/app.json" 2>/dev/null)
    if [[ "$volume_overrides" != "{}" && "$volume_overrides" != "null" ]]; then
        has_volume_overrides=true
        echo "  ℹ Using volume mapping overrides from app.json"
    fi
    
    if [[ -n "$named_volumes" ]]; then
        # For each service, replace volume references
        while IFS= read -r vol_name; do
            [[ -z "$vol_name" ]] && continue
            
            local clean_path
            
            # Check if there's a custom override for this volume
            if [[ "$has_volume_overrides" == "true" ]]; then
                clean_path=$(yq eval ".compatibility.umbrel.volume_mappings.\"$vol_name\" // \"\"" "$app_dir/app.json" 2>/dev/null)
            fi
            
            # If no override found, use automatic conversion
            if [[ -z "$clean_path" || "$clean_path" == "null" ]]; then
                # Convert volume name to a proper path by replacing underscores with slashes
                # e.g., "audiobookshelf_data_config" -> "data/config"
                # Remove common app name prefixes to get cleaner paths
                clean_path="$vol_name"
                # Remove app-specific prefix (e.g., "audiobookshelf_" from "audiobookshelf_data_config")
                # This preserves backward compatibility with existing Umbrel app structures
                clean_path=$(echo "$clean_path" | sed -E "s/^[a-z0-9-]+_//")
                # Convert remaining underscores to slashes for hierarchical paths
                clean_path=$(echo "$clean_path" | tr '_' '/')
            fi
            
            # Use sed to replace volume mounts in the file
            # Pattern: "volume_name:/path" becomes "${APP_DATA_DIR}/clean_path:/path"
            # Handle both quoted and unquoted volume references
            sed -i.bak "s|: ${vol_name}:|: \${APP_DATA_DIR}/${clean_path}:|g" "$output_dir/docker-compose.yml"
            sed -i.bak "s|- ${vol_name}:|- \${APP_DATA_DIR}/${clean_path}:|g" "$output_dir/docker-compose.yml"
            sed -i.bak "s|: \"${vol_name}:|: \${APP_DATA_DIR}/${clean_path}:|g" "$output_dir/docker-compose.yml"
            sed -i.bak "s|- \"${vol_name}:|- \${APP_DATA_DIR}/${clean_path}:|g" "$output_dir/docker-compose.yml"
            rm -f "$output_dir/docker-compose.yml.bak"
        done <<< "$named_volumes"
        
        # Remove any quotes around paths that contain slashes
        # Pattern 1: Remove quotes immediately after the path: ${APP_DATA_DIR}/"path" -> ${APP_DATA_DIR}/path
        sed -i.bak 's|\${APP_DATA_DIR}/"\([^"]*\)"|\${APP_DATA_DIR}/\1|g' "$output_dir/docker-compose.yml"
        # Pattern 2: Remove trailing quotes before comments: /path" # comment -> /path # comment
        sed -i.bak 's|\(\${APP_DATA_DIR}/[^"]*\)" #|\1 #|g' "$output_dir/docker-compose.yml"
        # Pattern 3: Remove trailing quotes at end of line: /path" -> /path
        sed -i.bak 's|\(\${APP_DATA_DIR}/[^"]*\)"$|\1|g' "$output_dir/docker-compose.yml"
        rm -f "$output_dir/docker-compose.yml.bak"
        
        # Remove the volumes section entirely
        yq eval 'del(.volumes)' "$output_dir/docker-compose.yml" > "$temp_compose"
        mv "$temp_compose" "$output_dir/docker-compose.yml"
        
        # Also remove any empty volumes arrays from services (only if app_proxy exists)
        if [[ "$uses_host_network" == "false" ]]; then
            yq eval 'del(.services.app_proxy.volumes)' "$output_dir/docker-compose.yml" > "$temp_compose" 2>/dev/null || cp "$output_dir/docker-compose.yml" "$temp_compose"
            mv "$temp_compose" "$output_dir/docker-compose.yml"
        fi
    fi
    
    # Convert CasaOS-style bind mounts to Umbrel format
    # Replace /DATA/AppData/$AppID with ${APP_DATA_DIR}
    sed -i.bak 's|/DATA/AppData/\$AppID|\${APP_DATA_DIR}|g' "$output_dir/docker-compose.yml"
    rm -f "$output_dir/docker-compose.yml.bak"
    
    # Create umbrel-app.yml with full app ID including prefix
    # For network_mode: host apps, use container_port (the actual port the app binds to)
    # For normal apps, use host_port (the remapped public port)
    local umbrel_port
    if [[ "$uses_host_network" == "true" ]]; then
        umbrel_port="$container_port"
        echo "  ℹ Using container port $container_port for umbrel-app.yml (network_mode: host)"
    else
        umbrel_port="$host_port"
    fi
    
    # Quote tagline if it contains colon (common YAML issue)
    local tagline_value="$APP_TAGLINE"
    if [[ "$tagline_value" == *:* ]] || [[ "$tagline_value" == *\#* ]] || [[ "$tagline_value" == *\[* ]] || [[ "$tagline_value" == *\{* ]]; then
        # Escape any existing quotes in the tagline
        local escaped_tagline="${APP_TAGLINE//\"/\\\"}"
        tagline_value="\"$escaped_tagline\""
    fi
    
    # Clean description: replace literal \n with spaces and collapse multiple spaces
    local clean_description=$(echo "$APP_DESCRIPTION" | tr '\n' ' ' | sed 's/  */ /g')
    
    # Debug: Print variables before creating umbrel-app.yml
    if [[ "$VERBOSE" == "true" ]]; then
        echo "  DEBUG: folder_name='$folder_name'"
        echo "  DEBUG: APP_NAME='$APP_NAME'"
        echo "  DEBUG: APP_VERSION='$APP_VERSION'"
    fi
    
    cat > "$output_dir/umbrel-app.yml" << EOF
manifestVersion: 1
id: $folder_name
category: $APP_CATEGORY
name: $APP_NAME
version: "$APP_VERSION"
tagline: $tagline_value
description: >-
  $clean_description
releaseNotes: >-
  This version includes various improvements and bug fixes.
developer: $APP_DEVELOPER
website: $APP_HOMEPAGE
dependencies: []
repo: https://github.com/bigbeartechworld/big-bear-universal-apps
support: https://github.com/bigbeartechworld/big-bear-universal-apps/issues
port: $umbrel_port
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
    
    # Validate the generated umbrel-app.yml has a valid ID
    local generated_id=$(yq eval '.id' "$output_dir/umbrel-app.yml" 2>/dev/null)
    if [[ -z "$generated_id" ]] || [[ "$generated_id" == "null" ]]; then
        print_error "Generated umbrel-app.yml for $app_name has invalid ID: '$generated_id'"
        print_error "folder_name was: '$folder_name'"
        print_error "Contents of umbrel-app.yml:"
        head -20 "$output_dir/umbrel-app.yml" | sed 's/^/  /'
        rm -rf "$output_dir"
        return 1
    fi
    
    # Create placeholder gallery images
    for i in 1 2 3; do
        create_placeholder_logo "$output_dir/$i.jpg"
    done
    
    # Create data directory with .gitkeep (standard Umbrel app structure)
    mkdir -p "$output_dir/data"
    touch "$output_dir/data/.gitkeep"
    
    print_success "Converted $app_name for Umbrel"
}

# Convert a single app to all platforms
convert_app() {
    local app_name="$1"
    local app_dir="$APPS_DIR/$app_name"
    
    # Skip the _example template app
    if [[ "$app_name" == "_example" ]]; then
        if [[ "$VERBOSE" == "true" ]]; then
            print_info "Skipping _example template app"
        fi
        TOTAL_SKIPPED=$((TOTAL_SKIPPED + 1))
        return 0
    fi
    
    if ! validate_app "$app_name"; then
        TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
        return 1
    fi
    
    # Load metadata to get compatibility flags
    load_app_metadata "$app_dir"
    
    print_info "Converting $app_name..."
    
    # Track if any platform was converted
    local platforms_converted=0
    
    # Convert to each platform
    for platform in "${PLATFORMS[@]}"; do
        case "$platform" in
            casaos)
                if [[ "$COMPAT_CASAOS" == "true" ]]; then
                    convert_to_casaos "$app_name" "$app_dir"
                    platforms_converted=$((platforms_converted + 1))
                elif [[ "$VERBOSE" == "true" ]]; then
                    print_info "$app_name: Skipping CasaOS (not supported)"
                fi
                ;;
            portainer)
                if [[ "$COMPAT_PORTAINER" == "true" ]]; then
                    convert_to_portainer "$app_name" "$app_dir"
                    platforms_converted=$((platforms_converted + 1))
                elif [[ "$VERBOSE" == "true" ]]; then
                    print_info "$app_name: Skipping Portainer (not supported)"
                fi
                ;;
            runtipi)
                if [[ "$COMPAT_RUNTIPI" == "true" ]]; then
                    convert_to_runtipi "$app_name" "$app_dir"
                    platforms_converted=$((platforms_converted + 1))
                elif [[ "$VERBOSE" == "true" ]]; then
                    print_info "$app_name: Skipping Runtipi (not supported)"
                fi
                ;;
            dockge)
                if [[ "$COMPAT_DOCKGE" == "true" ]]; then
                    convert_to_dockge "$app_name" "$app_dir"
                    platforms_converted=$((platforms_converted + 1))
                elif [[ "$VERBOSE" == "true" ]]; then
                    print_info "$app_name: Skipping Dockge (not supported)"
                fi
                ;;
            cosmos)
                if [[ "$COMPAT_COSMOS" == "true" ]]; then
                    convert_to_cosmos "$app_name" "$app_dir"
                    platforms_converted=$((platforms_converted + 1))
                elif [[ "$VERBOSE" == "true" ]]; then
                    print_info "$app_name: Skipping Cosmos (not supported)"
                fi
                ;;
            umbrel)
                if [[ "$COMPAT_UMBREL" == "true" ]]; then
                    convert_to_umbrel "$app_name" "$app_dir"
                    platforms_converted=$((platforms_converted + 1))
                elif [[ "$VERBOSE" == "true" ]]; then
                    print_info "$app_name: Skipping Umbrel (not supported)"
                fi
                ;;
            *)
                print_warning "Unknown platform: $platform"
                ;;
        esac
    done
    
    # Update counters based on whether any platforms were converted
    if [[ $platforms_converted -gt 0 ]]; then
        TOTAL_CONVERTED=$((TOTAL_CONVERTED + 1))
    else
        TOTAL_SKIPPED=$((TOTAL_SKIPPED + 1))
    fi
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
