#!/bin/bash
set -ex

# This script must run inside a container only.
if [ ! -f /.dockerenv ] && [ ! -f /.containerenv ] && [ ! -f /run/.containerenv ]; then
  echo "ERROR: script works in Docker/Podman only!"
  exit 1
fi

# shellcheck disable=SC1091
source /workspace/versions.config

### Variables

BUILD_RESULT_PATH="/workspace"
BUILD_PATH="/build"

VERSION=${VERSION:-${CIRCLE_TAG:-dirty}}
IMAGE_NAME="alpineos-rpi-${VERSION}.img"
export VERSION

ROOTFS_TAR="rootfs-armhf-${ALPINE_OS_VERSION}.tar.gz"
ROOTFS_TAR_PATH="${BUILD_RESULT_PATH}/${ROOTFS_TAR}"

echo "CIRCLE_TAG=${CIRCLE_TAG:-}"
echo "Building image: ${IMAGE_NAME}"

### Download rootfs tarball if not present locally

if [ ! -f "${ROOTFS_TAR_PATH}" ]; then
  echo "Downloading rootfs tarball ${ALPINE_OS_VERSION}..."
  wget -q -O "${ROOTFS_TAR_PATH}" \
    "https://github.com/barthel/alpine-os-rootfs/releases/download/${ALPINE_OS_VERSION}/${ROOTFS_TAR}"
fi

# Verify checksum if configured
if [ -n "${ROOTFS_TAR_CHECKSUM}" ]; then
  echo "${ROOTFS_TAR_CHECKSUM} ${ROOTFS_TAR_PATH}" | sha256sum -c -
fi

### Create blank disk image

IMAGE_PATH="${BUILD_RESULT_PATH}/${IMAGE_NAME}"
rm -f "${IMAGE_PATH}"
# Use fallocate for a fast sparse image (1 GiB: 256 MiB boot + ~768 MiB root)
fallocate -l 1G "${IMAGE_PATH}"

# Partition: MBR, boot=FAT32 (256 MiB), root=ext4 (rest)
parted -s "${IMAGE_PATH}" \
  mklabel msdos \
  mkpart primary fat32 4MiB 260MiB \
  mkpart primary ext4  260MiB 100% \
  set 1 boot on

# Attach loop device and create partition devices
LOOP_DEV=$(losetup -f --show "${IMAGE_PATH}")
kpartx -as "${LOOP_DEV}"
LOOP_NAME=$(basename "${LOOP_DEV}")
BOOT_PART="/dev/mapper/${LOOP_NAME}p1"
ROOT_PART="/dev/mapper/${LOOP_NAME}p2"

# Retrieve the MBR disk UUID for PARTUUID references in fstab / cmdline.txt
PARTUUID_PREFIX=$(blkid -s PTUUID -o value "${LOOP_DEV}")
export PARTUUID_PREFIX

### Format partitions

mkfs.vfat -F 32 -n BOOT "${BOOT_PART}"
mkfs.ext4 -L root "${ROOT_PART}"

### Extract Alpine rootfs into root partition

mkdir -p "${BUILD_PATH}"
mount "${ROOT_PART}" "${BUILD_PATH}"
tar xf "${ROOTFS_TAR_PATH}" -C "${BUILD_PATH}"
mkdir -p "${BUILD_PATH}/boot"

### Prepare chroot

# Register QEMU for armhf cross-execution
update-binfmts --enable qemu-arm || true
cp /usr/bin/qemu-arm-static "${BUILD_PATH}/usr/bin/"

# Ensure DNS resolves inside chroot
cp /etc/resolv.conf "${BUILD_PATH}/etc/resolv.conf"

# Copy builder file overlays
cp -R /builder/files/etc "${BUILD_PATH}/"

# Mount pseudo filesystems
mkdir -p "${BUILD_PATH}"/{proc,sys,dev/pts}
mount -o bind /dev     "${BUILD_PATH}/dev"
mount -o bind /dev/pts "${BUILD_PATH}/dev/pts"
mount -t proc  none    "${BUILD_PATH}/proc"
mount -t sysfs none    "${BUILD_PATH}/sys"

### Run chroot script

chroot "${BUILD_PATH}" \
  /usr/bin/env \
  VERSION="${VERSION}" \
  PARTUUID_PREFIX="${PARTUUID_PREFIX}" \
  ALPINE_VERSION="${ALPINE_VERSION}" \
  /bin/sh < /builder/chroot-script.sh

### Unmount pseudo filesystems

umount -lqn "${BUILD_PATH}/dev/pts" || true
umount -lqn "${BUILD_PATH}/dev"     || true
umount -lqn "${BUILD_PATH}/proc"    || true
umount -lqn "${BUILD_PATH}/sys"     || true

# Remove QEMU binary — host tool, not for target
rm -f "${BUILD_PATH}/usr/bin/qemu-arm-static"

### Populate FAT32 boot partition

mount "${BOOT_PART}" "${BUILD_PATH}/boot"

# Raspberry Pi firmware (from raspberrypi-bootloader package)
RPi_FW_DIR="${BUILD_PATH}/usr/share/raspberrypi/boot"
if [ -d "${RPi_FW_DIR}" ]; then
  cp "${RPi_FW_DIR}"/*.elf "${BUILD_PATH}/boot/" 2>/dev/null || true
  cp "${RPi_FW_DIR}"/*.dat "${BUILD_PATH}/boot/" 2>/dev/null || true
  cp "${RPi_FW_DIR}"/*.img "${BUILD_PATH}/boot/" 2>/dev/null || true
  cp "${RPi_FW_DIR}/bootcode.bin" "${BUILD_PATH}/boot/" 2>/dev/null || true
fi

# Copy cloud-init seed files
cp /builder/files/boot/user-data      "${BUILD_PATH}/boot/"
cp /builder/files/boot/meta-data      "${BUILD_PATH}/boot/"
cp /builder/files/boot/network-config "${BUILD_PATH}/boot/"

umount "${BUILD_PATH}/boot"

### Write fstab (needs PARTUUID, done after chroot)

cat >> "${BUILD_PATH}/etc/fstab" << EOF
PARTUUID=${PARTUUID_PREFIX}-01 /boot vfat defaults 0 0
PARTUUID=${PARTUUID_PREFIX}-02 /     ext4 defaults,noatime 0 1
EOF

### Unmount root partition and release loop device

umount "${BUILD_PATH}"
kpartx -d "${LOOP_DEV}"
losetup -d "${LOOP_DEV}"

### Compress and checksum

umask 0000
cd "${BUILD_RESULT_PATH}"
zip "${IMAGE_NAME}.zip" "${IMAGE_NAME}"
sha256sum "${IMAGE_NAME}.zip" > "${IMAGE_NAME}.zip.sha256"
rm "${IMAGE_NAME}"

### Run tests

VERSION="${VERSION}" rspec --format documentation --color /builder/test
