FROM debian:buster-20210816@sha256:e2fe52e17d649812bddcac07faf16f33542129a59b2c1c59b39a436754b7f146 AS toolchain

# To use http/https proxy while building, use:
# docker build --build-arg https_proxy=http://fwdproxy:8080 --build-arg http_proxy=http://fwdproxy:8080

RUN apt-get update && apt-get install -y cmake curl clang git pkg-config libssl-dev

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain none
ENV PATH "$PATH:/root/.cargo/bin"

WORKDIR /dijets
COPY rust-toolchain /dijets/rust-toolchain
RUN rustup install $(cat rust-toolchain)

FROM toolchain AS builder

ARG ENABLE_FAILPOINTS
COPY . /dijets

RUN IMAGE_TARGETS="test" ./docker/build-common.sh

### Pre-Production Image ###
FROM debian:buster-20210816@sha256:e2fe52e17d649812bddcac07faf16f33542129a59b2c1c59b39a436754b7f146 AS pre-prod

RUN apt-get update && apt-get install -y libssl1.1 ca-certificates && apt-get clean && rm -r /var/lib/apt/lists/*

RUN mkdir -p /opt/dijets/bin /opt/dijets/etc
COPY --from=builder /dijets/target/release/cli /opt/dijets/bin/dijets_client

### Test pre-production Image ###
FROM pre-prod as testing

RUN /opt/dijets/bin/dijets_client -h

### Production Image ###
FROM pre-prod AS prod

ENTRYPOINT ["/opt/dijets/bin/dijets_client"]
CMD ["--url", "https://testnet.dijets.com/v1", "--waypoint_url",  "https://testnet.dijets.com/waypoint.txt", "--chain-id", "TESTNET"]

ARG BUILD_DATE
ARG GIT_REV
ARG GIT_UPSTREAM

LABEL org.label-schema.schema-version="1.0"
LABEL org.label-schema.build-date=$BUILD_DATE
LABEL org.label-schema.vcs-ref=$GIT_REV
