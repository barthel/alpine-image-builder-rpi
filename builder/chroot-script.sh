#!/bin/sh
# Runs inside the Alpine chroot under busybox ash — POSIX sh only.
set -ex

### Package repositories

cat > /etc/apk/repositories << EOF
https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION}/main
https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION}/community
EOF

apk update

### Raspberry Pi kernel and firmware

apk add --no-cache \
  linux-rpi \
  raspberrypi-bootloader

### Docker CE

apk add --no-cache \
  docker \
  docker-openrc

### cloud-init

apk add --no-cache \
  cloud-init \
  cloud-init-openrc \
  e2fsprogs

### WiFi

apk add --no-cache \
  wpa_supplicant \
  wpa_supplicant-openrc \
  wireless-tools \
  wireless-regdb

### Enable OpenRC services

rc-update add docker default

# cloud-init runs in four ordered stages
for svc in cloud-init-local cloud-init cloud-config cloud-final; do
  rc-update add "${svc}" default 2>/dev/null || true
done

rc-update add wpa_supplicant default 2>/dev/null || true

### cloud-init: link seed files from FAT32 /boot partition

mkdir -p /var/lib/cloud/seed/nocloud-net
ln -sf /boot/user-data      /var/lib/cloud/seed/nocloud-net/user-data
ln -sf /boot/meta-data      /var/lib/cloud/seed/nocloud-net/meta-data
ln -sf /boot/network-config /var/lib/cloud/seed/nocloud-net/network-config

### Raspberry Pi boot configuration

# config.txt — RPi firmware settings
cat > /boot/config.txt << EOF
# AlpineOS RPi boot configuration
arm_64bit=0
kernel=vmlinuz-rpi
initramfs initramfs-rpi followkernel
enable_uart=0
hdmi_force_hotplug=1
gpu_mem=16

# Camera (disabled by default)
start_x=0
disable_camera_led=1
EOF

# cmdline.txt — kernel command line
echo "dwc_otg.lpm_enable=0 console=serial0,115200 console=tty1 root=PARTUUID=${PARTUUID_PREFIX}-02 rootfstype=ext4 fsck.repair=yes rootwait quiet" \
  > /boot/cmdline.txt

### OS identification

printf 'ALPINE_DEVICE="Raspberry Pi"\n' >> /etc/os-release
printf 'ALPINE_IMAGE_VERSION="%s"\n' "${VERSION}" >> /etc/os-release
cp /etc/os-release /boot/os-release

### Clean up

rm -rf /var/cache/apk/*
