ARG ELASTIC_VERSION

FROM docker.elastic.co/elasticsearch/elasticsearch:${ELASTIC_VERSION}

USER 0
RUN microdnf install --setopt=tsflags=nodocs -y openssl unzip && \
    microdnf clean all
USER 1000:0

ENTRYPOINT ["/entrypoint.sh"]
