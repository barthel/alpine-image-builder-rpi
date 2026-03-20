#!/bin/bash
# build.sh — builds Alpine SD card image for Raspberry Pi.
#
# Usage:
#   ./build.sh                      # local build, BASE_TAG=latest, ALPINE_OS_VERSION=latest
#   VERSION=3.21.0 ./build.sh       # versioned build: BASE_TAG=3.21, ALPINE_OS_VERSION=3.21.0
#
# Environment:
#   VERSION           Release version tag, e.g. 3.21.0 (default: empty = latest)
set -e

IMAGE_NAME="alpine-image-builder-rpi"

if [ -n "${VERSION}" ]; then
  BASE_TAG="${VERSION%.*}"       # major.minor, e.g. 3.21 from 3.21.0
  ALPINE_OS_VERSION="${VERSION}"
else
  BASE_TAG="latest"
  ALPINE_OS_VERSION="latest"
fi

echo "Building ${IMAGE_NAME} (base: uwebarthel/alpine-image-builder:${BASE_TAG})..."
docker build --build-arg BASE_TAG="${BASE_TAG}" -t "${IMAGE_NAME}" .

echo "Building SD image (ALPINE_OS_VERSION=${ALPINE_OS_VERSION})..."
docker run --rm --privileged \
  -e ALPINE_OS_VERSION="${ALPINE_OS_VERSION}" \
  -v "$(pwd):/workspace" \
  "${IMAGE_NAME}"
