#!/bin/bash
# Copyright (c) The Dijets Core Contributors
# SPDX-License-Identifier: Apache-2.0
set -e

#either release or test
if [ -z "$IMAGE_TARGETS" ]; then
  IMAGE_TARGETS="all"
fi

# This is a common compilation scripts across different docker file
# It unifies RUSFLAGS, compilation flags (like --release) and set of binary crates to compile in common docker layer

export RUSTFLAGS="-Ctarget-cpu=skylake -Ctarget-feature=+aes,+sse2,+sse4.1,+ssse3"

# We are using a pinned nightly cargo until feature resolver v2 is released (around 10/2020), but compiling with stable rustc
export CARGO_PROFILE_RELEASE_LTO=thin # override lto setting to turn on thin-LTO for release builds

# Disable the workspace-hack package to prevent extra features and packages from being enabled.
# Can't use ${CARGO} because of https://github.com/rust-lang/rustup/issues/2647 and
# https://github.com/env-logger-rs/env_logger/issues/190.
# TODO: consider using ${CARGO} once upstream issues are fixed.
cargo x generate-workspace-hack --mode disable

if [ "$IMAGE_TARGETS" = "release" ] || [ "$IMAGE_TARGETS" = "all" ]; then
  # Build release binaries (TODO: use x to run this?)
  cargo build --release \
          -p dijets-genesis-tool \
          -p dijets-operational-tool \
          -p dijets-node \
          -p dijets-key-manager \
          -p safety-rules \
          -p db-bootstrapper \
          -p backup-cli \
          -p dijets-transaction-replay \
          -p dijets-writeset-generator \
          "$@"

  # Build and overwrite the dijets-node binary with feature failpoints if $ENABLE_FAILPOINTS is configured
  if [ "$ENABLE_FAILPOINTS" = "1" ]; then
    echo "Building dijets-node with failpoints feature"
    (cd dijets-node && cargo build --release --features failpoints "$@")
  fi
fi


if [ "$IMAGE_TARGETS" = "test" ] || [ "$IMAGE_TARGETS" = "all"  ]; then
  # These non-release binaries are built separately to avoid feature unification issues
  cargo build --release \
          -p cluster-test \
          -p cli \
          -p dijets-faucet \
          -p forge-cli \
          "$@"
fi

rm -rf target/release/{build,deps,incremental}

STRIP_DIR=${STRIP_DIR:-/dijets/target}
find "$STRIP_DIR/release" -maxdepth 1 -executable -type f | grep -Ev 'dijets-node|safety-rules' | xargs strip
