#!/usr/bin/env bash
# ==============================================================================
# WhatsApp Desktop App Automated Installer for Linux
# Built with Nativefier
# Reference: /home/kanishk/Desktop/Blog-site/content/WhatsApp Desktop/WhatsApp Desktop App.md
# ==============================================================================

set -euo pipefail

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Default Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/icon.png" ]]; then
    DEFAULT_ICON_SOURCE="${SCRIPT_DIR}/icon.png"
else
    DEFAULT_ICON_SOURCE="/home/kanishk/Pictures/system/WhatsApp.png"
fi
FALLBACK_ICON_SOURCE="/home/kanishk/Desktop/Blog-site/images/whatsapp-icon.png"
INSTALL_DIR="/opt/WhatsApp"
DESKTOP_DIR="${HOME}/.local/share/applications"
DESKTOP_FILE="${DESKTOP_DIR}/whatsapp.desktop"
ICON_DIR="${HOME}/.local/share/icons/hicolor/512x512/apps"
APP_NAME="WhatsApp"
APP_URL="https://web.whatsapp.com/"
TEMP_DIR=""

log_info() {
    echo -e "${BLUE}${BOLD}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}${BOLD}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}${BOLD}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}${BOLD}[ERROR]${NC} $1" >&2
}

print_header() {
    echo -e "${CYAN}${BOLD}"
    echo "=========================================================="
    echo "       WhatsApp Desktop App Linux Installer"
    echo "=========================================================="
    echo -e "${NC}"
}

cleanup() {
    if [[ -n "${TEMP_DIR:-}" && -d "${TEMP_DIR}" ]]; then
        log_info "Cleaning up temporary build files in ${TEMP_DIR}..."
        rm -rf "${TEMP_DIR}"
    fi
}
trap cleanup EXIT

show_help() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Automates building and installing WhatsApp Web as a native desktop application on Linux.

Options:
  -i, --icon <path>     Path to the source WhatsApp icon image (PNG or WebP)
                        (default: ${DEFAULT_ICON_SOURCE})
  -d, --dir <path>      Installation target directory
                        (default: ${INSTALL_DIR})
  -u, --uninstall       Uninstall WhatsApp desktop app and desktop shortcut
  -h, --help            Show this help message and exit

Examples:
  ./$(basename "$0")
  ./$(basename "$0") --icon /path/to/custom/whatsapp.png
  ./$(basename "$0") --uninstall
EOF
}

detect_package_manager() {
    if command -v dnf >/dev/null 2>&1; then
        echo "dnf"
    elif command -v apt-get >/dev/null 2>&1; then
        echo "apt"
    elif command -v pacman >/dev/null 2>&1; then
        echo "pacman"
    elif command -v zypper >/dev/null 2>&1; then
        echo "zypper"
    else
        echo "unknown"
    fi
}

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
            sudo apt-get update
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
            log_error "Unsupported package manager. Please install Node.js and npm manually."
            exit 1
            ;;
    esac
}

check_dependencies() {
    log_info "Checking prerequisites..."

    # Check Node.js and npm
    if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
        log_warn "Node.js or npm is not installed. Attempting installation..."
        install_system_packages
    fi
    log_success "Node.js ($(node --version)) and npm ($(npm --version)) are ready."

    # Check Nativefier
    if ! command -v nativefier >/dev/null 2>&1; then
        log_info "Nativefier not found. Installing globally via npm..."
        if [ "$EUID" -ne 0 ]; then
            sudo npm install -g nativefier
        else
            npm install -g nativefier
        fi
    fi
    log_success "Nativefier ($(nativefier --version 2>/dev/null || echo 'installed')) is ready."
}

