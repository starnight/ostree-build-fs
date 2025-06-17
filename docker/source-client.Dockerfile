FROM docker.io/library/alpine:latest

RUN apk update \
    && apk add --no-cache ostree-push openssh-client \
    && ssh-keygen -A

CMD ["/bin/sh"]
