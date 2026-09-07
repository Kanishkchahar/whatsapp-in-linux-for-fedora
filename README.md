# WhatsApp Desktop App Installer for Linux

Automated installer that wraps [Nativefier](https://github.com/nativefier/nativefier) to create a native-feeling WhatsApp desktop app from WhatsApp Web. Works on **Fedora, Ubuntu, Arch, openSUSE**, and any distro with `dnf`, `apt`, `pacman`, or `zypper`.

## What it does

1. **Connectivity Check**: Verifies internet access before doing anything.
2. **Checks & Installs Prerequisites**: Automatically verifies that `Node.js` (v16+), `npm`, and `Nativefier` are installed. If missing, installs them using your distro's package manager. Node.js version is validated — too-old versions are caught early with a clear error.
3. **Converts & Optimizes the Icon**: Uses the bundled `icon.png` from the script directory. If not found, automatically downloads one from Wikimedia. You can also provide a custom icon with `--icon /path/to/icon.png`. Converts it to a standard high-quality 512×512 RGBA PNG.
4. **Builds the App**: Runs Nativefier against `https://web.whatsapp.com/` with `--single-instance`, system tray support, WhatsApp-green background, and internal-URL filtering so links stay inside the app.
5. **Installs System-Wide**: Deploys the built application to `/opt/WhatsApp` with proper permissions.
6. **Desktop Integration**:
   - Installs icons in **7 sizes** (16, 32, 48, 64, 128, 256, 512 px) into the hicolor theme for crisp display everywhere.
   - Creates `~/.local/share/applications/whatsapp.desktop` with `StartupWMClass=WhatsApp`, `Keywords`, `Version=1.5`, and uses the icon theme name (`Icon=whatsapp`) instead of a hard-coded path.
   - Registers the `whatsapp://` URL scheme handler via `xdg-mime`.
   - Updates the desktop menu database and icon cache (GNOME, KDE, XFCE, etc.).
7. **Wayland / X11 auto-detection**: Reads `XDG_SESSION_TYPE` and sets the correct Chromium/Electron flags automatically. Force Wayland with `--wayland`.

## Requirements

- Linux (Fedora, Ubuntu, Arch, openSUSE, or any distro with a supported package manager)
- `sudo` access (for installing to `/opt`)
- Internet connection (to download Nativefier and WhatsApp Web)
- Node.js v16 or newer (installed automatically if missing)

## Usage

Run the script directly from this directory:

```bash
./install-whatsapp.sh
```

### Options

```bash
# Specify a custom icon
./install-whatsapp.sh --icon /path/to/icon.png

# Install to a custom location (no sudo needed)
./install-whatsapp.sh --dir ~/.local/share/WhatsApp

# Update an existing installation
./install-whatsapp.sh --update

# Add WhatsApp to login autostart
./install-whatsapp.sh --autostart

# Force Wayland rendering mode
./install-whatsapp.sh --wayland

# Cleanly uninstall WhatsApp desktop app, icons, and shortcuts
./install-whatsapp.sh --uninstall

# Show installer version
./install-whatsapp.sh --version

# Show help
./install-whatsapp.sh --help
```

## Icon Resolution Order

1. **Bundled** `icon.png` in the same folder as the script
2. **Custom** icon passed via `--icon /path/to/file.png`
3. **Auto-downloaded** from Wikimedia if no local icon is found
4. **Error** with a clear message if none of the above work

## What's New in v2.0.0

- **Spinner animation** for long-running steps (Nativefier install, build, file copy)
- **`--update`** flag — re-install without needing to uninstall first
- **`--autostart`** flag — launches WhatsApp at login
- **`--wayland`** flag — force Wayland mode (default is auto-detect)
- **`--version`** flag — prints the installer version
- **Node.js v16+ enforcement** — clear error if your Node is too old
- **Internet connectivity check** — warns early if offline
- **Multi-size icon install** — 7 sizes (16–512 px) for perfect rendering in all DEs
- **`xdg-mime` URL scheme registration** — `whatsapp://` links open the app
- **Build log on failure** — Nativefier output is shown when the build fails
- **Already-installed guard** — warns and exits cleanly if installed; use `--update`
- **Improved uninstall** — removes all icon sizes and the autostart entry
