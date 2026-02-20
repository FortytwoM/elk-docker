ARG ELASTIC_VERSION

FROM docker.elastic.co/elastic-agent/elastic-agent:${ELASTIC_VERSION:-9.3.0}

USER root

RUN mkdir -p state && chown elastic-agent:elastic-agent state

COPY install-ca.sh /usr/local/bin/install-ca.sh
RUN sed -i 's/\r$//' /usr/local/bin/install-ca.sh && chmod +x /usr/local/bin/install-ca.sh
