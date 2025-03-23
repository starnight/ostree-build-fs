FROM docker.io/library/alpine:edge

RUN head -n 1 /etc/apk/repositories | sed -e 's/main$/testing/' >> /etc/apk/repositories \
    && apk update \
    && apk add --no-cache ostree-push openssh-client \
    && ssh-keygen -A

CMD ["/bin/sh"]
