#!/usr/bin/env bash
# RØDECaster Pro 2 Virtual Audio Driver - Installer (Arch + Fedora)
# https://github.com/v4lr4vn/rodecaster-vad
set -e

REPO_URL="https://github.com/v4lr4vn/rodecaster-vad.git"
INSTALL_DIR="$HOME/rodecaster-vad"
SERVICE_DIR="$HOME/.config/systemd/user"
RULES_FILE="/etc/udev/rules.d/90-rodecaster-vad.rules"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

check_root() {
  [[ $EUID -eq 0 ]] && error "Don't run this as root. Run as your normal user — sudo is used where needed."
  return 0
}

install_packages() {
  if command -v pacman &>/dev/null; then
    info "Arch-based distro detected"
    sudo pacman -S --needed --noconfirm \
      git python python-hidapi pipewire pipewire-pulse pipewire-audio \
      wireplumber python-gobject gtk4 libadwaita usbutils
  elif command -v dnf &>/dev/null; then
    info "Fedora/RHEL-based distro detected"
    # pipewire-utils provides pw-loopback; pulseaudio-utils provides pactl
    sudo dnf install -y \
      git python3 python3-hidapi hidapi \
      pipewire pipewire-pulseaudio pipewire-utils wireplumber \
      pulseaudio-utils python3-gobject gtk4 libadwaita usbutils
  else
    error "Unsupported package manager. Install manually: git, python3, hidapi python bindings, pipewire (+pulse, +utils/pw-loopback), wireplumber, pactl, python3-gobject, gtk4, libadwaita"
  fi
  command -v pw-loopback &>/dev/null || error "pw-loopback not found after install"
  command -v pactl &>/dev/null || error "pactl not found after install"
  success "Dependencies ready."
}

install_udev_rules() {
  info "Installing udev rules..."
  sudo tee "$RULES_FILE" > /dev/null << 'RULES'
# RØDECaster Pro 2 - VID:PID 19f7:0072
SUBSYSTEM=="hidraw", ATTRS{idVendor}=="19f7", ATTRS{idProduct}=="0072", MODE="0660", GROUP="wheel", TAG+="uaccess"
SUBSYSTEM=="usb", ATTRS{idVendor}=="19f7", ATTRS{idProduct}=="0072", MODE="0660", GROUP="wheel", TAG+="uaccess"
RULES
  sudo udevadm control --reload-rules
  sudo udevadm trigger
  success "udev rules installed. Replug your RØDECaster if it's already connected."
}

install_service() {
  info "Installing systemd user service..."
  mkdir -p "$SERVICE_DIR"
  tee "$SERVICE_DIR/rodecaster-vad.service" > /dev/null << EOF2
[Unit]
Description=RØDECaster Pro 2 Virtual Audio Driver
After=pipewire.service wireplumber.service
Wants=pipewire.service wireplumber.service

[Service]
Type=simple
ExecStart=/usr/bin/python3 ${INSTALL_DIR}/rodecaster_daemon.py
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF2
  systemctl --user daemon-reload
  systemctl --user enable rodecaster-vad.service
  systemctl --user restart rodecaster-vad.service
  success "Service installed and started."
}

install_desktop_entry() {
  info "Installing desktop launcher..."
  local app_dir="$HOME/.local/share/applications"
  mkdir -p "$app_dir"
  tee "$app_dir/rodecaster-control.desktop" > /dev/null << EOF2
[Desktop Entry]
Name=RØDECaster Control Panel
Comment=Virtual Audio Driver for RØDECaster Pro 2
Exec=/usr/bin/python3 ${INSTALL_DIR}/rodecaster_gtk_gui.py
Icon=audio-card
Terminal=false
Type=Application
Categories=AudioVideo;Audio;
EOF2
  chmod +x "$INSTALL_DIR/rodecaster_gtk_gui.py"
  update-desktop-database "$app_dir" 2>/dev/null || true
  success "Desktop launcher installed."
}

cmd_install() {
  check_root
  install_packages
  if [[ -d "$INSTALL_DIR" ]]; then
    warn "Install directory already exists at $INSTALL_DIR."
    read -rp "Reinstall? This will overwrite local files. [y/N] " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { info "Aborted."; exit 0; }
    rm -rf "$INSTALL_DIR"
  fi
  info "Cloning repository..."
  git clone "$REPO_URL" "$INSTALL_DIR"
  install_udev_rules
  install_service
  install_desktop_entry
  success "Installation complete. Replug the RØDECaster if it wasn't detected."
  systemctl --user status rodecaster-vad.service --no-pager || true
}

cmd_update() {
  check_root
  [[ -d "$INSTALL_DIR" ]] || error "Not installed. Run '$0 install' first."
  systemctl --user stop rodecaster-vad.service || true
  git -C "$INSTALL_DIR" pull origin main
  install_udev_rules
  install_service
  install_desktop_entry
  success "Update complete!"
}

cmd_uninstall() {
  check_root
  read -rp "Remove service, udev rules, launcher and $INSTALL_DIR? [y/N] " confirm
  [[ "$confirm" =~ ^[Yy]$ ]] || { info "Aborted."; exit 0; }
  systemctl --user stop rodecaster-vad.service 2>/dev/null || true
  systemctl --user disable rodecaster-vad.service 2>/dev/null || true
  rm -f "$SERVICE_DIR/rodecaster-vad.service"
  systemctl --user daemon-reload
  sudo rm -f "$RULES_FILE"
  sudo udevadm control --reload-rules
  rm -f "$HOME/.local/share/applications/rodecaster-control.desktop"
  rm -rf "$INSTALL_DIR"
  success "Uninstalled."
}

cmd_status() {
  systemctl --user status rodecaster-vad.service --no-pager || true
  echo; info "Virtual sinks:";  pactl list short sinks | grep -i rode || echo "  None found."
  echo; info "USB device:";     lsusb | grep -i -e rode -e 19f7 || echo "  Not detected."
  echo; info "hidraw:";         ls -la /dev/hidraw* 2>/dev/null || echo "  None."
}

case "${1:-}" in
  install)   cmd_install ;;
  update)    cmd_update ;;
  uninstall) cmd_uninstall ;;
  status)    cmd_status ;;
  *) echo "Usage: $0 {install|update|uninstall|status}" ;;
esac
