FROM alpine:3.24.4

RUN apk add --no-cache fish par2cmdline 7zip rcon-cli docker-cli-compose
RUN addgroup -S backup && adduser -S backup -G backup

WORKDIR /app
RUN chown -R backup:backup /app
COPY --chown=backup:backup backup.fish .

USER backup
ENTRYPOINT ["fish", "/app/backup.fish"]