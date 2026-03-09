#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Intel IPU6 Camera (ov01a10) Setup ==="
echo ""

# Check dependencies
echo "[1/6] Checking dependencies..."
sudo apt install -y build-essential meson ninja-build pkg-config \
  libgnutls28-dev libudev-dev libyaml-dev python3-yaml python3-jinja2 \
  libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev

# Clone libcamera if needed
echo "[2/6] Setting up libcamera..."
LIBCAMERA_DIR="${LIBCAMERA_DIR:-$HOME/Code/libcamera}"
if [ ! -d "$LIBCAMERA_DIR" ]; then
    git clone https://git.libcamera.org/libcamera/libcamera.git "$LIBCAMERA_DIR"
fi
cd "$LIBCAMERA_DIR"

# Checkout correct version
git checkout v0.5.0 -b ubuntu-0.5.0 2>/dev/null || git checkout ubuntu-0.5.0

# Apply patch
echo "[3/6] Applying patch..."
git apply "$SCRIPT_DIR/patches/libcamera-ipu6-ov01a10.patch" || echo "Patch already applied or conflicts - check manually"
cp "$SCRIPT_DIR/patches/ov01a10.yaml" src/ipa/simple/data/

# Build
echo "[4/6] Building libcamera..."
meson setup build --prefix=/usr \
  -Dpipelines=simple,uvcvideo,vimc \
  -Dipas=simple,vimc 2>/dev/null || meson setup build --reconfigure --prefix=/usr \
  -Dpipelines=simple,uvcvideo,vimc \
  -Dipas=simple,vimc
ninja -C build -j$(nproc)

# Install
echo "[5/6] Installing..."
sudo ninja -C build install

# WirePlumber config
echo "[6/6] Configuring WirePlumber..."
mkdir -p ~/.config/wireplumber/wireplumber.conf.d
cp "$SCRIPT_DIR/config/99-libcamera.conf" ~/.config/wireplumber/wireplumber.conf.d/
cp "$SCRIPT_DIR/config/50-prefer-builtin-camera.conf" ~/.config/wireplumber/wireplumber.conf.d/

# Restart services
systemctl --user restart pipewire wireplumber

echo ""
echo "=== Done! ==="
echo "Test with: qcam"
echo ""
echo "For Firefox: install the deb version (not snap) and set"
echo "  media.webrtc.camera.allow-pipewire = true"
echo "in about:config. See README.md for details."
