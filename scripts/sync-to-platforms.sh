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

# Platform repository paths are derived after argument parsing so -w/--workspace takes effect.
CASAOS_REPO=""
PORTAINER_REPO=""
RUNTIPI_REPO=""
DOCKGE_REPO=""
COSMOS_REPO=""
UMBREL_REPO=""

PLATFORMS=("casaos" "portainer" "runtipi" "dockge" "cosmos" "umbrel")
SPECIFIC_APP=""
DRY_RUN=false
FORCE=false
REPLACE_ALL=false
NO_CLEAN=false
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
    --no-clean             Skip removing orphaned apps (apps removed by default when not in source; a single-app sync removes only the named app)
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
        -a|--app)
            if [[ -z "${2:-}" ]]; then
                print_error "--app requires a non-empty app name"
                exit 1
            fi
            SPECIFIC_APP="$2"
            shift 2
            ;;
        --dry-run) DRY_RUN=true; shift ;;
        --force) FORCE=true; shift ;;
        --replace-all) REPLACE_ALL=true; shift ;;
        --no-clean) NO_CLEAN=true; shift ;;
        -v|--verbose) VERBOSE=true; shift ;;
        *) print_error "Unknown option: $1"; usage; exit 1 ;;
    esac
done

if [[ "$REPLACE_ALL" == "true" ]] && [[ -n "$SPECIFIC_APP" ]]; then
    print_error "--replace-all cannot be combined with --app"
    exit 1
fi

CASAOS_REPO="$WORKSPACE_DIR/big-bear-casaos"
PORTAINER_REPO="$WORKSPACE_DIR/big-bear-portainer"
RUNTIPI_REPO="$WORKSPACE_DIR/big-bear-runtipi"
DOCKGE_REPO="$WORKSPACE_DIR/big-bear-dockge"
COSMOS_REPO="$WORKSPACE_DIR/big-bear-cosmos"
UMBREL_REPO="$WORKSPACE_DIR/big-bear-umbrel"

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
        dockge) echo "$DOCKGE_REPO/Apps" ;;
        cosmos) echo "$COSMOS_REPO/servapps" ;;
        umbrel) echo "$UMBREL_REPO" ;;
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

# Same folder rule as convert-to-platforms.sh: compatibility.<platform>.folder_name,
# otherwise metadata.id, and Umbrel prefixes big-bear-umbrel- when that value is
# still the app directory name.
resolve_converted_folder_name() {
    local platform="$1"
    local app_name="$2"
    local app_json="$UNIVERSAL_REPO/apps/$app_name/app.json"
    local folder_name=""

    if [[ -f "$app_json" ]] && command -v python3 >/dev/null 2>&1; then
        folder_name="$(python3 - "$app_json" "$platform" << 'PY'
import json, sys
path, platform = sys.argv[1], sys.argv[2]
try:
    with open(path) as fh:
        data = json.load(fh)
except Exception as exc:
    print(f"Cannot read {path}: {exc}", file=sys.stderr)
    sys.exit(1)
compat = (data.get("compatibility") or {}).get(platform) or {}
folder = compat.get("folder_name")
if folder in (None, "", "null"):
    folder = (data.get("metadata") or {}).get("id") or ""
if folder in (None, "null"):
    folder = ""
print(folder)
PY
)" || folder_name=""
    elif [[ -f "$app_json" ]]; then
        print_warning "python3 is required to read folder_name overrides for $app_name"
    fi

    if [[ "$platform" == "umbrel" ]]; then
        if [[ -z "$folder_name" || "$folder_name" == "null" || "$folder_name" == "$app_name" ]]; then
            folder_name="big-bear-umbrel-$app_name"
        fi
    elif [[ -z "$folder_name" || "$folder_name" == "null" ]]; then
        folder_name="$app_name"
    fi

    printf '%s\n' "$folder_name"
}

# Umbrel apps live in the repository root, next to .git, scripts, schemas, and
# any other top-level directory the store adds later. Only directories the
# converter writes (they contain umbrel-app.yml) are apps.
is_platform_app_dir() {
    local platform="$1"
    local dir="$2"
    local name
    name="$(basename "$dir")"

    if [[ "$name" == "__tests__" ]]; then
        return 1
    fi
    if [[ "$platform" == "umbrel" ]]; then
        [[ -f "$dir/umbrel-app.yml" ]]
        return
    fi
    return 0
}

remove_absent_app() {
    local platform="$1"
    local folder="$2"
    local dest_dir source_dir dest_app_dir
    dest_dir="$(get_platform_dest_dir "$platform")"
    source_dir="$CONVERTED_DIR/$platform/$folder"
    dest_app_dir="$dest_dir/$folder"

    if [[ -d "$source_dir" || ! -d "$dest_app_dir" ]]; then
        return 1
    fi
    if ! is_platform_app_dir "$platform" "$dest_app_dir"; then
        return 1
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        print_warning "DRY RUN: Would remove orphaned app: $folder"
        return 0
    fi

    print_warning "Removing orphaned app: $folder"
    rm -rf "$dest_app_dir"
}

