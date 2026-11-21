# Alpine keeps the sandbox image small. Override the base when Docker Hub is
# already cached under another tag: docker build --build-arg BASE=alpine:3.14.0
ARG BASE=alpine:3.20
FROM ${BASE}

RUN apk add --no-cache python3 curl ca-certificates \
    && ln -sf /usr/bin/python3 /usr/local/bin/python \
    && command -v curl | grep -qx /usr/bin/curl \
    && adduser -D -u 1000 -g 1000 agent

COPY agent.py /opt/sample-agent/agent.py
RUN chmod 755 /opt/sample-agent/agent.py

# Files are world-readable. The 0.1.9 Kubernetes driver selected uid 10001
# when sandboxUid was left unset.
ENV PYTHONDONTWRITEBYTECODE=1 \
    HOME=/tmp

USER 1000:1000
WORKDIR /sandbox

CMD ["/usr/local/bin/python", "/opt/sample-agent/agent.py"]