process_icon() {
    local raw_icon="$1"
    local output_icon="$2"

    if [[ ! -f "$raw_icon" ]]; then
        if [[ -f "$FALLBACK_ICON_SOURCE" ]]; then
            log_warn "Specified icon not found at ${raw_icon}. Using fallback at ${FALLBACK_ICON_SOURCE}."
            raw_icon="$FALLBACK_ICON_SOURCE"
        else
            log_error "Icon file not found: ${raw_icon}"
            exit 1
        fi
    fi

    log_info "Processing icon: ${raw_icon}"

    # Check if conversion is needed (e.g. WebP or not a 512x512 PNG)
    local is_png=0
    if file "$raw_icon" | grep -q "PNG image data"; then
        is_png=1
    fi

    # Convert to standard 512x512 RGBA PNG for maximum desktop compatibility
    if command -v python3 >/dev/null 2>&1 && python3 -c "import PIL" >/dev/null 2>&1; then
        python3 - <<EOF
from PIL import Image
try:
    img = Image.open("${raw_icon}")
    if img.mode != 'RGBA':
        img = img.convert('RGBA')
    img_512 = img.resize((512, 512), Image.Resampling.LANCZOS)
    img_512.save("${output_icon}", 'PNG')
    print("Icon converted and saved successfully with PIL.")
except Exception as e:
    print(f"PIL conversion failed: {e}")
    exit(1)
EOF
    elif command -v magick >/dev/null 2>&1; then
        magick "${raw_icon}" -resize 512x512 "${output_icon}"
    elif command -v convert >/dev/null 2>&1; then
        convert "${raw_icon}" -resize 512x512 "${output_icon}"
    elif command -v ffmpeg >/dev/null 2>&1; then
        ffmpeg -y -i "${raw_icon}" -vf "scale=512:512" "${output_icon}" >/dev/null 2>&1
    elif [[ $is_png -eq 1 ]]; then
        cp "${raw_icon}" "${output_icon}"
    else
        log_error "Cannot convert ${raw_icon} to PNG. Please install python3-pillow or ImageMagick."
        exit 1
    fi

    log_success "Prepared application icon: ${output_icon}"
}

build_whatsapp() {
    local icon_path="$1"
    local build_out_dir="$2"

    log_info "Building WhatsApp desktop app with Nativefier..."
    log_info "URL: ${APP_URL}"
    log_info "App Name: ${APP_NAME}"

    nativefier "${APP_URL}" \
        --name "${APP_NAME}" \
        --single-instance \
        --icon "${icon_path}" \
        "${build_out_dir}"

    local built_folder
    built_folder=$(find "${build_out_dir}" -maxdepth 1 -type d -name "WhatsApp-linux-*" | head -n 1)

    if [[ -z "${built_folder}" || ! -d "${built_folder}" ]]; then
        log_error "Nativefier build output directory was not found in ${build_out_dir}."
        exit 1
    fi

    if [[ ! -f "${built_folder}/WhatsApp" ]]; then
        log_error "WhatsApp binary not found in ${built_folder}."
        exit 1
    fi

    echo "${built_folder}"
}

install_whatsapp() {
    local source_folder="$1"
    local target_dir="$2"
    local icon_path="$3"

    log_info "Installing WhatsApp to ${target_dir}..."

    # Requires sudo if target is /opt or outside home
    local use_sudo=""
    if [[ ! -w "$(dirname "${target_dir}")" ]] || [[ -d "${target_dir}" && ! -w "${target_dir}" ]]; then
        use_sudo="sudo"
    fi

    if [[ -d "${target_dir}" ]]; then
        log_warn "Existing directory found at ${target_dir}. Replacing it..."
        ${use_sudo} rm -rf "${target_dir}"
    fi

    ${use_sudo} mkdir -p "$(dirname "${target_dir}")"
    ${use_sudo} cp -r "${source_folder}" "${target_dir}"
    ${use_sudo} cp "${icon_path}" "${target_dir}/icon.png"
    ${use_sudo} chmod -R u+rwX,go+rX "${target_dir}"
    ${use_sudo} chmod +x "${target_dir}/WhatsApp"

    log_success "WhatsApp successfully installed to ${target_dir}."
}

