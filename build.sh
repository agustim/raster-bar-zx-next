#!/usr/bin/env bash
# Build the raster-bar .nex for the ZX Spectrum Next.
#
# If the sjasmplus binary is not present (it is git-ignored), this script
# compiles it from source first so the build works from a clean checkout.
#
# Requires: python3, make, g++ (for building sjasmplus from source if needed)
#
# Output: src/build/rasterbar.nex
set -euo pipefail
cd "$(dirname "$0")/src"

mkdir -p build

# Build sjasmplus from source if the binary is missing (CI / clean checkout).
if [ ! -x ./sjasmplus ]; then
  echo "== sjasmplus not found - compiling from source =="
  BUILD_DIR="$(mktemp -d)"
  git clone --depth 1 https://github.com/z00m128/sjasmplus.git "$BUILD_DIR/sjasmplus"
  cd "$BUILD_DIR/sjasmplus"
  git submodule update --init --recursive
  make -j"$(nproc)"
  cp sjasmplus "$OLDPWD/sjasmplus"
  cd "$OLDPWD"
  rm -rf "$BUILD_DIR"
fi

echo "== generating data files =="
python3 gen_gradient.py

echo "== assembling =="
./sjasmplus --sym=build/rasterbar.labels --sld=build/rasterbar.sld --fullpath rasterbar.asm

echo "== done: src/build/rasterbar.nex =="
