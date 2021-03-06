FROM alpine:latest

RUN apk add --no-cache \
  aws-cli \
  bash \
  ca-certificates \
  curl \
  jq

COPY *.sh /

RUN chmod +x /*.sh

ENTRYPOINT ["/entrypoint.sh"]
