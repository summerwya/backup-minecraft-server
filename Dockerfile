FROM alpine:3.24.4

RUN apk add --no-cache fish=4.8.1-r1 par2cmdline=1.4.0-r0 7zip=26.01-r0 rcon-cli=1.7.5-r2 docker-cli=29.9.3-r0
RUN addgroup -S backup && adduser -S backup -G backup

WORKDIR /app
COPY --chown=backup:backup backup.fish .

USER backup
ENTRYPOINT ["fish", "/app/backup.fish"]