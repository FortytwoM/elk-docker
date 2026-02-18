ARG ELASTIC_VERSION

# ---- Stage 1: build patched x-pack-core JAR ----
FROM docker.elastic.co/elasticsearch/elasticsearch:${ELASTIC_VERSION:-9.3.0} AS xpack-source

FROM eclipse-temurin:21-jdk AS crack-builder

ARG ELASTIC_VERSION
ENV VERSION=${ELASTIC_VERSION}

WORKDIR /crack
COPY --from=xpack-source /usr/share/elasticsearch/lib /usr/share/elasticsearch/lib
COPY --from=xpack-source /usr/share/elasticsearch/modules/x-pack-core /usr/share/elasticsearch/modules/x-pack-core
COPY crack/build_crack_jar.sh /crack/

RUN sed -i 's/\r$//' build_crack_jar.sh && \
    apt-get update && apt-get install -y curl unzip >/dev/null && \
    bash build_crack_jar.sh

# ---- Stage 2: final Elasticsearch image ----
FROM docker.elastic.co/elasticsearch/elasticsearch:${ELASTIC_VERSION:-9.3.0}

ARG ELASTIC_VERSION

COPY --from=crack-builder --chown=elasticsearch:elasticsearch \
    /crack/output/x-pack-core-${ELASTIC_VERSION}.crack.jar \
    /usr/share/elasticsearch/modules/x-pack-core/x-pack-core-${ELASTIC_VERSION}.jar

# RUN elasticsearch-plugin install analysis-icu
