#!/usr/bin/env bash

set -e

ARGS=("$@")

# Use exported ARCHS if set, otherwise default to common architectures
ARCHS=${ARCHS:-"amd64 arm64 i386 armhf"}

for ARCH in $ARCHS; do
    echo "Building for architecture: $ARCH"
    DISTRO_ARCH="$ARCH" "${ARGS[@]}"
done
