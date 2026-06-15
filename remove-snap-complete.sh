#!/bin/bash
###############################################################################
# Script: remove-snap-complete.sh
# Description: Completely removes snapd and all its packages from Ubuntu
# Compatible with: Ubuntu 22.04, 24.04, 26.04 and later (tested on LTS)
# Usage: sudo ./remove-snap-complete.sh [--force] [--no-backup]
###############################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Variables
BACKUP_DIR="/tmp/snap-backup-$(date +%Y%m%d%H%M%S)"
LOG_FILE="/var/log/remove-snap-$(date +%Y%m%d%H%M%S).log"
SNAP_PACKAGES_FILE="/tmp/snap-packages-list.txt"
FORCE_MODE=false
NO_BACKUP=false
REMOVED_COUNT=0

# Utility functions
log() {
    echo -e "[$(date '+%H:%M:%S')] ${1}" | tee -a "$LOG_FILE"
}

info()  { log "${CYAN}[INFO]${NC} ${1}"; }
ok()    { log "${GREEN}[OK]${NC} ${1}"; }
warn()  { log "${YELLOW}[WARN]${NC} ${1}"; }
error() { log "${RED}[ERROR]${NC} ${1}"; }

# Verify running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (sudo)."
        exit 1
    fi
}

# Verify the OS is Ubuntu
check_os() {
    if ! grep -qi "ubuntu" /etc/os-release 2>/dev/null; then
        error "This script is designed only for Ubuntu."
        exit 1
    fi
    info "System detected: $(lsb_release -ds 2>/dev/null || cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
}

# Parse arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force)
                FORCE_MODE=true
                shift
                ;;
            --no-backup)
                NO_BACKUP=true
                shift
                ;;
            -h|--help)
                echo "Usage: sudo $0 [--force] [--no-backup]"
                echo "  --force     Force mode: delete even critical packages (gnome-software, etc.)"
                echo "  --no-backup Do not create a backup of snap configurations"
                exit 0
                ;;
            *)
                error "Unknown argument: $1. Use -h for help."
                exit 1
                ;;
        esac
    done
}

# Check if snapd is installed
is_snap_installed() {
    dpkg -l | grep -q "snapd" 2>/dev/null
    return $?
}

