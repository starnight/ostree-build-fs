FROM docker.io/library/alpine:edge

RUN head -n 1 /etc/apk/repositories | sed -e 's/main$/testing/' >> /etc/apk/repositories \
    && apk update \
    && apk add --no-cache ostree ostree-push openssh-server \
    && ssh-keygen -A \
    && adduser -G root ostreejob -D \
    && echo ostreejob:ostreejob | chpasswd \
    && echo "# Allow \"TCP forwarding\" and \"Gateway Ports\" for the ssh tunnel built by ostree-push" >> /etc/ssh/sshd_config.d/99-port-forward.conf \
    && echo "AllowTcpForwarding yes" >> /etc/ssh/sshd_config.d/99-port-forward.conf \
    && echo "GatewayPorts yes" >> /etc/ssh/sshd_config.d/99-port-forward.conf

CMD ["/usr/sbin/sshd", "-D"]
