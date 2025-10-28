#!/bin/bash

# Big Bear Universal Apps - Platform Sync Script
# Syncs converted apps from universal-apps/converted to platform repositories

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNIVERSAL_REPO="$(dirname "$SCRIPT_DIR")"
CONVERTED_DIR="$UNIVERSAL_REPO/converted"
WORKSPACE_DIR="$(dirname "$UNIVERSAL_REPO")"

# Platform repository paths
CASAOS_REPO="$WORKSPACE_DIR/big-bear-casaos"
PORTAINER_REPO="$WORKSPACE_DIR/big-bear-portainer"
RUNTIPI_REPO="$WORKSPACE_DIR/big-bear-runtipi"
DOCKGE_REPO="$WORKSPACE_DIR/big-bear-dockge"
COSMOS_REPO="$WORKSPACE_DIR/big-bear-cosmos"
UMBREL_REPO="$WORKSPACE_DIR/big-bear-umbrel"

PLATFORMS=("casaos" "portainer" "runtipi" "dockge" "cosmos" "umbrel")
SPECIFIC_APP=""
DRY_RUN=false
FORCE=false
REPLACE_ALL=false
CLEAN=false
VERBOSE=false

# Counters
TOTAL_SYNCED=0
TOTAL_SKIPPED=0
TOTAL_ERRORS=0

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Sync converted apps to platform repositories.

OPTIONS:
    -h, --help              Show this help message
    -c, --converted DIR     Converted apps directory (default: ./converted)
    -w, --workspace DIR     Workspace directory (default: parent of universal repo)
    -p, --platforms LIST    Comma-separated platforms to sync
                           Available: casaos,portainer,runtipi,dockge,cosmos,umbrel
    -a, --app NAME          Sync specific app only
    --dry-run              Show what would be synced
    --force                Overwrite existing apps
    --replace-all          Delete all existing apps before syncing
    --clean                Remove apps not in source
    -v, --verbose          Verbose output

EXAMPLES:
    $0                                    # Sync all apps to all platforms
    $0 -p casaos,runtipi                 # Sync to specific platforms
    $0 -a jellyseerr                     # Sync only jellyseerr
    $0 --dry-run                         # Preview sync

EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help) usage; exit 0 ;;
        -c|--converted) CONVERTED_DIR="$2"; shift 2 ;;
        -w|--workspace) WORKSPACE_DIR="$2"; shift 2 ;;
        -p|--platforms) IFS=',' read -ra PLATFORMS <<< "$2"; shift 2 ;;
        -a|--app) SPECIFIC_APP="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        --force) FORCE=true; shift ;;
        --replace-all) REPLACE_ALL=true; shift ;;
        --clean) CLEAN=true; shift ;;
        -v|--verbose) VERBOSE=true; shift ;;
        *) print_error "Unknown option: $1"; usage; exit 1 ;;
    esac
done

# Validate directories
validate_directories() {
    if [[ ! -d "$CONVERTED_DIR" ]]; then
        print_error "Converted directory not found: $CONVERTED_DIR"
        print_info "Run convert-to-platforms.sh first"
        exit 1
    fi
    
    print_info "Converted directory: $CONVERTED_DIR"
    print_info "Workspace directory: $WORKSPACE_DIR"
    print_info "Platforms: ${PLATFORMS[*]}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_warning "DRY RUN MODE"
    fi
    
    if [[ "$REPLACE_ALL" == "true" ]]; then
        print_warning "REPLACE ALL MODE - All existing apps will be deleted"
    fi
    
    echo ""
}

# Get destination directory for platform
get_platform_dest_dir() {
    local platform="$1"
    
    case "$platform" in
        casaos) echo "$CASAOS_REPO/Apps" ;;
        portainer) echo "$PORTAINER_REPO/Apps" ;;
        runtipi) echo "$RUNTIPI_REPO/apps" ;;
        dockge) echo "$DOCKGE_REPO/stacks" ;;
        cosmos) echo "$COSMOS_REPO/servapps" ;;
        umbrel) echo "$UMBREL_REPO/apps" ;;
        *) echo "" ;;
    esac
}

# Check if platform repository exists
check_platform_repo() {
    local platform="$1"
    local dest_dir=$(get_platform_dest_dir "$platform")
    
    if [[ -z "$dest_dir" ]]; then
        print_error "Unknown platform: $platform"
        return 1
    fi
    
    if [[ ! -d "$dest_dir" ]]; then
        print_warning "Platform repository not found: $dest_dir"
        return 1
    fi
    
    return 0
}

# Replace all apps in platform
replace_all_apps() {
    local platform="$1"
    local dest_dir=$(get_platform_dest_dir "$platform")
    
    if [[ ! -d "$dest_dir" ]]; then
        return
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "DRY RUN: Would delete all apps in $platform"
        return
    fi
    
    print_warning "Deleting all existing apps in $platform..."
    find "$dest_dir" -mindepth 1 -maxdepth 1 -type d ! -name '__tests__' -exec rm -rf {} + 2>/dev/null || true
    print_success "Cleared $platform"
}

