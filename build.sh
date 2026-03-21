#!/bin/bash
# build.sh — builds Alpine SD card image for Raspberry Pi.
#
# Usage:
#   ./build.sh                          # local build, BASE_TAG=latest, ALPINE_OS_VERSION=stable
#   VERSION=3.21.0 ./build.sh           # versioned build: BASE_TAG=3.21, ALPINE_OS_VERSION=3.21.0
#   VERSION=3.21.0 PUSH=true ./build.sh # versioned build + push to Docker Hub
#
# Environment:
#   DOCKER_USER   Docker Hub username (default: uwebarthel)
#   VERSION       Release version tag, e.g. 3.21.0 (default: empty = latest)
#   PUSH          Set to "true" to push builder + SD image distribution to Docker Hub
set -e

DOCKER_USER="${DOCKER_USER:-uwebarthel}"
IMAGE_NAME="alpine-image-builder-rpi"
DIST_IMAGE="${DOCKER_USER}/${IMAGE_NAME}"
IMG_DIST_IMAGE="${DOCKER_USER}/alpineos-rpi"

if [ -n "${VERSION}" ]; then
  BASE_TAG="${VERSION%.*}"       # major.minor, e.g. 3.21 from 3.21.1
  ALPINE_OS_VERSION="${BASE_TAG}"  # alpine-os-rootfs publishes a major.minor tag
else
  BASE_TAG="latest"
  ALPINE_OS_VERSION="stable"
fi

echo "Building ${IMAGE_NAME} (base: ${DOCKER_USER}/alpine-image-builder:${BASE_TAG})..."
docker build --build-arg BASE_TAG="${BASE_TAG}" -t "${IMAGE_NAME}" .

# Pull rootfs tarballs from Docker Hub (uwebarthel/alpine-os-rootfs:<version>)
if [ ! -f "rootfs-armhf.tar.gz" ] || [ ! -f "rootfs-aarch64.tar.gz" ]; then
  echo "Pulling rootfs from ${DOCKER_USER}/alpine-os-rootfs:${ALPINE_OS_VERSION}..."
  cid=$(docker create "${DOCKER_USER}/alpine-os-rootfs:${ALPINE_OS_VERSION}")
  docker cp "${cid}:/rootfs/rootfs-armhf.tar.gz" .
  docker cp "${cid}:/rootfs/rootfs-aarch64.tar.gz" .
  docker rm "${cid}"
fi

echo "Building SD image armhf (ALPINE_OS_VERSION=${ALPINE_OS_VERSION})..."
docker run --rm --privileged \
  -e ALPINE_OS_VERSION="${ALPINE_OS_VERSION}" \
  -e VERSION="${VERSION}" \
  -e ALPINE_ARCH=armhf \
  -v "$(pwd):/workspace" \
  "${IMAGE_NAME}"

echo "Building SD image aarch64 (ALPINE_OS_VERSION=${ALPINE_OS_VERSION})..."
docker run --rm --privileged \
  -e ALPINE_OS_VERSION="${ALPINE_OS_VERSION}" \
  -e VERSION="${VERSION}" \
  -e ALPINE_ARCH=aarch64 \
  -v "$(pwd):/workspace" \
  "${IMAGE_NAME}"

if [ "${PUSH:-false}" = "true" ]; then
  IMG_VERSION="${VERSION:-latest}"
  MAJOR="${VERSION%%.*}"
  MINOR="${VERSION%.*}"
  PRE=""
  if [[ "${VERSION:-}" = *"rc"* ]]; then PRE="true"; fi

  # Push builder image
  docker tag "${IMAGE_NAME}" "${DIST_IMAGE}:${IMG_VERSION}"
  docker push "${DIST_IMAGE}:${IMG_VERSION}"

  # Push SD image distributions (FROM scratch with .img.zip for docker cp extraction)
  # Platform annotation reflects the target architecture, not the build machine.
  mkdir -p .img-ctx
  cat > .img-ctx/Dockerfile << 'EOF'
FROM scratch
COPY image.img.zip /image/
CMD ["/noop"]
EOF

  # armhf distribution
  cp "alpineos-rpi-${IMG_VERSION}.img.zip" .img-ctx/image.img.zip
  docker build --platform linux/arm/v6 --tag "${IMG_DIST_IMAGE}:${IMG_VERSION}" .img-ctx/
  docker push "${IMG_DIST_IMAGE}:${IMG_VERSION}"

  # arm64 distribution
  ARM64_DIST_IMAGE="${DOCKER_USER}/alpineos-rpi-arm64"
  cp "alpineos-rpi-arm64-${IMG_VERSION}.img.zip" .img-ctx/image.img.zip
  docker build --platform linux/arm64 --tag "${ARM64_DIST_IMAGE}:${IMG_VERSION}" .img-ctx/
  docker push "${ARM64_DIST_IMAGE}:${IMG_VERSION}"

  rm -rf .img-ctx

  if [ -n "${VERSION}" ] && [ -z "${PRE}" ]; then
    for extra_tag in "${MINOR}" "${MAJOR}" latest stable; do
      docker tag "${IMAGE_NAME}" "${DIST_IMAGE}:${extra_tag}"
      docker push "${DIST_IMAGE}:${extra_tag}"
      docker tag "${IMG_DIST_IMAGE}:${IMG_VERSION}" "${IMG_DIST_IMAGE}:${extra_tag}"
      docker push "${IMG_DIST_IMAGE}:${extra_tag}"
      docker tag "${ARM64_DIST_IMAGE}:${IMG_VERSION}" "${ARM64_DIST_IMAGE}:${extra_tag}"
      docker push "${ARM64_DIST_IMAGE}:${extra_tag}"
    done
  fi
fi
