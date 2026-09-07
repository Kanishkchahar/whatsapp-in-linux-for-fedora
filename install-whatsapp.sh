#!/usr/bin/env bash
# ==============================================================================
# WhatsApp Desktop App Automated Installer for Linux
# Built with Nativefier — works on Fedora, Ubuntu, Arch, openSUSE, and more
# Version: 2.0.0
# ==============================================================================

set -euo pipefail

# Script version
VERSION="2.0.0"

# Minimum supported Node.js major version
MIN_NODE_MAJOR=16

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ---------------------------------------------------------------------------
# Configuration — all paths are portable, no hardcoded user home directories
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="/opt/WhatsApp"
DESKTOP_DIR="${HOME}/.local/share/applications"
DESKTOP_FILE="${DESKTOP_DIR}/whatsapp.desktop"
ICON_BASE_DIR="${HOME}/.local/share/icons/hicolor"
AUTOSTART_DIR="${HOME}/.config/autostart"
APP_NAME="WhatsApp"
APP_URL="https://web.whatsapp.com/"
TEMP_DIR=""
BUILT_FOLDER=""  # set by build_whatsapp() to avoid stdout-capture issues

# Icon sizes to install in the hicolor theme
ICON_SIZES=(16 32 48 64 128 256 512)

# Icon: use bundled icon.png if present, otherwise download later
if [[ -f "${SCRIPT_DIR}/icon.png" ]]; then
    DEFAULT_ICON_SOURCE="${SCRIPT_DIR}/icon.png"
else
    DEFAULT_ICON_SOURCE=""
fi

# ---------------------------------------------------------------------------
# Spinner — animated progress indicator for long-running steps
# ---------------------------------------------------------------------------
SPINNER_PID=""

