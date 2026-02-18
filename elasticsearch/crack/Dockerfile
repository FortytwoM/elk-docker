# check=skip=InvalidDefaultArgInFrom
ARG VERSION

FROM docker.elastic.co/elasticsearch/elasticsearch:${VERSION} AS baseline

FROM eclipse-temurin:21-jdk

ARG VERSION
ENV VERSION=${VERSION}

WORKDIR /crack

COPY --from=baseline /usr/share/elasticsearch/lib /usr/share/elasticsearch/lib
COPY --from=baseline /usr/share/elasticsearch/modules/x-pack-core /usr/share/elasticsearch/modules/x-pack-core
COPY build_crack_jar.sh /crack

RUN apt-get update && apt-get install -y curl unzip >/dev/null

CMD [ "bash", "build_crack_jar.sh" ]
