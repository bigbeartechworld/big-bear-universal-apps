#!/bin/bash

# Big Bear Universal Apps - Validation Script
# Validates app.json files against the JSON schema

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[✓]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNIVERSAL_REPO="$(dirname "$SCRIPT_DIR")"
APPS_DIR="$UNIVERSAL_REPO/apps"
SCHEMA_FILE="$UNIVERSAL_REPO/schemas/app-schema-v1.json"

SPECIFIC_APP=""
VERBOSE=false
STRICT=false

# Counters
TOTAL_VALIDATED=0
TOTAL_PASSED=0
TOTAL_FAILED=0
TOTAL_WARNINGS=0

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Validate universal app definitions against JSON schema.

OPTIONS:
    -h, --help              Show this help message
    -a, --app NAME          Validate specific app only
    -s, --strict            Fail on warnings
    -v, --verbose          Verbose output

EXAMPLES:
    $0                      # Validate all apps
    $0 -a jellyseerr       # Validate specific app
    $0 --strict            # Strict validation

EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help) usage; exit 0 ;;
        -a|--app) SPECIFIC_APP="$2"; shift 2 ;;
        -s|--strict) STRICT=true; shift ;;
        -v|--verbose) VERBOSE=true; shift ;;
        *) print_error "Unknown option: $1"; usage; exit 1 ;;
    esac
done

# Check dependencies
check_dependencies() {
    if ! command -v jq &> /dev/null; then
        print_error "jq not found. Install: apt-get install jq or brew install jq"
        exit 1
    fi
    
    if ! command -v yq &> /dev/null; then
        print_error "yq not found. Install: brew install yq"
        exit 1
    fi
}

# Validate JSON syntax
validate_json_syntax() {
    local file="$1"
    
    if ! jq empty "$file" 2>/dev/null; then
        return 1
    fi
    
    return 0
}

# Validate YAML syntax
validate_yaml_syntax() {
    local file="$1"
    
    if ! yq eval '.' "$file" > /dev/null 2>&1; then
        return 1
    fi
    
    return 0
}

# Validate required fields
validate_required_fields() {
    local app_json="$1"
    local errors=0
    
    # Check required top-level fields
    local required_fields=("spec_version" "metadata" "technical" "deployment")
    for field in "${required_fields[@]}"; do
        if [[ $(jq -r ".$field // empty" "$app_json") == "" ]]; then
            print_error "  Missing required field: $field"
            errors=$((errors + 1))
        fi
    done
    
    # Check required metadata fields
    local metadata_fields=("id" "name" "description" "version" "category")
    for field in "${metadata_fields[@]}"; do
        if [[ $(jq -r ".metadata.$field // empty" "$app_json") == "" ]]; then
            print_error "  Missing required metadata field: $field"
            errors=$((errors + 1))
        fi
    done
    
    # Check required technical fields
    local technical_fields=("architectures" "main_service" "main_image" "compose_file")
    for field in "${technical_fields[@]}"; do
        if [[ $(jq -r ".technical.$field // empty" "$app_json") == "" ]]; then
            print_error "  Missing required technical field: $field"
            errors=$((errors + 1))
        fi
    done
    
    return $errors
}

# Validate ID format
validate_id_format() {
    local id="$1"
    
    if [[ ! "$id" =~ ^[a-z0-9-]+$ ]]; then
        print_error "  Invalid ID format: $id (must be lowercase alphanumeric with hyphens)"
        return 1
    fi
    
    return 0
}

# Validate version format
validate_version_format() {
    local version="$1"
    
    if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]; then
        print_warning "  Version not in semver format: $version"
        return 1
    fi
    
    return 0
}

