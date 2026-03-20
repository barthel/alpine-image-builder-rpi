FROM uwebarthel/alpine-image-builder:latest

COPY builder /builder/

CMD ["/builder/build.sh"]