spinner_start() {
    local msg="${1:-Please wait...}"
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    (
        local i=0
        while true; do
            printf "\r  ${CYAN}${frames[$i]}${NC}  ${DIM}%s${NC}   " "$msg"
            i=$(( (i + 1) % ${#frames[@]} ))
            sleep 0.1
        done
    ) &
    SPINNER_PID=$!
    disown "$SPINNER_PID" 2>/dev/null || true
}

spinner_stop() {
    if [[ -n "${SPINNER_PID}" ]]; then
        kill "${SPINNER_PID}" 2>/dev/null || true
        SPINNER_PID=""
        printf "\r\033[K"   # erase the spinner line
    fi
}

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------
log_info()    { spinner_stop; echo -e "  ${BLUE}${BOLD}i${NC}  $*"; }
log_success() { spinner_stop; echo -e "  ${GREEN}${BOLD}+${NC}  $*"; }
log_warn()    { spinner_stop; echo -e "  ${YELLOW}${BOLD}!${NC}  $*"; }
log_error()   { spinner_stop; echo -e "  ${RED}${BOLD}x${NC}  $*" >&2; }
log_step()    { spinner_stop; echo -e "\n${MAGENTA}${BOLD}>> $*${NC}"; }

print_header() {
    echo -e "${CYAN}${BOLD}"
    echo "  ============================================================"
    echo "       WhatsApp Desktop App Installer for Linux"
    printf "                    Version %s\n" "${VERSION}"
    echo "  ============================================================"
    echo -e "${NC}"
}

print_summary() {
    local target_dir="$1"
    local display_server="$2"
    echo ""
    echo -e "${GREEN}${BOLD}  ============================================================${NC}"
    echo -e "${GREEN}${BOLD}         Installation Complete!${NC}"
    echo -e "${GREEN}${BOLD}  ============================================================${NC}"
    echo ""
    echo -e "  ${BOLD}Installed to :${NC}  ${target_dir}"
    echo -e "  ${BOLD}Desktop file :${NC}  ${DESKTOP_FILE}"
    echo -e "  ${BOLD}Display mode :${NC}  ${display_server}"
    echo -e "  ${BOLD}Launch       :${NC}  Search ${CYAN}'WhatsApp'${NC} in your application menu"
    echo -e "  ${BOLD}Terminal     :${NC}  ${CYAN}${target_dir}/WhatsApp &${NC}"
    echo ""
}

# ---------------------------------------------------------------------------
# Cleanup on exit — remove temp dir and stop any running spinner
# ---------------------------------------------------------------------------
cleanup() {
    spinner_stop
    if [[ -n "${TEMP_DIR:-}" && -d "${TEMP_DIR}" ]]; then
        log_info "Cleaning up temporary build files..."
        rm -rf "${TEMP_DIR}"
    fi
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------
show_help() {
    cat <<EOF

Usage: $(basename "$0") [OPTIONS]

Automates building and installing WhatsApp Web as a native desktop application
on Linux. Works on Fedora, Ubuntu, Arch, openSUSE, and any distro with
dnf, apt, pacman, or zypper.

Options:
  -i, --icon <path>     Path to a custom WhatsApp icon (PNG or WebP)
                        (default: bundled icon.png, or auto-downloaded)
  -d, --dir <path>      Installation target directory
                        (default: ${INSTALL_DIR})
  -u, --uninstall       Uninstall WhatsApp desktop app and all shortcuts
      --update          Force re-install / update an existing installation
      --autostart       Add WhatsApp to login autostart
      --wayland         Force Wayland rendering mode (default: auto-detect)
  -v, --version         Show installer version and exit
  -h, --help            Show this help message and exit

Examples:
  ./$(basename "$0")
  ./$(basename "$0") --icon /path/to/custom/whatsapp.png
  ./$(basename "$0") --dir ~/.local/share/WhatsApp
  ./$(basename "$0") --update
  ./$(basename "$0") --autostart
  ./$(basename "$0") --uninstall

EOF
}

# ---------------------------------------------------------------------------
# Internet connectivity check
# ---------------------------------------------------------------------------
check_connectivity() {
    log_info "Checking internet connectivity..."
    local ok=0
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --connect-timeout 6 "https://web.whatsapp.com" -o /dev/null 2>/dev/null && ok=1
    elif command -v wget >/dev/null 2>&1; then
        wget -q --timeout=6 --spider "https://web.whatsapp.com" 2>/dev/null && ok=1
    fi
    if [[ $ok -eq 1 ]]; then
        log_success "Internet connection verified."
    else
        log_warn "Could not reach web.whatsapp.com — check your connection."
        log_warn "Continuing anyway; the build may fail if packages need to be downloaded."
    fi
}

# ---------------------------------------------------------------------------
# Package manager detection
# ---------------------------------------------------------------------------
detect_package_manager() {
    if   command -v dnf     >/dev/null 2>&1; then echo "dnf"
    elif command -v apt-get >/dev/null 2>&1; then echo "apt"
    elif command -v pacman  >/dev/null 2>&1; then echo "pacman"
    elif command -v zypper  >/dev/null 2>&1; then echo "zypper"
    else echo "unknown"
    fi
}

# ---------------------------------------------------------------------------
# Install Node.js + npm via the system package manager
# ---------------------------------------------------------------------------
install_system_packages() {
    local pm
    pm=$(detect_package_manager)
    log_info "Detected package manager: ${pm}"

    case "$pm" in
        dnf)
            log_info "Installing nodejs and npm via dnf..."
            sudo dnf install -y nodejs npm
            ;;
        apt)
            log_info "Installing nodejs and npm via apt..."
            sudo apt-get update -qq
            sudo apt-get install -y nodejs npm
            ;;
        pacman)
            log_info "Installing nodejs and npm via pacman..."
            sudo pacman -Sy --noconfirm nodejs npm
            ;;
        zypper)
            log_info "Installing nodejs and npm via zypper..."
            sudo zypper install -y nodejs npm
            ;;
        *)
            log_error "Unsupported package manager."
            log_error "Please install Node.js (v${MIN_NODE_MAJOR}+) and npm manually."
            log_error "  -> https://nodejs.org/en/download/"
            exit 1
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Verify Node.js meets the minimum version requirement
# ---------------------------------------------------------------------------
check_node_version() {
    local raw_ver
    raw_ver=$(node --version 2>/dev/null | sed 's/v//')
    local major
    major=$(echo "$raw_ver" | cut -d. -f1)

    if [[ "$major" -lt "$MIN_NODE_MAJOR" ]]; then
        log_error "Node.js v${raw_ver} is too old (minimum required: v${MIN_NODE_MAJOR})."
        log_error "Upgrade Node.js:  https://nodejs.org/en/download/"
        exit 1
    fi
    log_success "Node.js v${raw_ver} OK"
}

