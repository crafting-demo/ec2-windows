FROM maven:3.6-openjdk-11 AS builder
ADD guacamole-jetty /src
RUN cd /src && mvn package

FROM guacamole/guacd:1.5.4
USER root
RUN apk update && apk add openjdk11-jre-headless bash && apk cache clean
COPY --from=builder /src/target/guacamole-jetty-1.0.0-jar-with-dependencies.jar /guacamole-jetty.jar
ADD start.sh /

# The image runs as the unprivileged guacd user, which cannot create directories
# under /etc. Without this the tunnel fails to persist its RDP parameters and
# silently reverts to defaults whenever the container restarts.
RUN mkdir -p /etc/guacamole && chown guacd:guacd /etc/guacamole

USER guacd
ENTRYPOINT ["/start.sh"]
EXPOSE 4822 8080 8081
