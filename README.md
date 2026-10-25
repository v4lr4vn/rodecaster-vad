# RØDECaster Pro 2 Virtual Audio Driver for Linux

![Platform](https://img.shields.io/badge/Platform-Linux-blue?logo=linux)
![License](https://img.shields.io/badge/License-GPL--3.0-green)
![Python](https://img.shields.io/badge/Python-3.10+-yellow?logo=python)
![Distros](https://img.shields.io/badge/Tested-Arch%20%7C%20Fedora-informational)

Windows-like virtual audio routing for the RØDECaster Pro 2 on Linux. Control your apps with physical mixer faders!

## ✨ Features

- 🎛️ **3 Virtual Outputs** mapped to physical faders
- 🎨 **GTK4 Control Panel** - no command line needed!
- 🔊 **Multiple Apps Per Fader** - software mixing
- 🔄 **Auto-Detection** - plug and play, no hardcoded serial numbers
- ⚡ **Systemd Integration** - runs in the background
- 🎯 **No pavucontrol needed** - route apps in the GUI
- 🐧 **Arch and Fedora supported** - one-command installer for both

## 📸 Screenshots

![Control Panel](https://r2.fivemanage.com/twlJi4g2rT1Wmmh5KJ1u9/Preview.png)
*Full-featured GTK4 control panel*

## 🎯 What It Does

Creates virtual audio outputs that route to specific faders on your RØDECaster Pro 2:

| Virtual Output | Physical Fader | Typical Use            |
| -------------- | -------------- | ---------------------- |
| Chat (Discord) | Fader 1        | Voice chat, Discord    |
| Game Output    | Fader 2        | Games, gameplay audio  |
| Music Output   | Fader 3        | Music, browsers, media |

**Control volume with your physical mixer faders!**

## 🚀 Installation

The installer detects your package manager (`pacman` or `dnf`), installs dependencies, sets up the udev rules, the systemd user service and the GUI launcher, and clones the repo to `~/rodecaster-vad`. Run it as your normal user, not root.

### Quick install (Arch and Fedora)

```bash
curl -fsSL https://raw.githubusercontent.com/v4lr4vn/rodecaster-vad/main/install.sh -o install.sh
bash install.sh install
```

Then replug the RØDECaster's USB cable and check everything:

```bash
bash install.sh status
```

Other commands: `bash install.sh update` and `bash install.sh uninstall`.

### Fedora

Tested on Fedora Workstation (PipeWire + WirePlumber, the default audio stack).

The installer runs this for you. To install the dependencies by hand:

```bash
sudo dnf install -y git python3 python3-hidapi hidapi \
  pipewire pipewire-pulseaudio pipewire-utils wireplumber \
  pulseaudio-utils python3-gobject gtk4 libadwaita usbutils
```

Fedora notes:

- `pipewire-utils` provides `pw-loopback` and `pulseaudio-utils` provides `pactl`. The daemon cannot create sinks without both.
- Use `python3-hidapi` from `dnf`. The `hid` package on PyPI is a different library and will not work. The HID module is optional; the daemon runs without it.
- If the service fails to start, check for SELinux denials: `ausearch -m avc -ts recent`.

### Arch Linux / Manjaro / EndeavourOS

```bash
sudo pacman -S --needed git python python-hidapi pipewire pipewire-pulse pipewire-audio \
  wireplumber python-gobject gtk4 libadwaita usbutils
```

Then run the quick install above. A `PKGBUILD` is also included in the repo.

### Other distributions

Dependencies needed:

- Python 3.10+
- Python hidapi bindings (optional)
- PipeWire with `pipewire-pulse`, plus `pw-loopback` and `pactl`
- WirePlumber
- GTK4, libadwaita and PyGObject
- systemd

Install those with your package manager, then run `bash install.sh install`. The installer will stop with a message if `pw-loopback` or `pactl` is missing.

## 📖 Usage

### GUI Control Panel

1. **Launch the app** from your application menu: "RØDECaster Control Panel"
2. **Play audio** in any application (Firefox, Spotify, Discord, games)
3. **Click "Refresh Apps"** to see available apps
4. **Select app** from the dropdown under the fader you want
5. **Control volume** with your physical RØDECaster fader!

### Command Line

```bash
# Check service status
systemctl --user status rodecaster-vad.service

# View logs
journalctl --user -u rodecaster-vad.service -f

# Restart the service
systemctl --user restart rodecaster-vad.service

# Full status check (service, sinks, USB, hidraw)
bash ~/rodecaster-vad/install.sh status
```

## 🔧 How It Works

1. **Device discovery** - finds the RØDECaster card through PipeWire/PulseAudio (`pactl`), so no serial number is hardcoded
2. **Pro Audio mode** - sets the card to the `pro-audio` profile for multitrack USB
3. **Virtual sinks** - creates PipeWire virtual audio devices with `pw-loopback`
4. **Channel mapping** - routes to specific hardware channels:
   - Chat → pro-output-0 (2-channel)
   - Game → pro-output-1 AUX2, AUX3
   - Music → pro-output-1 AUX4, AUX5
5. **Software mixing** - PipeWire mixes multiple apps per fader
6. **Self-healing** - if a loopback dies or the device is unplugged, the daemon exits and systemd restarts it

## 🛠️ Requirements

### Hardware

- RØDECaster Pro 2 (USB VID:PID `19f7:0072`; check yours with `lsusb | grep 19f7`)
- Multitrack mode enabled on the RØDECaster

### Software

- Linux kernel with USB Audio Class 2.0 support
- PipeWire audio system
- systemd
- Python 3.10+

## 📋 Project Structure

```
rodecaster-vad/
├── rodecaster_daemon.py      # Background service (main driver)
├── rodecaster_gtk_gui.py     # GTK4 control panel
├── rodecaster_gui.py         # Alternate GUI
├── install.sh                # Installer (Arch + Fedora): install / update / uninstall / status
├── PKGBUILD                  # Arch package build file
├── find_channels.sh          # Helper scripts for channel mapping
├── find_missing_faders.sh
├── test_*.sh                 # Audio routing test scripts
└── README.md                 # This file
```

The udev rules, systemd service and desktop launcher are generated by `install.sh`.

## 🐛 Troubleshooting

**Service won't start:**

```bash
systemctl --user status rodecaster-vad.service
journalctl --user -u rodecaster-vad.service -n 50
```

**`pw-loopback` or `pactl` not found (Fedora):**

```bash
sudo dnf install pipewire-utils pulseaudio-utils
```

**Device not detected:**

```bash
lsusb | grep -i -e rode -e 19f7   # Should show 19f7:0072
ls -l /dev/hidraw*                # Check permissions
```

If your device shows a different product ID, update it in `/etc/udev/rules.d/90-rodecaster-vad.rules` and in `rodecaster_daemon.py`.

**No virtual outputs:**

```bash
pactl list short sinks | grep rodecaster
# Should show 3 virtual outputs
```

**Multitrack not working:**

- Check RØDECaster settings: enable "Multitrack" mode via USB
- Verify the pro-audio profile: `pactl list cards | grep -A50 RODECaster`

## 🤝 Contributing

Contributions welcome! Feel free to:

- 🐛 Report bugs via Issues
- 💡 Suggest features
- 🔧 Submit Pull Requests
- 📖 Improve documentation (other distros especially)

### Development Setup

```bash
git clone https://github.com/v4lr4vn/rodecaster-vad.git
cd rodecaster-vad

# Test changes
python3 rodecaster_daemon.py      # Test daemon
python3 rodecaster_gtk_gui.py     # Test GUI
```

## 📜 License

GPL-3.0 - See [LICENSE](LICENSE) file

## 🙏 Credits

- **Created by**: ValRavn (formerly SelfishEagle)
- **Reverse-engineered with**: Claude (Anthropic AI)
- **Community**: Linux audio enthusiasts
- **Inspired by**: RØDE's Windows driver

## 🔗 Links

- **Issues**: <https://github.com/v4lr4vn/rodecaster-vad/issues>
- **Discussions**: <https://github.com/v4lr4vn/rodecaster-vad/discussions>
- **RØDE**: <https://rode.com/>

## ⭐ Star History

If this project helped you, consider giving it a star! ⭐

---

**Made with ❤️ for the Linux audio community**
