#!/bin/sh
# Copyright (c) The Dijets Core Contributors
# SPDX-License-Identifier: Apache-2.0
set -e

DIR="$( cd "$( dirname "$0" )" && pwd )"

$DIR/../dijets-build.sh $DIR/../validator/Dockerfile dijets/validator "$@"