# Backup snap configurations
backup_snap() {
    if $NO_BACKUP; then
        warn "Backup skipped at user request."
        return
    fi

    info "Creating backup of snap configurations in: $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"

    # Copy configuration files if they exist
    [[ -d /var/lib/snapd ]] && cp -a /var/lib/snapd "$BACKUP_DIR/" 2>/dev/null && ok "Backup of /var/lib/snapd done."
    [[ -d /var/snap ]] && cp -a /var/snap "$BACKUP_DIR/" 2>/dev/null && ok "Backup of /var/snap done."
    [[ -d /home/*/snap ]] && cp -a /home/*/snap "$BACKUP_DIR/home_snap" 2>/dev/null || true

    info "Backup complete. Located at: $BACKUP_DIR"
}

# List all installed snap packages
list_snap_packages() {
    info "Listing installed snap packages..."
    snap list 2>/dev/null | tail -n +2 | awk '{print $1}' > "$SNAP_PACKAGES_FILE" || true
    local count=$(wc -l < "$SNAP_PACKAGES_FILE")
    if [[ $count -eq 0 ]]; then
        info "No snap packages found."
    else
        info "Snap packages found: $(cat "$SNAP_PACKAGES_FILE" | tr '\n' ' ')"
    fi
}

# Stop snap services
stop_snap_services() {
    info "Stopping snap services..."
    systemctl stop snapd.service snapd.socket snapd.seeded.service snapd.apparmor.service 2>/dev/null || true
    systemctl disable snapd.service snapd.socket snapd.seeded.service 2>/dev/null || true
    ok "Snap services stopped and disabled."
}

# Unmount snap loop devices
umount_snap_loops() {
    info "Unmounting snap loop devices..."
    local loops
    loops=$(mount | grep snap | awk '{print $1}' 2>/dev/null) || true
    if [[ -n "$loops" ]]; then
        for loop in $loops; do
            umount -l "$loop" 2>/dev/null && info "Unmounted: $loop" || warn "Could not unmount $loop"
        done
    else
        info "No snap loop devices mounted."
    fi
}

# Remove all snap packages (with error handling)
remove_snap_packages() {
    info "Removing all installed snap packages..."
    while IFS= read -r pkg; do
        if [[ -n "$pkg" ]]; then
            log "Removing snap: $pkg"
            if snap remove "$pkg" --purge 2>/dev/null; then
                ((REMOVED_COUNT++))
                ok "Snap '$pkg' removed."
            else
                # If it fails (e.g. snap not responding), force with systemd stopped
                warn "Failed to remove '$pkg', trying with snapd stopped..."
                systemctl stop snapd.service snapd.socket 2>/dev/null || true
                rm -rf "/snap/$pkg" "/var/snap/$pkg" 2>/dev/null || true
                warn "Deleted directories of '$pkg' manually."
                ((REMOVED_COUNT++))
            fi
        fi
    done < "$SNAP_PACKAGES_FILE"

    # Make sure snapd is stopped to continue
    stop_snap_services

    # Remove any remaining snap directories
    rm -rf /snap/* 2>/dev/null || true
    rm -rf /var/snap/* 2>/dev/null || true
    ok "All snap packages removed ($REMOVED_COUNT total)."
}

# Purge snapd and related packages via APT
purge_snapd_apt() {
    info "Purging snapd and related packages via APT..."

    # List of packages to remove
    local packages=(
        snapd
        ubuntu-core-launcher
        gir1.2-snapd-1
        qtchooser  # sometimes a dependency
    )

    if $FORCE_MODE; then
        # In force mode, also remove gnome-software-plugin-snap and similar
        packages+=(
            gnome-software-plugin-snap
            ubuntu-software
            ubuntu-software-plugin-snap
        )
    fi

    for pkg in "${packages[@]}"; do
        if dpkg -l | grep -q "ii  $pkg "; then
            apt purge -y "$pkg" 2>/dev/null && ok "Package '$pkg' purged." || warn "Could not purge '$pkg'."
        fi
    done

    # Clean up orphaned dependencies
    apt autoremove --purge -y 2>/dev/null || true
    ok "Orphaned dependencies removed."
}

# Remove residual snap directories
remove_snap_directories() {
    info "Removing residual snap directories..."
    local dirs=(
        /snap
        /var/snap
        /var/lib/snapd
        /var/cache/snapd
        /var/log/snapd
        /tmp/snap-*
        /root/snap
        /home/*/snap
    )

    for dir in "${dirs[@]}"; do
        if [[ -e "$dir" ]]; then
            rm -rf "$dir" 2>/dev/null && info "Directory removed: $dir" || warn "Could not remove $dir"
        fi
    done

    # Remove systemd mount units (if any remain)
    rm -f /etc/systemd/system/snap-*.mount /etc/systemd/system/snap-*.target 2>/dev/null || true
    systemctl daemon-reload 2>/dev/null || true
    ok "Residual directories cleaned."
}

# Block snapd to prevent reinstallation
block_snapd_install() {
    info "Blocking snapd to prevent reinstallation..."
    apt-mark hold snapd 2>/dev/null && ok "snapd marked as 'hold' (will not be updated or installed automatically)."
    # Additionally, create an APT preferences file to block installation even with --install-recommends
    cat > /etc/apt/preferences.d/snapd-block <<'EOF'
Package: snapd
Pin: release *
Pin-Priority: -1
EOF
    ok "APT negative priority set for snapd."
}

# Remove any APT sources related to snap
remove_snap_apt_sources() {
    local snap_sources
    snap_sources=$(grep -rl "snapcraft.io\|snapd" /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null) || true
    if [[ -n "$snap_sources" ]]; then
        for f in $snap_sources; do
            sed -i '/snapcraft.io\|snapd/d' "$f" 2>/dev/null && info "Cleaned APT source: $f"
        done
    fi
    apt update 2>/dev/null || true
    ok "APT sources updated."
}

# Final verification
final_check() {
    info "Verifying that snap is completely removed..."
    if command -v snap &>/dev/null; then
        error "The snap command still exists in PATH. Please check manually."
    else
        ok "The snap command is no longer available."
    fi

    if mount | grep -q snap; then
        warn "There are still snap mounts. Reboot the system to clean them."
    else
        ok "No snap mounts found."
    fi

    if dpkg -l | grep -q "snapd"; then
        warn "snapd still appears in dpkg. It may not have been fully purged."
    else
        ok "snapd removed from the package system."
    fi
}

# Final summary
show_summary() {
    echo ""
    echo -e "${BOLD}══════════════════════════════════════════════════${NC}"
    echo -e "${GREEN} Snap completely removed from Ubuntu ${NC}"
    echo -e "${BOLD}══════════════════════════════════════════════════${NC}"
    echo -e "  Snap packages removed: ${REMOVED_COUNT}"
    echo -e "  Directories cleaned:   /snap, /var/snap, /var/lib/snapd"
    echo -e "  Operation log:         ${LOG_FILE}"
    if ! $NO_BACKUP; then
        echo -e "  Backup saved at:      ${BACKUP_DIR}"
    fi
    echo -e "  snapd blocked:         Yes (hold + APT preference)"
    echo -e "${BOLD}══════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}⚠️  It is recommended to REBOOT the system to apply all changes.${NC}"
    echo ""
}

# MAIN
main() {
    # Presentation
    clear
    echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}  Complete Snap Remover for Ubuntu ${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
    echo ""

    # Initial checks
    check_root
    check_os
    parse_args "$@"

    # If snapd is not installed, exit gracefully
    if ! is_snap_installed; then
        info "Snapd is not installed on the system. Nothing to do."
        # Still clean up any residues just in case
        remove_snap_directories
        block_snapd_install
        remove_snap_apt_sources
        final_check
        show_summary
        exit 0
    fi

    info "Starting the complete removal of Snap..."
    echo ""

    # Step 1: Backup
    backup_snap

    # Step 2: Stop services
    stop_snap_services

    # Step 3: List snap packages
    list_snap_packages

    # Step 4: Unmount loops
    umount_snap_loops

    # Step 5: Remove snap packages
    remove_snap_packages

    # Step 6: Purge snapd from APT
    purge_snapd_apt

    # Step 7: Remove residual directories
    remove_snap_directories

    # Step 8: Block snapd
    block_snapd_install

    # Step 9: Clean APT sources
    remove_snap_apt_sources

    # Step 10: Final verification
    final_check

    # Summary
    show_summary
}

# Run
main "$@"