# ---------------------------------------------------------------------------
# Check and install all dependencies
# ---------------------------------------------------------------------------
check_dependencies() {
    log_step "Checking Prerequisites"

    # Node.js and npm
    if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
        log_warn "Node.js or npm not found — attempting automatic installation..."
        install_system_packages
    fi

    check_node_version
    log_success "npm v$(npm --version) OK"

    # Nativefier
    if ! command -v nativefier >/dev/null 2>&1; then
        log_info "Nativefier not found — installing globally via npm..."
        spinner_start "Installing Nativefier..."
        if [[ "$EUID" -ne 0 ]]; then
            sudo npm install -g nativefier --quiet 2>/dev/null
        else
            npm install -g nativefier --quiet 2>/dev/null
        fi
        spinner_stop
    fi
    log_success "Nativefier $(nativefier --version 2>/dev/null || echo 'installed') OK"
}

# ---------------------------------------------------------------------------
# Download a fallback WhatsApp icon from the internet
# ---------------------------------------------------------------------------
download_icon() {
    local dest="$1"
    local urls=(
        "https://upload.wikimedia.org/wikipedia/commons/thumb/6/6b/WhatsApp.svg/512px-WhatsApp.svg.png"
        "https://upload.wikimedia.org/wikipedia/commons/5/5e/WhatsApp_icon.png"
    )

    log_warn "No local icon found — downloading from the web..."

    for url in "${urls[@]}"; do
        if command -v curl >/dev/null 2>&1; then
            if curl -fsSL --connect-timeout 10 "$url" -o "$dest" 2>/dev/null; then
                log_success "Icon downloaded."
                return 0
            fi
        elif command -v wget >/dev/null 2>&1; then
            if wget -q --timeout=10 "$url" -O "$dest" 2>/dev/null; then
                log_success "Icon downloaded."
                return 0
            fi
        fi
    done

    return 1
}

# ---------------------------------------------------------------------------
# Resize/convert a single image to a given dimension and save as PNG
# ---------------------------------------------------------------------------
convert_icon_size() {
    local src="$1"
    local dest="$2"
    local size="$3"

    if command -v python3 >/dev/null 2>&1 && python3 -c "import PIL" >/dev/null 2>&1; then
        python3 - <<PYEOF
from PIL import Image
img = Image.open("${src}")
if img.mode != 'RGBA':
    img = img.convert('RGBA')
img.resize((${size}, ${size}), Image.Resampling.LANCZOS).save("${dest}", 'PNG')
PYEOF
    elif command -v magick >/dev/null 2>&1; then
        magick "${src}" -resize "${size}x${size}!" -background none "${dest}" 2>/dev/null
    elif command -v convert >/dev/null 2>&1; then
        convert "${src}" -resize "${size}x${size}!" -background none "${dest}" 2>/dev/null
    elif command -v ffmpeg >/dev/null 2>&1; then
        ffmpeg -y -i "${src}" -vf "scale=${size}:${size}" "${dest}" >/dev/null 2>&1
    else
        cp "${src}" "${dest}"
    fi
}

