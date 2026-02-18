ARG ELASTIC_VERSION

# https://www.docker.elastic.co/
FROM docker.elastic.co/elasticsearch/elasticsearch:${ELASTIC_VERSION:-9.3.0}

# Entrypoint that optionally replaces x-pack-core with a patched JAR before startup (set CRACK_JAR and ELASTIC_VERSION).
COPY --chmod=755 entrypoint.sh /entrypoint.sh

ENV ELASTIC_VERSION=${ELASTIC_VERSION}

ENTRYPOINT ["/entrypoint.sh"]
CMD ["eswrapper"]

# Add your elasticsearch plugins setup here
# Example: RUN elasticsearch-plugin install analysis-icu
