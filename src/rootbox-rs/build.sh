#!/bin/bash
# Build script for rootbox

set -e

echo "Building rootbox in release mode..."
cargo build --release

echo ""
echo "Build successful!"
echo "Binary location: target/release/rootbox"
echo ""
echo "To install:"
echo "  sudo install -m 755 target/release/rootbox /usr/local/bin/"
echo "  or"
echo "  install -m 755 target/release/rootbox ~/.local/bin/"
echo ""
echo "To test:"
echo "  ./target/release/rootbox --help"
