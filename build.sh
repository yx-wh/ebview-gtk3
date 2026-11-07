#!/bin/sh
# One-shot build for EBView (GTK3 port).
set -eu

cd "$(dirname "$0")"
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release "$@"
cmake --build build --parallel "$(nproc)"

echo
echo "Build finished: build/ebview, build/ebdump"
echo "Run without installing (data dir is auto-detected):"
echo "  ./build/ebview"
echo "Or install system-wide:"
echo "  sudo cmake --install build"
