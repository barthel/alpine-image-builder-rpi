# alpine-image-builder-rpi

Builds a bootable SD card image with AlpineOS for the Raspberry Pi Zero W
(armhf / ARMv6). Based on the rootfs from
[alpine-os-rootfs](https://github.com/barthel/alpine-os-rootfs).

## What the image contains

- Alpine Linux base rootfs (armhf)
- Raspberry Pi kernel (`linux-rpi`) and firmware (`raspberrypi-bootloader`)
- Docker CE with OpenRC service enabled
- cloud-init (NoCloud datasource, seeded from `/boot`)
- WiFi support: `wpa_supplicant`, `wireless-tools`
- OpenRC init system

## Disk layout

| Partition | Filesystem | Size | Contents |
|---|---|---|---|
| `/dev/mmcblk0p1` | FAT32 | 256 MiB | Firmware, kernel, dtbs, cloud-init seed, config.txt |
| `/dev/mmcblk0p2` | ext4 | ~768 MiB | Alpine rootfs |

## Prerequisites

- Docker

## Build

```bash
# Build the builder image
make build

# Build SD card image (uses local rootfs-armhf-dirty.tar.gz if present)
make sd-image
```

Output: `alpineos-rpi-dirty.img.zip` + `.sha256` in the project root.
Tests run automatically at the end of each build.

### Versioned build

```bash
VERSION=0.1.0 make sd-image
```

### Using a released rootfs

Set `ALPINE_OS_VERSION` in `versions.config` to the
[alpine-os-rootfs](https://github.com/barthel/alpine-os-rootfs/releases) tag
and optionally set `ROOTFS_TAR_CHECKSUM` for checksum verification.

If no local tarball is found, the build script downloads it automatically
from the GitHub Release matching `ALPINE_OS_VERSION`.

## Other targets

```bash
make shellcheck   # Run shellcheck against builder/build.sh and chroot-script.sh
make test         # Run serverspec tests against a previously built image zip
make shell        # Open a shell inside the builder container
make tag TAG=0.1.0  # Create and push a git tag
```

## First boot

### Default credentials

| Setting | Value |
|---|---|
| Default hostname | `black-pearl` |
| Default user | `admin` |
| Password | *none set* — SSH key required, or add `plain_text_passwd:` to user-data |
| SSH password auth | enabled (`ssh_pwauth: true`) |
| sudo | passwordless |

Add your SSH public key to `builder/files/boot/user-data` before building:

```yaml
users:
  - name: admin
    # ...
    ssh_authorized_keys:
      - ssh-ed25519 AAAA...
```

Or edit `/boot/user-data` on the SD card after flashing.

### eth0 (wired)
DHCP is configured automatically. The image boots without any configuration.

### WiFi
Uncomment and fill in the WiFi section in `builder/files/boot/user-data`
before building, or edit `/boot/user-data` on the SD card after flashing.

## cloud-init

Seed files on the FAT32 boot partition are linked to the NoCloud datasource:

| File | Purpose |
|---|---|
| `/boot/user-data` | cloud-config: hostname, users, write_files, runcmd |
| `/boot/meta-data` | instance-id |
| `/boot/network-config` | network configuration |

Edit these files on the SD card to customise the first boot.

## CI / Release

CircleCI builds and tests the image on every push and every tag.
On a tag push, the image zip is published as a GitHub Release.

The pipeline uses contexts `github` (for `GITHUB_USER`) and `Docker Hub`
(for `DOCKER_USER` / `DOCKER_PASS`).

## Repository structure

```
Dockerfile              Builder container (Debian bookworm + QEMU + loop-device tools)
Makefile                Build targets: sd-image, shell, shellcheck, test
versions.config         Pinned rootfs version and checksum
builder/
  build.sh              Creates disk image: partition, extract rootfs, chroot, boot setup
  chroot-script.sh      apk installs: linux-rpi, docker, cloud-init, WiFi
  files/
    boot/
      user-data         Default cloud-init user-data
      meta-data         cloud-init instance-id
      network-config    cloud-init network config (eth0 DHCP)
    etc/
      cloud/
        cloud.cfg       cloud-init config (distro: alpine, NoCloud datasource)
  test/
    spec_helper.rb      Test helper
    image_spec.rb       Verifies image zip exists
    os-release_spec.rb  Verifies image archive contents
```
