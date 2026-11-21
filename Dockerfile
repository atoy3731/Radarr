# syntax=docker/dockerfile:1

# Build stage runs natively on the build host and cross-publishes a
# self-contained binary for the target arch, so no QEMU is needed for buildx.
FROM --platform=$BUILDPLATFORM mcr.microsoft.com/dotnet/sdk:10.0 AS build

ARG TARGETARCH
ARG RADARRVERSION=""
ARG BRANCH="local"
ARG NODE_MAJOR=24

ENV DOTNET_CLI_TELEMETRY_OPTOUT=1 \
    DOTNET_NOLOGO=1 \
    RADARRVERSION=${RADARRVERSION} \
    BUILD_SOURCEBRANCHNAME=${BRANCH}

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl gnupg \
 && curl -fsSL https://deb.nodesource.com/setup_${NODE_MAJOR}.x | bash - \
 && apt-get install -y --no-install-recommends nodejs \
 && corepack enable \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /src
COPY . .

RUN case "${TARGETARCH}" in \
      amd64) RID=linux-musl-x64 ;; \
      arm64) RID=linux-musl-arm64 ;; \
      arm)   RID=linux-musl-arm ;; \
      *) echo "unsupported TARGETARCH ${TARGETARCH}" >&2; exit 1 ;; \
    esac \
 && ./build.sh --backend --frontend --packages -r "${RID}" -f net10.0 \
 && mv "_artifacts/${RID}/net10.0/Radarr" /out


FROM alpine:3.22

ARG RADARRVERSION=""

RUN apk add --no-cache ca-certificates icu-libs libstdc++ libgcc sqlite-libs tzdata \
 && addgroup -g 1000 radarr \
 && adduser -u 1000 -G radarr -h /config -H -D -s /sbin/nologin radarr \
 && mkdir -p /config \
 && chown radarr:radarr /config

COPY --from=build --chown=root:root /out /app/bin

# Radarr reads ../package_info relative to its binary. UpdateMethod=docker
# disables the in-app updater, matching the linuxserver image.
RUN printf 'UpdateMethod=docker\nPackageVersion=%s\nPackageAuthor=atoy3731\n' "${RADARRVERSION:-local}" > /app/package_info

ENV XDG_CONFIG_HOME=/config \
    TZ=Etc/UTC

USER 1000:1000
VOLUME /config
EXPOSE 7878

ENTRYPOINT ["/app/bin/Radarr", "-nobrowser", "-data=/config"]
