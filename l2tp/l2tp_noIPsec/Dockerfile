#FROM ghcr.io/linuxserver/baseimage-alpine:arm64v8-3.21
FROM ghcr.io/linuxserver/baseimage-alpine:3.21

ENV LANG C.UTF-8

RUN apk update && apk add --no-cache \
    bash \
    xl2tpd \
    iproute2 \
    iputils \
    curl \
    iptables \
    net-tools \
    && rm -rf /var/cache/apk/*

RUN mkdir -p /app

COPY --chown=root:root configs/ /app/configs/
COPY --chown=root:root scripts/ppp_manager.sh /app/scripts/ppp_manager.sh
COPY --chown=root:root scripts/ppp_setup.sh /app/scripts/ppp_setup.sh

RUN chown -R root:root /app
RUN chmod 751 /app/scripts/ppp_manager.sh
RUN chmod 751 /app/scripts/ppp_setup.sh
RUN chmod 600 /app/configs/chap-secrets
RUN chmod 640 /app/configs/options.myvpn
RUN chmod 640 /app/configs/xl2tpd.conf

WORKDIR /app

VOLUME /lib/modules

EXPOSE 1701/udp

# Set entrypoint to start ppp_manager
ENTRYPOINT ["/app/scripts/ppp_manager.sh"]