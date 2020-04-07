FROM alpine:latest

RUN apk add dnscrypt-proxy bash xxd

COPY root/ /

EXPOSE 53/udp 53/tcp

ENTRYPOINT ["/startup.sh"]
