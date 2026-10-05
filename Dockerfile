ARG BASE_IMAGE=debian:bullseye-slim

FROM rust:latest as builder

ARG VERSION=master
ARG PROFILE=debug
ARG UPSTREAM=https://github.com/Frodo45127/rpfm.git

WORKDIR /usr/src/app

RUN apt-get update && apt-get install -y --no-install-recommends \
    software-properties-common \
    apt-transport-https \
    git \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN git clone \
      -b ${VERSION} \
      --depth 1 \
      ${UPSTREAM} \
    && cd rpfm \
    && sed -i \
       's/debug\s*=\s*true//gm' \
       Cargo.toml \
    && mkdir /build \
    && cargo build \
       -vv \
       --bin rpfm_cli \
       --target-dir /build \
       $( [ "${PROFILE}" == "release" ] && echo "--${PROFILE}" )

FROM ${BASE_IMAGE}

ARG PROFILE=debug
ARG APP=/app
ARG RUNTIME_DEPS=libssl1.1

ENV APP_USER=rpfm

RUN groupadd ${APP_USER} \
 && useradd -g ${APP_USER} ${APP_USER} \
 && mkdir -p ${APP} \
 && apt-get update \
 && apt-get install -y ${RUNTIME_DEPS} \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

COPY --chown=${APP_USER}:${APP_USER} \
     --from=builder \
     /build/${PROFILE}/rpfm_cli ${APP}/

WORKDIR ${APP}
ENV PATH="${APP}:${PATH}"

ENTRYPOINT ["rpfm_cli"]
