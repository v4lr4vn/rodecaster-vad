#!/usr/bin/env python3
"""
RØDECaster Virtual Audio Driver Daemon (distro-agnostic)

Multitrack mapping:
  Chat  -> pro-output-0 (Fader 1)
  Game  -> pro-output-1 AUX2,AUX3 (Fader 2)
  Music -> pro-output-1 AUX4,AUX5 (Fader 3)

Changes from the original:
  - No hardcoded device serial: the card is discovered via pactl
  - No shell=True; loopbacks are real child processes and are terminated on exit
  - python-hidapi is optional (it was only used for a log line)
  - Exits non-zero if a loopback dies, so systemd Restart=on-failure recovers
"""

import logging
import signal
import subprocess
import sys
import time

try:
    import hid
except ImportError:
    hid = None

VENDOR_ID = 0x19F7
PRODUCT_ID = 0x0072

VIRTUAL_SINKS = [
    {"name": "chat",  "desc": "Chat (Discord)", "output": 0, "channels": "FL FR",
     "dont_remix": False, "fader": 1},
    {"name": "game",  "desc": "Game Output",    "output": 1, "channels": "AUX2 AUX3",
     "dont_remix": True,  "fader": 2},
    {"name": "music", "desc": "Music Output",   "output": 1, "channels": "AUX4 AUX5",
     "dont_remix": True,  "fader": 3},
]


class RodecasterVAD:
    def __init__(self):
        self.running = True
        self.hid_dev = None
        self.card = None          # e.g. alsa_card.usb-R__DE_RODECaster_Pro_II_XXXX-00
        self.procs = []
        logging.basicConfig(level=logging.INFO,
                            format="%(asctime)s - %(levelname)s - %(message)s")
        self.log = logging.getLogger("rodecaster-vad")
        signal.signal(signal.SIGINT, self._stop)
        signal.signal(signal.SIGTERM, self._stop)

    def _stop(self, *_):
        self.log.info("Shutdown signal received")
        self.running = False

    # ---------- discovery ----------
    @staticmethod
    def find_card():
        try:
            out = subprocess.run(["pactl", "list", "short", "cards"],
                                 capture_output=True, text=True, check=True).stdout
        except (OSError, subprocess.CalledProcessError):
            return None
        for line in out.splitlines():
            parts = line.split("\t")
            if len(parts) >= 2 and "rodecaster" in parts[1].lower():
                return parts[1]
        return None

    def open_hid(self):
        """Optional; only used to log the device strings."""
        if hid is None:
            self.log.info("python hid module not installed - skipping HID (not required)")
            return
        try:
            if hasattr(hid, "device"):      # cython-hidapi ('hidapi' on PyPI)
                dev = hid.device()
                dev.open(VENDOR_ID, PRODUCT_ID)
                self.log.info("HID: %s %s", dev.get_manufacturer_string(),
                              dev.get_product_string())
            else:                           # 'hid' on PyPI
                dev = hid.Device(VENDOR_ID, PRODUCT_ID)
                self.log.info("HID: %s %s", dev.manufacturer, dev.product)
            self.hid_dev = dev
        except Exception as e:
            self.log.warning("Could not open HID device (continuing): %s", e)

    # ---------- audio ----------
    def set_pro_audio_profile(self):
        self.log.info("Setting %s to pro-audio profile...", self.card)
        subprocess.run(["pactl", "set-card-profile", self.card, "pro-audio"],
                       capture_output=True, text=True)
        time.sleep(1)

    def create_sink(self, cfg):
        node = f"rodecaster_{cfg['name']}"
        desc = f"RØDECaster {cfg['desc']}"
        base = self.card.replace("alsa_card.", "", 1)
        target = f"alsa_output.{base}.pro-output-{cfg['output']}"

        capture = (f'media.class=Audio/Sink node.name={node} '
                   f'node.description="{desc}" audio.position=[ FL FR ]')
        playback = f'node.target={target} audio.position=[ {cfg["channels"]} ]'
        if cfg["dont_remix"]:
            playback += " stream.dont-remix=true"

        try:
            proc = subprocess.Popen(
                ["pw-loopback",
                 f"--capture-props={capture}",
                 f"--playback-props={playback}"],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except OSError as e:
            self.log.error("Cannot run pw-loopback (install pipewire-utils): %s", e)
            return False
        self.procs.append(proc)
        self.log.info("✓ %s → Fader %d (%s)", desc, cfg["fader"], target)
        time.sleep(0.3)
        return True

    def create_all_sinks(self):
        self.set_pro_audio_profile()
        ok = sum(1 for s in VIRTUAL_SINKS if self.create_sink(s))
        self.log.info("Created %d/%d virtual sinks", ok, len(VIRTUAL_SINKS))
        return ok == len(VIRTUAL_SINKS)

    def cleanup(self):
        self.log.info("Cleaning up virtual devices...")
        for p in self.procs:
            if p.poll() is None:
                p.terminate()
        for p in self.procs:
            try:
                p.wait(timeout=3)
            except subprocess.TimeoutExpired:
                p.kill()
        self.procs.clear()
        if self.hid_dev:
            try:
                self.hid_dev.close()
            except Exception:
                pass
            self.hid_dev = None

    # ---------- main ----------
    def run(self):
        self.log.info("RØDECaster Virtual Audio Driver starting; waiting for device...")
        while self.running:
            self.card = self.find_card()
            if self.card:
                break
            time.sleep(2)
        if not self.running:
            return 0

        self.log.info("Found card: %s", self.card)
        self.open_hid()

        if not self.create_all_sinks():
            self.cleanup()
            return 1

        self.log.info("READY: route apps to the 'RØDECaster ...' outputs "
                      "(GUI or pavucontrol); faders 1/2/3 = Chat/Game/Music")
        code = 0
        try:
            while self.running:
                if self.find_card() is None:
                    self.log.warning("Device disconnected")
                    code = 1
                    break
                if any(p.poll() is not None for p in self.procs):
                    self.log.error("A pw-loopback process exited unexpectedly")
                    code = 1
                    break
                time.sleep(5)
        finally:
            self.cleanup()
        return code


if __name__ == "__main__":
    sys.exit(RodecasterVAD().run())