# --app names an app that is no longer in converted/. Remove only that folder.
conclude_specific_app() {
    local platform="$1"
    local resolved_folder="$2"

    if [[ "$NO_CLEAN" == "true" ]]; then
        local dest_dir
        dest_dir="$(get_platform_dest_dir "$platform")"
        if [[ ! -d "$dest_dir/$resolved_folder" && ! -d "$dest_dir/$SPECIFIC_APP" ]]; then
            print_warning "No app matched '$SPECIFIC_APP' for $platform"
        fi
        return
    fi

    if remove_absent_app "$platform" "$resolved_folder"; then
        return
    fi
    if [[ "$resolved_folder" != "$SPECIFIC_APP" ]] && remove_absent_app "$platform" "$SPECIFIC_APP"; then
        return
    fi
    print_warning "No app matched '$SPECIFIC_APP' for $platform"
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
    if [[ "$platform" == "umbrel" ]]; then
        while IFS= read -r -d '' app_dir; do
            if is_platform_app_dir "$platform" "$app_dir"; then
                rm -rf "$app_dir"
            fi
        done < <(find "$dest_dir" -mindepth 1 -maxdepth 1 -type d -print0)
    else
        find "$dest_dir" -mindepth 1 -maxdepth 1 -type d ! -name '__tests__' -exec rm -rf {} + 2>/dev/null || true
    fi
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
    local resolved_folder=""

    if [[ -n "$SPECIFIC_APP" ]]; then
        resolved_folder="$(resolve_converted_folder_name "$platform" "$SPECIFIC_APP")"
    fi
    
    print_info "Syncing apps for $platform..."
    
    if [[ ! -d "$platform_converted_dir" ]]; then
        print_warning "No converted apps for $platform"
        if [[ -n "$SPECIFIC_APP" ]] && check_platform_repo "$platform"; then
            conclude_specific_app "$platform" "$resolved_folder"
        fi
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
        if [[ -n "$SPECIFIC_APP" ]]; then
            conclude_specific_app "$platform" "$resolved_folder"
        fi
        return
    fi
    
    print_info "Found ${#apps[@]} apps for $platform"
    
    local matched_specific=0
    # Sync each app
    for app_name in "${apps[@]}"; do
        # Skip _example template app
        if [[ "$app_name" == "_example" ]]; then
            if [[ "$VERBOSE" == "true" ]]; then
                print_info "Skipping _example template app"
            fi
            continue
        fi
        
        if [[ -n "$SPECIFIC_APP" ]]; then
            if [[ "$app_name" != "$resolved_folder" && "$app_name" != "$SPECIFIC_APP" ]]; then
                continue
            fi
            # Prefer the converter folder when both it and the literal name exist.
            if [[ "$app_name" != "$resolved_folder" && -d "$platform_converted_dir/$resolved_folder" ]]; then
                continue
            fi
            matched_specific=1
        fi
        
        sync_app_to_platform "$platform" "$app_name"
    done

    if [[ -n "$SPECIFIC_APP" && "$matched_specific" -eq 0 ]]; then
        conclude_specific_app "$platform" "$resolved_folder"
    fi
    
    # Post-sync tasks for specific platforms
    post_sync_platform "$platform"
    
    echo ""
}

# Post-sync tasks for specific platforms
post_sync_platform() {
    local platform="$1"

    case "$platform" in
        portainer)
            if [[ -n "$SPECIFIC_APP" ]]; then
                print_warning "Skipping Portainer templates.json update for a single-app sync; run a full sync to publish it"
                return
            fi

            # Copy master templates.json and .template_id_counter to root
            local master_template="$CONVERTED_DIR/portainer/templates.json"
            local counter_file="$CONVERTED_DIR/portainer/.template_id_counter"
            
            if [[ -f "$master_template" ]]; then
                if [[ "$DRY_RUN" == "true" ]]; then
                    print_info "[DRY RUN] Would copy templates.json to Portainer root"
                else
                    cp "$master_template" "$PORTAINER_REPO/templates.json"
                    print_success "Copied templates.json to Portainer root"
                fi
            fi
            
            if [[ -f "$counter_file" ]]; then
                if [[ "$DRY_RUN" == "true" ]]; then
                    print_info "[DRY RUN] Would copy .template_id_counter to Portainer root"
                else
                    cp "$counter_file" "$PORTAINER_REPO/.template_id_counter"
                    print_success "Copied .template_id_counter to Portainer root"
                fi
            fi
            ;;
    esac
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
        
        # Umbrel's destination is the repo root, so only directories that contain
        # umbrel-app.yml are apps. Other platforms keep the existing denylist.
        if [[ "$platform" == "umbrel" ]]; then
            if ! is_platform_app_dir "$platform" "$dest_app_dir"; then
                continue
            fi
        elif [[ "$app_name" == "__tests__" ]] || \
           [[ "$app_name" =~ ^\. ]] || \
           [[ "$app_name" == "scripts" ]] || \
           [[ "$app_name" == "templates" ]]; then
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
    
    if [[ "$NO_CLEAN" != "true" ]] && [[ -z "$SPECIFIC_APP" ]]; then
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
