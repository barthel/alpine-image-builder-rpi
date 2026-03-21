#!/bin/sh
# Runs inside the Alpine chroot under busybox ash — POSIX sh only.
set -ex

ALPINE_ARCH="${ALPINE_ARCH:-armhf}"
ALPINE_MINOR="$(echo "${ALPINE_VERSION}" | cut -d. -f1,2)"

### Package repositories

cat > /etc/apk/repositories << EOF
https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_MINOR}/main
https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_MINOR}/community
EOF

apk update

### Raspberry Pi kernel, firmware, and arch-specific packages

if [ "${ALPINE_ARCH}" = "aarch64" ]; then
  # Pi 3B (arm64): linux-rpi4 supports BCM2837; wired-only host, no WiFi needed
  apk add --no-cache \
    linux-rpi4 \
    raspberrypi-bootloader

  cat > /boot/config.txt << EOF
# AlpineOS RPi boot configuration (arm64 / Pi 3B)
arm_64bit=1
kernel=vmlinuz-rpi4
initramfs initramfs-rpi4 followkernel
enable_uart=0
hdmi_force_hotplug=1
gpu_mem=32
EOF

  echo "dwc_otg.lpm_enable=0 console=serial0,115200 console=tty1 root=/dev/mmcblk0p2 rootfstype=ext4 fsck.repair=yes rootwait quiet" \
    > /boot/cmdline.txt

  printf 'ALPINE_DEVICE="Raspberry Pi 3B"\n' >> /etc/os-release

else
  # armhf (Pi Zero W): linux-rpi + WiFi (BCM43430 SDIO)
  apk add --no-cache \
    linux-rpi \
    raspberrypi-bootloader \
    wpa_supplicant \
    wpa_supplicant-openrc \
    wireless-tools \
    wireless-regdb

  rc-update add wpa_supplicant default 2>/dev/null || true

  # Load brcmfmac at boot for BCM43430 WiFi (Pi Zero W SDIO chip).
  echo "brcmfmac" >> /etc/modules

  cat > /boot/config.txt << EOF
# AlpineOS RPi boot configuration (armhf / Pi Zero W)
arm_64bit=0
kernel=vmlinuz-rpi
initramfs initramfs-rpi followkernel
enable_uart=0
hdmi_force_hotplug=1
gpu_mem=32
EOF

  echo "dwc_otg.lpm_enable=0 console=serial0,115200 console=tty1 root=/dev/mmcblk0p2 rootfstype=ext4 fsck.repair=yes rootwait quiet" \
    > /boot/cmdline.txt

  printf 'ALPINE_DEVICE="Raspberry Pi"\n' >> /etc/os-release

fi

### Docker CE

apk add --no-cache \
  docker \
  docker-cli-compose \
  docker-openrc

### cloud-init

apk add --no-cache \
  cloud-init \
  cloud-init-openrc \
  e2fsprogs \
  e2fsprogs-extra

### Enable OpenRC services

# sysfs, cgroups, modules: added to runlevels by build.sh (from the build host,
# after the chroot exits) because rc-update detects the Docker build environment
# via /proc cgroup namespace and silently skips keyword -docker services.
rc-update add docker default

# cloud-init runs in four ordered stages
for svc in cloud-init-local cloud-init cloud-config cloud-final; do
  rc-update add "${svc}" default 2>/dev/null || true
done

### cloud-init: link seed files from FAT32 /boot partition

mkdir -p /var/lib/cloud/seed/nocloud-net
ln -sf /boot/user-data      /var/lib/cloud/seed/nocloud-net/user-data
ln -sf /boot/meta-data      /var/lib/cloud/seed/nocloud-net/meta-data
ln -sf /boot/network-config /var/lib/cloud/seed/nocloud-net/network-config

### OS identification

printf 'ALPINE_IMAGE_VERSION="%s"\n' "${VERSION}" >> /etc/os-release
cp /etc/os-release /boot/os-release

### Clean up

rm -rf /var/cache/apk/*
