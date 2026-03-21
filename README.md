# alpine-image-builder-rpi

Builds bootable SD card images with AlpineOS for Raspberry Pi boards.
Two architectures are produced in a single build run:

| Image | Arch | Target board |
|---|---|---|
| `alpineos-rpi-<version>.img.zip` | armhf (ARMv6) | Raspberry Pi Zero W |
| `alpineos-rpi-arm64-<version>.img.zip` | aarch64 | Raspberry Pi 3B |

Based on the rootfs from
[alpine-os-rootfs](https://github.com/barthel/alpine-os-rootfs).

## What each image contains

**Both images include:**
- Alpine Linux base rootfs
- Raspberry Pi firmware (`raspberrypi-bootloader`)
- Docker CE with OpenRC service enabled
- cloud-init (NoCloud datasource, seeded from `/boot`)
- WiFi support: `wpa_supplicant`, `wpa_supplicant-openrc`, `wireless-tools`, `wireless-regdb`, `brcmfmac` kernel module
- OpenRC init system

**armhf image (Pi Zero W):**
- Kernel: `linux-rpi`
- `config.txt`: `arm_64bit=0`, `kernel=vmlinuz-rpi`
- `ALPINE_DEVICE="Raspberry Pi"`

**arm64 image (Pi 3B):**
- Kernel: `linux-rpi4` (supports BCM2837 of Pi 3B)
- `config.txt`: `arm_64bit=1`, `kernel=vmlinuz-rpi4`
- `ALPINE_DEVICE="Raspberry Pi 3B"`

## Disk layout

| Partition | Filesystem | Size | Contents |
|---|---|---|---|
| `/dev/mmcblk0p1` | FAT32 | 256 MiB | Firmware, kernel, dtbs, cloud-init seed, config.txt |
| `/dev/mmcblk0p2` | ext4 | ~768 MiB → full SD card | Alpine rootfs (resized to full SD card on first boot) |

## Prerequisites

- Docker

## Build

```bash
# Build the builder image and both SD card images (armhf + aarch64)
./build.sh
```

Output: `alpineos-rpi-dirty.img.zip` and `alpineos-rpi-arm64-dirty.img.zip`
plus `.sha256` files in the project root.
Tests run automatically at the end of each build (for both architectures).

### Versioning

Versions follow the Alpine version: `MAJOR.MINOR.BUILD`.
`BUILD` starts at 0 and increments with each change while on the same Alpine minor.

### Versioned build

```bash
VERSION=3.21.0 ./build.sh
```

### Push to Docker Hub

```bash
VERSION=3.21.0 PUSH=true ./build.sh
```

This pushes:
- `uwebarthel/alpine-image-builder-rpi:<version>` — builder image (multi-arch: amd64 + arm64)
- `uwebarthel/alpineos-rpi:<version>` — armhf SD image distribution (platform: linux/arm/v6)
- `uwebarthel/alpineos-rpi-arm64:<version>` — arm64 SD image distribution (platform: linux/arm64)

## Docker Hub images

| Image | Platform | Use |
|---|---|---|
| `uwebarthel/alpineos-rpi` | `linux/arm/v6` | Flash to Pi Zero W SD card |
| `uwebarthel/alpineos-rpi-arm64` | `linux/arm64` | Flash to Pi 3B SD card |
| `uwebarthel/alpine-image-builder-rpi` | `linux/amd64`, `linux/arm64` | Builder image (CI) |

Extract the image zip:
```bash
cid=$(docker create uwebarthel/alpineos-rpi:latest)
docker cp "${cid}:/image/image.img.zip" .
docker rm "${cid}"
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

CircleCI builds and tests both images on every push and every tag.
On a tag push, both image zips are published as a GitHub Release:

- `alpineos-rpi.img.zip` — stable name for armhf (Pi Zero W)
- `alpineos-rpi-arm64.img.zip` — stable name for arm64 (Pi 3B)

The pipeline uses contexts `github` (for `GITHUB_USER`) and `Docker Hub`
(for `DOCKER_USER` / `DOCKER_PASS`).

## Repository structure

```
Dockerfile              Builder container (Debian bookworm + QEMU + loop-device tools)
build.sh                Outer build: pulls rootfs tarballs, runs two builder passes (armhf + aarch64), optional push
versions.config         Pinned rootfs version and checksum
builder/
  build.sh              Creates disk image: MBR partition, extract rootfs, chroot, boot setup
  chroot-script.sh      apk installs: linux-rpi / linux-rpi4 (arch-dependent), docker, cloud-init, WiFi
  files/
    boot/
      user-data         Default cloud-init user-data
      meta-data         cloud-init instance-id
      network-config    cloud-init network config (eth0 DHCP)
    etc/
      cloud/
        cloud.cfg       cloud-init config (distro: alpine, NoCloud datasource)
  test/
    spec_helper.rb      Test helper (image_path selects zip name by ALPINE_ARCH)
    image_spec.rb       Verifies image zip exists
    os-release_spec.rb  Verifies image archive contents
```
