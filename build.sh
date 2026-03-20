#!/bin/bash
# build.sh — builds Alpine SD card image for Raspberry Pi.
#
# Usage:
#   ./build.sh                          # local build, BASE_TAG=latest, ALPINE_OS_VERSION=stable
#   VERSION=3.21.0 ./build.sh           # versioned build: BASE_TAG=3.21, ALPINE_OS_VERSION=3.21.0
#   VERSION=3.21.0 PUSH=true ./build.sh # versioned build + push builder image to Docker Hub
#
# Environment:
#   DOCKER_USER   Docker Hub username (default: uwebarthel)
#   VERSION       Release version tag, e.g. 3.21.0 (default: empty = latest)
#   PUSH          Set to "true" to push the builder image to Docker Hub
set -e

DOCKER_USER="${DOCKER_USER:-uwebarthel}"
IMAGE_NAME="alpine-image-builder-rpi"
DIST_IMAGE="${DOCKER_USER}/${IMAGE_NAME}"

if [ -n "${VERSION}" ]; then
  BASE_TAG="${VERSION%.*}"       # major.minor, e.g. 3.21 from 3.21.0
  ALPINE_OS_VERSION="${VERSION}"
else
  BASE_TAG="latest"
  ALPINE_OS_VERSION="stable"
fi

echo "Building ${IMAGE_NAME} (base: ${DOCKER_USER}/alpine-image-builder:${BASE_TAG})..."
docker build --build-arg BASE_TAG="${BASE_TAG}" -t "${IMAGE_NAME}" .

# Pull rootfs tarball from Docker Hub (uwebarthel/alpine-os-rootfs:<version>)
# The image contains /rootfs/rootfs-armhf.tar.gz (and aarch64, x86_64).
if [ ! -f "rootfs-armhf.tar.gz" ]; then
  echo "Pulling rootfs from ${DOCKER_USER}/alpine-os-rootfs:${ALPINE_OS_VERSION}..."
  cid=$(docker create "${DOCKER_USER}/alpine-os-rootfs:${ALPINE_OS_VERSION}")
  docker cp "${cid}:/rootfs/rootfs-armhf.tar.gz" .
  docker rm "${cid}"
fi

echo "Building SD image (ALPINE_OS_VERSION=${ALPINE_OS_VERSION})..."
docker run --rm --privileged \
  -e ALPINE_OS_VERSION="${ALPINE_OS_VERSION}" \
  -v "$(pwd):/workspace" \
  "${IMAGE_NAME}"

if [ "${PUSH:-false}" = "true" ]; then
  IMG_VERSION="${VERSION:-latest}"
  docker tag "${IMAGE_NAME}" "${DIST_IMAGE}:${IMG_VERSION}"
  docker push "${DIST_IMAGE}:${IMG_VERSION}"

  if [ -n "${VERSION}" ]; then
    MAJOR="${VERSION%%.*}"
    MINOR="${VERSION%.*}"
    PRE=""
    if [[ "${VERSION}" = *"rc"* ]]; then PRE="true"; fi
    if [ -z "${PRE}" ]; then
      for extra_tag in "${MINOR}" "${MAJOR}" latest stable; do
        docker tag "${IMAGE_NAME}" "${DIST_IMAGE}:${extra_tag}"
        docker push "${DIST_IMAGE}:${extra_tag}"
      done
    fi
  fi
fi
