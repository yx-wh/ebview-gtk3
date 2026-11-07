#!/bin/sh
# One-shot build for EBView (GTK3 port).
set -eu

cd "$(dirname "$0")"
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release "$@"
cmake --build build --parallel "$(nproc)"

echo
echo "Build finished: build/ebview, build/ebdump"
echo "This port still looks up its data under the configured install prefix,"
echo "so install before running (or point the prefix at a writable tree):"
echo "  sudo cmake --install build && ebview"
