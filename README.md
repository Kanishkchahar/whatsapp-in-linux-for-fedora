# WhatsApp Desktop App Installer for Linux

Automated installer script based on the guide in [WhatsApp Desktop App.md](/home/kanishk/Desktop/Blog-site/content/WhatsApp%20Desktop/WhatsApp%20Desktop%20App.md).

## What it does

1. **Checks & Installs Prerequisites**: Automatically verifies that `Node.js`, `npm`, and `Nativefier` are installed. If missing, it installs them using your distribution's package manager (`dnf`, `apt`, `pacman`, or `zypper`).
2. **Converts & Optimizes the Icon**: Takes `/home/kanishk/Pictures/system/WhatsApp.png` (or custom icon), verifies its format, converts it to a standard high-quality 512×512 RGBA PNG for crisp display in Linux desktop environments.
3. **Builds the App**: Runs Nativefier against `https://web.whatsapp.com/` with `--single-instance` and embeds the icon.
4. **Installs System-Wide**: Deploys the built application to `/opt/WhatsApp` with proper execution permissions.
5. **Desktop Integration**:
   - Creates `~/.local/share/applications/whatsapp.desktop` with correct window grouping (`StartupWMClass=WhatsApp`) and URL handler support.
   - Installs high-res icon into `~/.local/share/icons/hicolor/512x512/apps/whatsapp.png`.
   - Updates desktop menu database and icon cache.

## Usage

Run the script directly from this directory:

```bash
./install-whatsapp.sh
```

### Options

```bash
# Specify a custom icon
./install-whatsapp.sh --icon /path/to/icon.png

# Specify a custom install location (e.g. without sudo)
./install-whatsapp.sh --dir ~/.local/share/WhatsApp

# Cleanly uninstall WhatsApp desktop app and shortcuts
./install-whatsapp.sh --uninstall

# Show help
./install-whatsapp.sh --help
```
