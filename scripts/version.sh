#!/bin/bash
# Version Management Script
# Helps create new versions by updating CHANGELOG.md and creating git tags

set -euo pipefail

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script directory
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly CHANGELOG="${PROJECT_ROOT}/CHANGELOG.md"

usage() {
    cat << EOF
${BLUE}Version Management Script${NC}

Usage: $0 <command> [options]

Commands:
    current             Show current version
    bump <type>         Bump version (type: major, minor, patch)
    set <version>       Set specific version (e.g., 2.1.0)
    tag                 Create git tag for current version
    prepare <version>   Prepare CHANGELOG for new version
    
Options:
    -h, --help         Show this help message
    -d, --dry-run      Show what would be done without making changes

Examples:
    $0 current                    # Show current version
    $0 bump patch                 # Bump patch version (2.0.0 -> 2.0.1)
    $0 bump minor                 # Bump minor version (2.0.0 -> 2.1.0)
    $0 bump major                 # Bump major version (2.0.0 -> 3.0.0)
    $0 set 2.1.0                  # Set version to 2.1.0
    $0 prepare 2.1.0              # Prepare CHANGELOG for version 2.1.0
    $0 tag                        # Create git tag for current version

EOF
    exit 0
}

error() {
    echo -e "${RED}Error: $*${NC}" >&2
    exit 1
}

success() {
    echo -e "${GREEN}✅ $*${NC}"
}

info() {
    echo -e "${BLUE}ℹ️  $*${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $*${NC}"
}

get_current_version() {
    if [ ! -f "$CHANGELOG" ]; then
        error "CHANGELOG.md not found"
    fi
    
    # Extract first version from CHANGELOG
    grep -m 1 -oP '(?<=## \[)[0-9]+\.[0-9]+\.[0-9]+(?=\])' "$CHANGELOG" || echo "0.0.0"
}

validate_version() {
    local version="$1"
    if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        error "Invalid version format: $version (expected: X.Y.Z)"
    fi
}

bump_version() {
    local bump_type="$1"
    local current_version
    current_version=$(get_current_version)
    
    IFS='.' read -r major minor patch <<< "$current_version"
    
    case "$bump_type" in
        major)
            major=$((major + 1))
            minor=0
            patch=0
            ;;
        minor)
            minor=$((minor + 1))
            patch=0
            ;;
        patch)
            patch=$((patch + 1))
            ;;
        *)
            error "Invalid bump type: $bump_type (use: major, minor, or patch)"
            ;;
    esac
    
    echo "${major}.${minor}.${patch}"
}

prepare_changelog() {
    local new_version="$1"
    local current_date
    current_date=$(date +%Y-%m-%d)
    
    if ! grep -q "## \[Unreleased\]" "$CHANGELOG"; then
        error "CHANGELOG.md doesn't contain [Unreleased] section"
    fi
    
    # Create backup
    cp "$CHANGELOG" "${CHANGELOG}.backup"
    
    # Replace [Unreleased] with new version
    sed -i.tmp "s/## \[Unreleased\]/## [$new_version] - $current_date/" "$CHANGELOG"
    rm -f "${CHANGELOG}.tmp"
    
    # Add new Unreleased section at the top
    local unreleased_section="## [Unreleased]

### Added

### Changed

### Fixed

### Deprecated

### Removed

### Security

"
    
    # Insert after the header (line 8 typically)
    sed -i.tmp "8a\\
$unreleased_section" "$CHANGELOG"
    rm -f "${CHANGELOG}.tmp"
    
    success "CHANGELOG.md prepared for version $new_version"
    info "Please review and edit the CHANGELOG.md before committing"
}

create_tag() {
    local version
    version=$(get_current_version)
    
    if [ "$version" = "0.0.0" ]; then
        error "No valid version found in CHANGELOG.md"
    fi
    
    # Check if tag exists
    if git rev-parse "v$version" >/dev/null 2>&1; then
        warning "Tag v$version already exists"
        return 1
    fi
    
    # Check if we're on main branch
    local current_branch
    current_branch=$(git rev-parse --abbrev-ref HEAD)
    if [ "$current_branch" != "main" ]; then
        warning "Not on main branch (currently on: $current_branch)"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    # Create and push tag
    git tag -a "v$version" -m "Release version $version"
    git push origin "v$version"
    
    success "Created and pushed tag v$version"
    info "This will trigger the release workflow on GitHub"
}

show_current_version() {
    local version
    version=$(get_current_version)
    
    echo -e "${BLUE}Current version:${NC} ${GREEN}$version${NC}"
    
    # Check if tag exists
    if git rev-parse "v$version" >/dev/null 2>&1; then
        echo -e "${GREEN}Git tag exists${NC}"
    else
        echo -e "${YELLOW}Git tag does not exist yet${NC}"
    fi
}

main() {
    cd "$PROJECT_ROOT"
    
    if [ $# -eq 0 ]; then
        usage
    fi
    
    local command="$1"
    shift
    
    case "$command" in
        current)
            show_current_version
            ;;
        bump)
            if [ $# -eq 0 ]; then
                error "Bump type required (major, minor, or patch)"
            fi
            local new_version
            new_version=$(bump_version "$1")
            info "Current version: $(get_current_version)"
            info "New version: $new_version"
            echo
            read -p "Prepare CHANGELOG for version $new_version? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                prepare_changelog "$new_version"
            fi
            ;;
        set)
            if [ $# -eq 0 ]; then
                error "Version required (e.g., 2.1.0)"
            fi
            validate_version "$1"
            prepare_changelog "$1"
            ;;
        prepare)
            if [ $# -eq 0 ]; then
                error "Version required (e.g., 2.1.0)"
            fi
            validate_version "$1"
            prepare_changelog "$1"
            ;;
        tag)
            create_tag
            ;;
        -h|--help)
            usage
            ;;
        *)
            error "Unknown command: $command"
            usage
            ;;
    esac
}

main "$@"