setup_desktop_shortcut() {
    local target_dir="$1"
    local icon_path="$2"

    log_info "Setting up desktop integration..."

    mkdir -p "${DESKTOP_DIR}"
    mkdir -p "${ICON_DIR}"

    cp "${icon_path}" "${ICON_DIR}/whatsapp.png" 2>/dev/null || true

    cat << EOF > "${DESKTOP_FILE}"
[Desktop Entry]
Name=WhatsApp
GenericName=WhatsApp Desktop
Comment=WhatsApp Web Desktop Client
Exec=${target_dir}/WhatsApp %U
Icon=${target_dir}/icon.png
Terminal=false
Type=Application
Categories=Network;Chat;InstantMessaging;
StartupWMClass=WhatsApp
StartupNotify=true
MimeType=x-scheme-handler/whatsapp;
EOF

    chmod +x "${DESKTOP_FILE}"
    log_success "Created desktop entry: ${DESKTOP_FILE}"

    # Update system desktop database (GNOME, XFCE, and universal)
    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database "${DESKTOP_DIR}" 2>/dev/null || true
    fi

    # Update KDE Plasma system configuration cache (KDE 6 / KDE 5)
    if command -v kbuildsycoca6 >/dev/null 2>&1; then
        kbuildsycoca6 2>/dev/null || true
    elif command -v kbuildsycoca5 >/dev/null 2>&1; then
        kbuildsycoca5 2>/dev/null || true
    fi

    # Update icon cache if tool exists
    if command -v gtk-update-icon-cache >/dev/null 2>&1; then
        gtk-update-icon-cache -f -t "${HOME}/.local/share/icons/hicolor" 2>/dev/null || true
    fi

    log_success "Desktop database and icon cache refreshed."
}

uninstall() {
    log_info "Uninstalling WhatsApp Desktop App..."

    local use_sudo=""
    if [[ -d "${INSTALL_DIR}" ]] && [[ ! -w "${INSTALL_DIR}" ]]; then
        use_sudo="sudo"
    fi

    if [[ -d "${INSTALL_DIR}" ]]; then
        log_info "Removing ${INSTALL_DIR}..."
        ${use_sudo} rm -rf "${INSTALL_DIR}"
    fi

    if [[ -f "${DESKTOP_FILE}" ]]; then
        log_info "Removing desktop entry: ${DESKTOP_FILE}..."
        rm -f "${DESKTOP_FILE}"
    fi

    if [[ -f "${ICON_DIR}/whatsapp.png" ]]; then
        log_info "Removing icon from ${ICON_DIR}..."
        rm -f "${ICON_DIR}/whatsapp.png"
    fi

    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database "${DESKTOP_DIR}" 2>/dev/null || true
    fi

    log_success "WhatsApp has been completely removed from your system."
}

main() {
    local icon_arg="${DEFAULT_ICON_SOURCE}"
    local target_dir="${INSTALL_DIR}"
    local do_uninstall=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -i|--icon)
                icon_arg="$2"
                shift 2
                ;;
            -d|--dir)
                target_dir="$2"
                shift 2
                ;;
            -u|--uninstall)
                do_uninstall=1
                shift
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

    if [[ ${do_uninstall} -eq 1 ]]; then
        uninstall
        exit 0
    fi

    # 1. Verify and install dependencies (Node, npm, Nativefier)
    check_dependencies

    # 2. Setup temporary workspace
    TEMP_DIR=$(mktemp -d /tmp/whatsapp-build.XXXXXX)
    local converted_icon="${TEMP_DIR}/icon.png"

    # 3. Process icon (convert WebP/PNG to proper 512x512 PNG)
    process_icon "${icon_arg}" "${converted_icon}"

    # 4. Build WhatsApp app using Nativefier
    local built_folder
    built_folder=$(build_whatsapp "${converted_icon}" "${TEMP_DIR}")

    # 5. Install app to target directory (/opt/WhatsApp)
    install_whatsapp "${built_folder}" "${target_dir}" "${converted_icon}"

    # 6. Create .desktop file and register with desktop environment
    setup_desktop_shortcut "${target_dir}" "${converted_icon}"

    echo ""
    log_success "🎉 WhatsApp Desktop App installation complete!"
    echo -e "${GREEN}You can now launch WhatsApp from your Application Menu (search 'WhatsApp')${NC}"
    echo -e "${CYAN}Or start it from terminal: ${BOLD}${target_dir}/WhatsApp &${NC}"
    echo ""
}

main "$@"
