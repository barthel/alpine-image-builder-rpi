BASE_TAG ?= latest

default: build

build:
	docker build --build-arg BASE_TAG=$(BASE_TAG) -t alpine-image-builder-rpi .

sd-image: build
	docker run --rm --privileged \
	  -v $(shell pwd):/workspace \
	  -e CIRCLE_TAG \
	  -e VERSION \
	  -e ALPINE_OS_VERSION \
	  alpine-image-builder-rpi

shell: build
	docker run -ti --rm --privileged \
	  -v $(shell pwd):/workspace \
	  -e CIRCLE_TAG \
	  -e VERSION \
	  -e ALPINE_OS_VERSION \
	  alpine-image-builder-rpi bash

test: build
	VERSION=latest docker run --rm --privileged \
	  -v $(shell pwd):/workspace \
	  -e VERSION=latest \
	  alpine-image-builder-rpi bash -c "rspec --format documentation --color /builder/test"

shellcheck: build
	docker run --rm \
	  -v $(shell pwd):/workspace \
	  alpine-image-builder-rpi bash -c 'shellcheck /builder/build.sh /builder/chroot-script.sh'

tag:
	git tag $(TAG)
	git push origin $(TAG)
