# Fixture for the docker.yml self-test (built on pull requests only, never pushed).
FROM busybox:1.37
COPY hello.txt /hello.txt
ARG APP_VERSION=dev
RUN echo "$APP_VERSION" > /version.txt && cat /hello.txt /version.txt
CMD ["cat", "/hello.txt", "/version.txt"]
