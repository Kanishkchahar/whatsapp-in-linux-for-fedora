# WhatsApp Desktop App Installer for Linux

Automated installer that wraps [Nativefier](https://github.com/nativefier/nativefier) to create a native-feeling WhatsApp desktop app from WhatsApp Web. Works on **Fedora, Ubuntu, Arch, openSUSE**, and any distro with `dnf`, `apt`, `pacman`, or `zypper`.

## What it does

1. **Checks & Installs Prerequisites**: Automatically verifies that `Node.js`, `npm`, and `Nativefier` are installed. If missing, it installs them using your distribution's package manager (`dnf`, `apt`, `pacman`, or `zypper`).
2. **Converts & Optimizes the Icon**: Uses the bundled `icon.png` from the script directory. If not found, automatically downloads one from the web. You can also provide a custom icon with `--icon /path/to/icon.png`. Converts it to a standard high-quality 512×512 RGBA PNG for crisp display in Linux desktop environments.
3. **Builds the App**: Runs Nativefier against `https://web.whatsapp.com/` with `--single-instance` and embeds the icon.
4. **Installs System-Wide**: Deploys the built application to `/opt/WhatsApp` with proper execution permissions.
5. **Desktop Integration**:
   - Creates `~/.local/share/applications/whatsapp.desktop` with correct window grouping (`StartupWMClass=WhatsApp`) and URL handler support.
   - Installs high-res icon into `~/.local/share/icons/hicolor/512x512/apps/whatsapp.png`.
   - Updates desktop menu database and icon cache (works with GNOME, KDE, XFCE, etc.).

## Requirements

- Linux (Fedora, Ubuntu, Arch, openSUSE, or any distro with a supported package manager)
- `sudo` access (for installing to `/opt`)
- Internet connection (to download Nativefier and WhatsApp Web)

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

# Cleanly uninstall WhatsApp desktop app and shortcuts
./install-whatsapp.sh --uninstall

# Show help
./install-whatsapp.sh --help
```

## Icon Resolution Order

1. **Bundled** `icon.png` in the same folder as the script
2. **Custom** icon passed via `--icon /path/to/file.png`
3. **Auto-downloaded** from Wikimedia if no local icon is found
4. **Error** with a clear message if none of the above work
