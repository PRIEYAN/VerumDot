#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

echo "=== NVIDIA Suspend/Resume Fixer for Arch Linux ==="

# 1. Update /etc/modprobe.d/nvidia.conf
CONF_FILE="/etc/modprobe.d/nvidia.conf"
PARAM="options nvidia NVreg_PreserveVideoMemoryAllocations=1"

echo "Checking $CONF_FILE..."
if [ ! -f "$CONF_FILE" ]; then
    echo "Creating $CONF_FILE..."
    echo "$PARAM" > "$CONF_FILE"
else
    if grep -q "NVreg_PreserveVideoMemoryAllocations" "$CONF_FILE"; then
        echo "Parameter already in $CONF_FILE."
    else
        echo "Adding parameter to $CONF_FILE..."
        echo "$PARAM" >> "$CONF_FILE"
    fi
fi

# Ensure options nvidia-drm modeset=1 is also there
DRM_PARAM="options nvidia-drm modeset=1"
if ! grep -q "nvidia-drm modeset" "$CONF_FILE"; then
    echo "Adding $DRM_PARAM to $CONF_FILE..."
    echo "$DRM_PARAM" >> "$CONF_FILE"
fi

echo "File content of $CONF_FILE:"
cat "$CONF_FILE"
echo ""

# 2. Enable NVIDIA systemd services
echo "Enabling NVIDIA systemd services..."
systemctl enable nvidia-suspend.service
systemctl enable nvidia-hibernate.service
systemctl enable nvidia-resume.service

# 3. Rebuild initramfs
echo "Rebuilding initramfs using mkinitcpio..."
mkinitcpio -P

echo "=== Success! Please reboot your system to apply changes. ==="
