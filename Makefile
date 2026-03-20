default: build

build:
	docker build -t alpine-image-builder-rpi .

sd-image: build
	docker run --rm --privileged \
	  -v $(shell pwd):/workspace \
	  -e CIRCLE_TAG \
	  -e VERSION \
	  alpine-image-builder-rpi

shell: build
	docker run -ti --rm --privileged \
	  -v $(shell pwd):/workspace \
	  -e CIRCLE_TAG \
	  -e VERSION \
	  alpine-image-builder-rpi bash

test: build
	VERSION=dirty docker run --rm --privileged \
	  -v $(shell pwd):/workspace \
	  -e VERSION=dirty \
	  alpine-image-builder-rpi bash -c "rspec --format documentation --color /builder/test"

shellcheck: build
	docker run --rm \
	  -v $(shell pwd):/workspace \
	  alpine-image-builder-rpi bash -c 'shellcheck /builder/build.sh /builder/chroot-script.sh'

tag:
	git tag $(TAG)
	git push origin $(TAG)