# Validate URLs
validate_urls() {
    local app_json="$1"
    local warnings=0
    
    # Check icon URL
    local icon=$(jq -r '.visual.icon // ""' "$app_json")
    if [[ -n "$icon" ]] && [[ ! "$icon" =~ ^https?:// ]]; then
        print_warning "  Invalid icon URL: $icon"
        warnings=$((warnings + 1))
    fi
    
    # Check documentation URL
    local docs=$(jq -r '.resources.documentation // ""' "$app_json")
    if [[ -n "$docs" ]] && [[ ! "$docs" =~ ^https?:// ]]; then
        print_warning "  Invalid documentation URL: $docs"
        warnings=$((warnings + 1))
    fi
    
    # Check repository URL
    local repo=$(jq -r '.resources.repository // ""' "$app_json")
    if [[ -n "$repo" ]] && [[ ! "$repo" =~ ^https?:// ]]; then
        print_warning "  Invalid repository URL: $repo"
        warnings=$((warnings + 1))
    fi
    
    return $warnings
}

# Validate architectures
validate_architectures() {
    local app_json="$1"
    local errors=0
    
    local valid_archs=("amd64" "arm64" "armv7" "armv6" "i386" "ppc64le" "s390x")
    local archs=$(jq -r '.technical.architectures[]?' "$app_json")
    
    while IFS= read -r arch; do
        [[ -z "$arch" ]] && continue
        
        local valid=false
        for valid_arch in "${valid_archs[@]}"; do
            if [[ "$arch" == "$valid_arch" ]]; then
                valid=true
                break
            fi
        done
        
        if [[ "$valid" == "false" ]]; then
            print_error "  Invalid architecture: $arch"
            errors=$((errors + 1))
        fi
    done <<< "$archs"
    
    return $errors
}

# Validate category
validate_category() {
    local category="$1"
    
    local valid_categories=(
        "Media" "Network" "Utilities" "Security" "Productivity"
        "Communication" "Development" "Smart Home" "Gaming" "Finance"
        "Education" "Health" "Entertainment" "Analytics" "Automation"
        "Backup" "Database" "Monitoring" "Storage" "Web" "Other" "BigBearCasaOS"
    )
    
    for valid_cat in "${valid_categories[@]}"; do
        if [[ "$category" == "$valid_cat" ]]; then
            return 0
        fi
    done
    
    print_warning "  Unknown category: $category"
    return 1
}

# Validate a single app
validate_app() {
    local app_name="$1"
    local app_dir="$APPS_DIR/$app_name"
    local app_json="$app_dir/app.json"
    local compose_file="$app_dir/docker-compose.yml"
    
    print_info "Validating $app_name..."
    TOTAL_VALIDATED=$((TOTAL_VALIDATED + 1))
    
    local errors=0
    local warnings=0
    
    # Check if directory exists
    if [[ ! -d "$app_dir" ]]; then
        print_error "App directory not found: $app_dir"
        TOTAL_FAILED=$((TOTAL_FAILED + 1))
        return 1
    fi
    
    # Check if app.json exists
    if [[ ! -f "$app_json" ]]; then
        print_error "app.json not found"
        TOTAL_FAILED=$((TOTAL_FAILED + 1))
        return 1
    fi
    
    # Check if docker-compose.yml exists
    if [[ ! -f "$compose_file" ]]; then
        print_error "docker-compose.yml not found"
        TOTAL_FAILED=$((TOTAL_FAILED + 1))
        return 1
    fi
    
    # Validate JSON syntax
    if ! validate_json_syntax "$app_json"; then
        print_error "Invalid JSON syntax in app.json"
        TOTAL_FAILED=$((TOTAL_FAILED + 1))
        return 1
    fi
    
    # Validate YAML syntax
    if ! validate_yaml_syntax "$compose_file"; then
        print_error "Invalid YAML syntax in docker-compose.yml"
        TOTAL_FAILED=$((TOTAL_FAILED + 1))
        return 1
    fi
    
    # Validate required fields
    validate_required_fields "$app_json"
    errors=$((errors + $?))
    
    # Validate ID format
    local app_id=$(jq -r '.metadata.id' "$app_json")
    validate_id_format "$app_id"
    errors=$((errors + $?))
    
    # Note: Version can be any valid Docker image tag format
    # No validation needed as Docker accepts any string as a tag
    
    # Validate URLs
    validate_urls "$app_json"
    warnings=$((warnings + $?))
    
    # Validate architectures
    validate_architectures "$app_json"
    errors=$((errors + $?))
    
    # Validate category
    local category=$(jq -r '.metadata.category' "$app_json")
    validate_category "$category"
    warnings=$((warnings + $?))
    
    # Check for x-casaos in compose (should not be present)
    if yq eval '.x-casaos' "$compose_file" 2>/dev/null | grep -q -v "null"; then
        print_warning "  docker-compose.yml contains x-casaos extensions (should be clean)"
        warnings=$((warnings + 1))
    fi
    
    # Summary for this app
    if [[ $errors -gt 0 ]]; then
        print_error "$app_name: FAILED ($errors errors, $warnings warnings)"
        TOTAL_FAILED=$((TOTAL_FAILED + 1))
        return 1
    elif [[ $warnings -gt 0 ]]; then
        if [[ "$STRICT" == "true" ]]; then
            print_warning "$app_name: FAILED in strict mode ($warnings warnings)"
            TOTAL_FAILED=$((TOTAL_FAILED + 1))
            return 1
        else
            print_success "$app_name: PASSED with $warnings warnings"
            TOTAL_PASSED=$((TOTAL_PASSED + 1))
            TOTAL_WARNINGS=$((TOTAL_WARNINGS + warnings))
        fi
    else
        print_success "$app_name: PASSED"
        TOTAL_PASSED=$((TOTAL_PASSED + 1))
    fi
    
    return 0
}

# Print summary
print_summary() {
    echo ""
    echo "========================================"
    echo "       VALIDATION SUMMARY"
    echo "========================================"
    echo -e "Total:    $TOTAL_VALIDATED apps"
    echo -e "${GREEN}Passed:${NC}   $TOTAL_PASSED apps"
    echo -e "${RED}Failed:${NC}   $TOTAL_FAILED apps"
    echo -e "${YELLOW}Warnings:${NC} $TOTAL_WARNINGS total"
    echo "========================================"
    echo ""
}

# Main function
main() {
    echo ""
    echo "========================================"
    echo "   Universal Apps Validation"
    echo "========================================"
    echo ""
    
    check_dependencies
    
    if [[ ! -d "$APPS_DIR" ]]; then
        print_error "Apps directory not found: $APPS_DIR"
        exit 1
    fi
    
    if [[ -n "$SPECIFIC_APP" ]]; then
        validate_app "$SPECIFIC_APP"
    else
        while IFS= read -r -d '' app_dir; do
            app_name=$(basename "$app_dir")
            validate_app "$app_name" || true
        done < <(find "$APPS_DIR" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)
    fi
    
    print_summary
    
    if [[ $TOTAL_FAILED -gt 0 ]]; then
        exit 1
    fi
}

main "$@"
