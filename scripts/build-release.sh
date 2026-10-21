#!/bin/bash
# Compila tria como binario universal (arm64 + x86_64) en dist/tria.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --arch arm64 --arch x86_64
mkdir -p dist
# La ruta del binario universal cambia entre toolchains: se pregunta a SwiftPM.
cp "$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/tria" dist/tria
lipo -archs dist/tria
dist/tria --version