# ---------------------------------------------------------------------------
# Process icon: convert raw source to 512x512 RGBA PNG
# ---------------------------------------------------------------------------
process_icon() {
    local raw_icon="$1"
    local output_icon="$2"

    # Download a fallback if no local icon is available
    if [[ -z "$raw_icon" || ! -f "$raw_icon" ]]; then
        local downloaded="${TEMP_DIR}/whatsapp-downloaded.png"
        if download_icon "$downloaded"; then
            raw_icon="$downloaded"
        else
            log_error "Could not find or download a WhatsApp icon."
            log_error "Supply one manually:  --icon /path/to/icon.png"
            exit 1
        fi
    fi

    log_info "Processing icon: ${raw_icon}"

    # Detect PNG without a converter as last resort
    local is_png=0
    if file "$raw_icon" 2>/dev/null | grep -q "PNG image data"; then
        is_png=1
    fi

    if command -v python3 >/dev/null 2>&1 && python3 -c "import PIL" >/dev/null 2>&1; then
        python3 - <<PYEOF
from PIL import Image
import sys
try:
    img = Image.open("${raw_icon}")
    if img.mode != 'RGBA':
        img = img.convert('RGBA')
    img.resize((512, 512), Image.Resampling.LANCZOS).save("${output_icon}", 'PNG')
except Exception as e:
    print(f"PIL error: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF
    elif command -v magick >/dev/null 2>&1; then
        magick "${raw_icon}" -resize 512x512! -background none -gravity center "${output_icon}"
    elif command -v convert >/dev/null 2>&1; then
        convert "${raw_icon}" -resize 512x512! -background none -gravity center "${output_icon}"
    elif command -v ffmpeg >/dev/null 2>&1; then
        ffmpeg -y -i "${raw_icon}" -vf "scale=512:512" "${output_icon}" >/dev/null 2>&1
    elif [[ $is_png -eq 1 ]]; then
        cp "${raw_icon}" "${output_icon}"
    else
        log_error "Cannot convert icon to PNG."
        log_error "Please install python3-pillow or ImageMagick and re-run."
        exit 1
    fi

    log_success "Icon prepared (512x512 RGBA PNG)."
}

# ---------------------------------------------------------------------------
# Install icon into every hicolor size directory
# ---------------------------------------------------------------------------
install_icons() {
    local icon_512="$1"

    log_info "Installing icons in ${#ICON_SIZES[@]} sizes..."

    for size in "${ICON_SIZES[@]}"; do
        local size_dir="${ICON_BASE_DIR}/${size}x${size}/apps"
        mkdir -p "${size_dir}"
        convert_icon_size "${icon_512}" "${size_dir}/whatsapp.png" "${size}"
    done

    log_success "Icons installed: ${ICON_SIZES[*]} px"
}

# ---------------------------------------------------------------------------
# Auto-detect Wayland vs X11
# ---------------------------------------------------------------------------
detect_display_server() {
    if [[ "${XDG_SESSION_TYPE:-}" == "wayland" ]] || [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
        echo "wayland"
    else
        echo "x11"
    fi
}

# ---------------------------------------------------------------------------
# Build the Electron/WhatsApp app with Nativefier
# ---------------------------------------------------------------------------
build_whatsapp() {
    local icon_path="$1"
    local build_out_dir="$2"
    local nativefier_log="${build_out_dir}/nativefier.log"

    log_step "Building WhatsApp App"
    log_info "  URL       : ${APP_URL}"
    log_info "  App Name  : ${APP_NAME}"
    log_info "  Output    : ${build_out_dir}"

    spinner_start "Building with Nativefier (this may take a few minutes)..."

    if ! nativefier "${APP_URL}" \
            --name "${APP_NAME}" \
            --single-instance \
            --icon "${icon_path}" \
            --tray start-in-tray \
            --zoom 1.0 \
            --internal-urls ".*whatsapp\\.com.*" \
            --background-color "#128C7E" \
            "${build_out_dir}" \
            > "${nativefier_log}" 2>&1; then
        spinner_stop
        log_error "Nativefier build failed. Build log:"
        cat "${nativefier_log}" >&2
        exit 1
    fi

    spinner_stop

    local built_folder
    built_folder=$(find "${build_out_dir}" -maxdepth 1 -type d -name "WhatsApp-linux-*" | head -n 1)

    if [[ -z "${built_folder}" || ! -d "${built_folder}" ]]; then
        log_error "Nativefier output directory not found in ${build_out_dir}."
        log_error "Check build log: ${nativefier_log}"
        exit 1
    fi

    if [[ ! -f "${built_folder}/WhatsApp" ]]; then
        log_error "WhatsApp binary not found in ${built_folder}."
        exit 1
    fi

    BUILT_FOLDER="${built_folder}"
    log_success "WhatsApp app built successfully."
}

# ---------------------------------------------------------------------------
# Install app files to the target directory
# ---------------------------------------------------------------------------
install_whatsapp() {
    local source_folder="$1"
    local target_dir="$2"
    local icon_path="$3"

    log_step "Installing WhatsApp"
    log_info "Target: ${target_dir}"

    # Determine whether sudo is needed
    local use_sudo=""
    if [[ ! -w "$(dirname "${target_dir}")" ]] \
       || [[ -d "${target_dir}" && ! -w "${target_dir}" ]]; then
        use_sudo="sudo"
    fi

    if [[ -d "${target_dir}" ]]; then
        log_warn "Existing installation found at ${target_dir}. Replacing..."
        spinner_start "Removing old installation..."
        ${use_sudo} rm -rf "${target_dir}"
        spinner_stop
    fi

    spinner_start "Copying application files..."
    ${use_sudo} mkdir -p "$(dirname "${target_dir}")"
    ${use_sudo} cp -r "${source_folder}" "${target_dir}"
    ${use_sudo} cp "${icon_path}" "${target_dir}/icon.png"
    ${use_sudo} chmod -R u+rwX,go+rX "${target_dir}"
    ${use_sudo} chmod +x "${target_dir}/WhatsApp"
    spinner_stop

    log_success "Installed to ${target_dir}."
}

# ---------------------------------------------------------------------------
# Create .desktop file and register with the desktop environment
# ---------------------------------------------------------------------------
setup_desktop_shortcut() {
    local target_dir="$1"
    local icon_path="$2"
    local display_server="$3"

    log_step "Setting Up Desktop Integration"

    mkdir -p "${DESKTOP_DIR}"

    # Build Electron/Chromium flags for the detected display server
    local gdk_backend exec_flags
    if [[ "$display_server" == "wayland" ]]; then
        gdk_backend="wayland"
        exec_flags="--no-sandbox --enable-features=UseOzonePlatform --ozone-platform=wayland"
        log_info "Configuring for Wayland."
    else
        gdk_backend="x11"
        exec_flags="--no-sandbox --ozone-platform=x11"
        log_info "Configuring for X11."
    fi

    # Install multi-size icons
    install_icons "${icon_path}"

    # Write the .desktop file (use icon theme name — not a hard-coded path)
    cat > "${DESKTOP_FILE}" <<EOF
[Desktop Entry]
Name=WhatsApp
GenericName=Messaging App
Comment=WhatsApp Web Desktop Client
Exec=env GDK_BACKEND=${gdk_backend} ${target_dir}/WhatsApp ${exec_flags} %U
Icon=whatsapp
Terminal=false
Type=Application
Version=1.5
Categories=Network;Chat;InstantMessaging;
StartupWMClass=WhatsApp
StartupNotify=true
MimeType=x-scheme-handler/whatsapp;
Keywords=WhatsApp;Chat;Messaging;IM;
EOF

    chmod +x "${DESKTOP_FILE}"
    log_success "Desktop entry: ${DESKTOP_FILE}"

    # Register whatsapp:// URL scheme
    if command -v xdg-mime >/dev/null 2>&1; then
        xdg-mime default whatsapp.desktop x-scheme-handler/whatsapp 2>/dev/null || true
        log_success "Registered whatsapp:// URL scheme handler."
    fi

    # Refresh desktop databases
    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database "${DESKTOP_DIR}" 2>/dev/null || true
    fi
    if command -v kbuildsycoca6 >/dev/null 2>&1; then
        kbuildsycoca6 2>/dev/null || true
    elif command -v kbuildsycoca5 >/dev/null 2>&1; then
        kbuildsycoca5 2>/dev/null || true
    fi
    if command -v gtk-update-icon-cache >/dev/null 2>&1; then
        gtk-update-icon-cache -f -t "${HOME}/.local/share/icons/hicolor" 2>/dev/null || true
    fi

    log_success "Desktop database and icon cache refreshed."
}

# ---------------------------------------------------------------------------
# Optional: add WhatsApp to the login autostart
# ---------------------------------------------------------------------------
setup_autostart() {
    local target_dir="$1"
    local display_server="$2"

    log_step "Setting Up Autostart"
    mkdir -p "${AUTOSTART_DIR}"

    local gdk_backend exec_flags
    if [[ "$display_server" == "wayland" ]]; then
        gdk_backend="wayland"
        exec_flags="--no-sandbox --enable-features=UseOzonePlatform --ozone-platform=wayland"
    else
        gdk_backend="x11"
        exec_flags="--no-sandbox --ozone-platform=x11"
    fi

    cat > "${AUTOSTART_DIR}/whatsapp.desktop" <<EOF
[Desktop Entry]
Name=WhatsApp
GenericName=Messaging App
Comment=Start WhatsApp at login
Exec=env GDK_BACKEND=${gdk_backend} ${target_dir}/WhatsApp ${exec_flags}
Icon=whatsapp
Terminal=false
Type=Application
Categories=Network;Chat;InstantMessaging;
StartupWMClass=WhatsApp
StartupNotify=false
Hidden=false
X-GNOME-Autostart-enabled=true
EOF

    chmod +x "${AUTOSTART_DIR}/whatsapp.desktop"
    log_success "Autostart entry created: ${AUTOSTART_DIR}/whatsapp.desktop"
    log_info "WhatsApp will now launch automatically at login."
}

# ---------------------------------------------------------------------------
# Uninstall — remove all installed files
# ---------------------------------------------------------------------------
uninstall() {
    log_step "Uninstalling WhatsApp Desktop App"

    local use_sudo=""
    if [[ -d "${INSTALL_DIR}" && ! -w "${INSTALL_DIR}" ]]; then
        use_sudo="sudo"
    fi

    if [[ -d "${INSTALL_DIR}" ]]; then
        log_info "Removing ${INSTALL_DIR}..."
        ${use_sudo} rm -rf "${INSTALL_DIR}"
        log_success "Application files removed."
    else
        log_warn "${INSTALL_DIR} not found — nothing to remove."
    fi

    [[ -f "${DESKTOP_FILE}" ]] \
        && rm -f "${DESKTOP_FILE}" \
        && log_success "Desktop entry removed."

    [[ -f "${AUTOSTART_DIR}/whatsapp.desktop" ]] \
        && rm -f "${AUTOSTART_DIR}/whatsapp.desktop" \
        && log_success "Autostart entry removed."

    # Remove every installed icon size
    local removed_icons=0
    for size in "${ICON_SIZES[@]}"; do
        local icon_path="${ICON_BASE_DIR}/${size}x${size}/apps/whatsapp.png"
        if [[ -f "$icon_path" ]]; then
            rm -f "$icon_path"
            removed_icons=$(( removed_icons + 1 ))
        fi
    done
    [[ $removed_icons -gt 0 ]] && log_success "Icons removed (${removed_icons} sizes)."

    # Refresh system databases
    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database "${DESKTOP_DIR}" 2>/dev/null || true
    fi
    if command -v gtk-update-icon-cache >/dev/null 2>&1; then
        gtk-update-icon-cache -f -t "${HOME}/.local/share/icons/hicolor" 2>/dev/null || true
    fi

    echo ""
    log_success "WhatsApp has been completely removed from your system."
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
main() {
    local icon_arg="${DEFAULT_ICON_SOURCE}"
    local target_dir="${INSTALL_DIR}"
    local do_uninstall=0
    local do_update=0
    local do_autostart=0
    local force_wayland=0

    # ---- argument parsing -----------------------------------------------
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -i|--icon)
                [[ -z "${2:-}" ]] && { log_error "--icon requires a path argument."; exit 1; }
                icon_arg="$2"
                shift 2
                ;;
            -d|--dir)
                [[ -z "${2:-}" ]] && { log_error "--dir requires a path argument."; exit 1; }
                target_dir="$2"
                shift 2
                ;;
            -u|--uninstall)
                do_uninstall=1
                shift
                ;;
            --update)
                do_update=1
                shift
                ;;
            --autostart)
                do_autostart=1
                shift
                ;;
            --wayland)
                force_wayland=1
                shift
                ;;
            -v|--version)
                echo "WhatsApp Linux Installer v${VERSION}"
                exit 0
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    print_header

    # ---- uninstall shortcut ----------------------------------------------
    if [[ ${do_uninstall} -eq 1 ]]; then
        uninstall
        exit 0
    fi

    # ---- abort early if already installed and no --update ----------------
    if [[ -d "${target_dir}" && ${do_update} -eq 0 ]]; then
        log_warn "WhatsApp is already installed at ${target_dir}."
        log_warn "Run with --update to re-install, or --uninstall to remove."
        exit 0
    fi

    # ---- detect display server ------------------------------------------
    local display_server
    if [[ $force_wayland -eq 1 ]]; then
        display_server="wayland"
    else
        display_server=$(detect_display_server)
    fi
    log_info "Display server: ${display_server}"

    # ---- main pipeline ---------------------------------------------------

    # 1. Internet check
    check_connectivity

    # 2. Dependencies (Node.js, npm, Nativefier)
    check_dependencies

    # 3. Temp workspace
    TEMP_DIR=$(mktemp -d /tmp/whatsapp-build.XXXXXX)
    local converted_icon="${TEMP_DIR}/icon.png"

    # 4. Icon -> 512x512 RGBA PNG
    log_step "Preparing Icon"
    process_icon "${icon_arg}" "${converted_icon}"

    # 5. Build with Nativefier
    build_whatsapp "${converted_icon}" "${TEMP_DIR}"
    local built_folder="${BUILT_FOLDER}"

    # 6. Deploy to target directory
    install_whatsapp "${built_folder}" "${target_dir}" "${converted_icon}"

    # 7. Desktop integration
    setup_desktop_shortcut "${target_dir}" "${converted_icon}" "${display_server}"

    # 8. Optional autostart
    if [[ ${do_autostart} -eq 1 ]]; then
        setup_autostart "${target_dir}" "${display_server}"
    fi

    # 9. Done!
    print_summary "${target_dir}" "${display_server}"
}

main "$@"
