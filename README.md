# Intel IPU6 Camera Setup (ov01a10) on Ubuntu 25.10

Get the Intel IPU6 MIPI camera (ov01a10 sensor) working on Ubuntu 25.10 with libcamera's SoftISP, PipeWire, and Firefox.

## The Problem

The IPU6 camera exposes ~32 raw V4L2 nodes that output Bayer data. Browsers and most apps can't use these directly. The camera needs libcamera's Simple pipeline handler with Software ISP (CPU debayering) to produce usable RGB frames. PipeWire then makes these available to desktop apps.

## What the Patch Does

- **Sensor helper** (`camera_sensor_helper.cpp`): Adds ov01a10 analog gain parameters
- **Sensor properties** (`camera_sensor_properties.cpp`): Adds ov01a10 unit cell size, test patterns, and sensor delays (2-frame delay for exposure/gain/vblank/hblank — fixes flickering)
- **AGC tuning** (`agc.cpp`): Reduces step size to ~1.25% (from 10%), increases hysteresis to 0.9, adds 3x highlight weighting for the brightest histogram bin (fixes overexposure near windows)
- **Adaptive contrast** (`lut.cpp`): Adjusts contrast based on scene brightness (1.3 in dark, 1.0 in bright scenes), default contrast 1.2
- **Color correction** (`ov01a10.yaml`): Tuning file with black level, CCM for vibrant colors
- **Native resolution** (`stream.cpp`): Adds 1268x800 to the common sizes list (full sensor resolution)
- **Build config** (`meson.build`): Registers the ov01a10 tuning file

## Prerequisites

```bash
sudo apt install build-essential meson ninja-build pkg-config \
  libgnutls28-dev libudev-dev libyaml-dev python3-yaml python3-jinja2 \
  libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev
```

**Important:** `libgnutls28-dev` is required for IPA module signing. Without it, the IPA runs in an isolated process that fails due to AppArmor's `restrict_unprivileged_userns`, resulting in zero camera formats in PipeWire.

## Build and Install libcamera

```bash
# Clone and checkout the Ubuntu 25.10 matching version
git clone https://git.libcamera.org/libcamera/libcamera.git
cd libcamera
git checkout v0.5.0 -b ubuntu-0.5.0

# Apply the patch
git apply /path/to/patches/libcamera-ipu6-ov01a10.patch

# Copy the tuning file
cp /path/to/patches/ov01a10.yaml src/ipa/simple/data/

# Configure (simple pipeline only, matching Ubuntu's installed version)
meson setup build --prefix=/usr \
  -Dpipelines=simple,uvcvideo,vimc \
  -Dipas=simple,vimc

# Verify gnutls was found
# Look for: "IPA modules signed with : gnutls"

# Build and install
ninja -C build -j$(nproc)
sudo ninja -C build install
```

## WirePlumber Configuration

```bash
mkdir -p ~/.config/wireplumber/wireplumber.conf.d

# Ensure libcamera monitor is enabled
cp config/99-libcamera.conf ~/.config/wireplumber/wireplumber.conf.d/

# Optional: boost built-in camera priority
cp config/50-prefer-builtin-camera.conf ~/.config/wireplumber/wireplumber.conf.d/
```

Restart PipeWire and WirePlumber:

```bash
systemctl --user restart pipewire wireplumber
```

## Firefox Setup

The Firefox snap cannot use PipeWire cameras due to sandbox restrictions. Install Firefox as a native deb from Mozilla's repository:

```bash
# Add Mozilla APT repo
wget -q https://packages.mozilla.org/apt/repo-signing-key.gpg -O- | \
  sudo tee /etc/apt/keyrings/packages.mozilla.org.asc > /dev/null

echo "deb [signed-by=/etc/apt/keyrings/packages.mozilla.org.asc] https://packages.mozilla.org/apt mozilla main" | \
  sudo tee /etc/apt/sources.list.d/mozilla.list > /dev/null

# Pin Mozilla's package over Ubuntu's snap transitional package
echo 'Package: firefox*
Pin: origin packages.mozilla.org
Pin-Priority: 1001' | sudo tee /etc/apt/preferences.d/mozilla-firefox > /dev/null

# Remove snap Firefox and install deb
sudo snap remove firefox
sudo apt update
sudo apt install firefox=148.0~build1  # or latest version

# Migrate profile from snap (passwords, cookies, bookmarks)
cp -a ~/snap/firefox/common/.mozilla/firefox/*.default*/* ~/.mozilla/firefox/*.default*/
```

In Firefox `about:config`, set:

```
media.webrtc.camera.allow-pipewire = true
```

Restart Firefox. The camera should appear in Google Meet, Jitsi, etc.

## Verify It Works

```bash
# Check PipeWire sees the camera with formats
wpctl status  # Should show "Built-in Front Camera" under Video Sources

# Test with qcam
qcam

# Test with GStreamer
gst-launch-1.0 libcamerasrc ! videoconvert ! autovideosink
```

## Tuning the Color Correction Matrix

The tuning file `patches/ov01a10.yaml` controls color correction (CCM), black level, and other ISP parameters. If you edit it after installation, you must copy it to the installed location and restart PipeWire:

```bash
sudo cp patches/ov01a10.yaml /usr/share/libcamera/ipa/simple/ov01a10.yaml
systemctl --user restart pipewire wireplumber
```

Changes won't take effect until the file is copied — libcamera reads from `/usr/share/`, not from the source tree.

## Notes

- The ov01a10 is a 1.3MP fixed-focus sensor. Image quality is limited by hardware.
- Cheese and GNOME Camera/Snapshot work through PipeWire without any Firefox-specific changes.
- Chromium snap has the same issue as Firefox snap. Use a native deb or Flatpak build instead.
- After a system update that replaces `/usr/lib/x86_64-linux-gnu/libcamera.so`, you'll need to rebuild and reinstall.

## Tested On

- Ubuntu 25.10 (Questing Quetzal)
- Kernel 6.17.0-14-generic
- PipeWire 1.4.7
- libcamera v0.5.0
- Firefox 148.0 (deb)
