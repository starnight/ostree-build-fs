FROM docker.io/library/python:3-alpine

RUN apk add --no-cache build-base cmake cairo-dev gobject-introspection-dev ostree ostree-gir openssh-server \
    && pip install ostree-push \
    && ssh-keygen -A \
    && adduser -G root ostreejob -D \
    && echo ostreejob:ostreejob | chpasswd \
    && echo "# Allow \"TCP forwarding\" and \"Gateway Ports\" for the ssh tunnel built by ostree-push" >> /etc/ssh/sshd_config.d/99-port-forward.conf \
    && echo "AllowTcpForwarding yes" >> /etc/ssh/sshd_config.d/99-port-forward.conf \
    && echo "GatewayPorts yes" >> /etc/ssh/sshd_config.d/99-port-forward.conf

CMD ["/usr/sbin/sshd", "-D"]