# Sync a single app to platform
sync_app_to_platform() {
    local platform="$1"
    local app_name="$2"
    local source_dir="$CONVERTED_DIR/$platform/$app_name"
    local dest_dir=$(get_platform_dest_dir "$platform")
    local dest_app_dir="$dest_dir/$app_name"
    
    if [[ ! -d "$source_dir" ]]; then
        [[ "$VERBOSE" == "true" ]] && print_warning "Source not found: $source_dir"
        TOTAL_SKIPPED=$((TOTAL_SKIPPED + 1))
        return 1
    fi
    
    if [[ -d "$dest_app_dir" ]] && [[ "$FORCE" != "true" ]]; then
        [[ "$VERBOSE" == "true" ]] && print_info "Skipping $app_name (already exists)"
        TOTAL_SKIPPED=$((TOTAL_SKIPPED + 1))
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "DRY RUN: Would sync $app_name to $platform"
        TOTAL_SYNCED=$((TOTAL_SYNCED + 1))
        return 0
    fi
    
    mkdir -p "$dest_app_dir"
    
    if rsync -a --delete "$source_dir/" "$dest_app_dir/"; then
        [[ "$VERBOSE" == "true" ]] && print_success "Synced $app_name to $platform"
        TOTAL_SYNCED=$((TOTAL_SYNCED + 1))
    else
        print_error "Failed to sync $app_name to $platform"
        TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
        return 1
    fi
}

# Sync all apps for a platform
sync_platform() {
    local platform="$1"
    local platform_converted_dir="$CONVERTED_DIR/$platform"
    
    print_info "Syncing apps for $platform..."
    
    if [[ ! -d "$platform_converted_dir" ]]; then
        print_warning "No converted apps for $platform"
        return
    fi
    
    if ! check_platform_repo "$platform"; then
        return
    fi
    
    if [[ "$REPLACE_ALL" == "true" ]]; then
        replace_all_apps "$platform"
    fi
    
    # Get list of apps
    local apps=()
    while IFS= read -r -d '' app_dir; do
        local app_name=$(basename "$app_dir")
        apps+=("$app_name")
    done < <(find "$platform_converted_dir" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)
    
    if [[ ${#apps[@]} -eq 0 ]]; then
        print_warning "No apps found in $platform"
        return
    fi
    
    print_info "Found ${#apps[@]} apps for $platform"
    
    # Sync each app
    for app_name in "${apps[@]}"; do
        # Skip _example template app
        if [[ "$app_name" == "_example" ]]; then
            if [[ "$VERBOSE" == "true" ]]; then
                print_info "Skipping _example template app"
            fi
            continue
        fi
        
        if [[ -n "$SPECIFIC_APP" ]] && [[ "$app_name" != "$SPECIFIC_APP" ]]; then
            continue
        fi
        
        sync_app_to_platform "$platform" "$app_name"
    done
    
    echo ""
}

# Clean orphaned apps
clean_orphaned_apps() {
    local platform="$1"
    local dest_dir=$(get_platform_dest_dir "$platform")
    local platform_converted_dir="$CONVERTED_DIR/$platform"
    
    if [[ ! -d "$dest_dir" ]] || [[ ! -d "$platform_converted_dir" ]]; then
        return
    fi
    
    print_info "Cleaning orphaned apps in $platform..."
    
    local orphaned_count=0
    
    while IFS= read -r -d '' dest_app_dir; do
        local app_name=$(basename "$dest_app_dir")
        
        # Skip special directories
        if [[ "$app_name" == "__tests__" ]]; then
            continue
        fi
        
        # Check if app exists in source
        if [[ ! -d "$platform_converted_dir/$app_name" ]]; then
            if [[ "$DRY_RUN" == "true" ]]; then
                print_warning "DRY RUN: Would remove orphaned app: $app_name"
            else
                print_warning "Removing orphaned app: $app_name"
                rm -rf "$dest_app_dir"
            fi
            orphaned_count=$((orphaned_count + 1))
        fi
    done < <(find "$dest_dir" -mindepth 1 -maxdepth 1 -type d -print0)
    
    if [[ $orphaned_count -eq 0 ]]; then
        print_success "No orphaned apps found in $platform"
    else
        print_warning "Found $orphaned_count orphaned apps in $platform"
    fi
    
    echo ""
}

# Print summary
print_summary() {
    echo ""
    echo "========================================"
    echo "           SYNC SUMMARY"
    echo "========================================"
    echo -e "${GREEN}Synced:${NC}  $TOTAL_SYNCED apps"
    echo -e "${YELLOW}Skipped:${NC} $TOTAL_SKIPPED apps"
    echo -e "${RED}Errors:${NC}  $TOTAL_ERRORS apps"
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
    echo "    Universal Apps Platform Sync"
    echo "========================================"
    echo ""
    
    validate_directories
    
    # Check rsync
    if ! command -v rsync &> /dev/null; then
        print_error "rsync not found. Install: apt-get install rsync"
        exit 1
    fi
    
    # Sync each platform
    for platform in "${PLATFORMS[@]}"; do
        sync_platform "$platform"
    done
    
    # Clean orphaned apps if requested
    if [[ "$CLEAN" == "true" ]]; then
        for platform in "${PLATFORMS[@]}"; do
            clean_orphaned_apps "$platform"
        done
    fi
    
    print_summary
    
    if [[ $TOTAL_ERRORS -gt 0 ]]; then
        exit 1
    fi
}

main "$@"
