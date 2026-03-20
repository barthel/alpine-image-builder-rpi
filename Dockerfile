ARG BASE_TAG=latest
FROM uwebarthel/alpine-image-builder:${BASE_TAG}

COPY builder /builder/

CMD ["/builder/build.sh"]
