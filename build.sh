#!/bin/bash
set -e
cd "$(dirname "$0")"

# The iOS-Simulator side of the camera feature — see VirtualCamera/.
# Cross-compiled against the iphonesimulator SDK (fat: arm64 + x86_64),
# linker-signed adhoc. Staged into Sources/BaguetteCore/Resources/VirtualCamera/
# so SPM bundles it as a `.copy` resource.
./VirtualCamera/build.sh
mkdir -p Sources/BaguetteCore/Resources/VirtualCamera
cp -f VirtualCamera/VirtualCamera.dylib Sources/BaguetteCore/Resources/VirtualCamera/

# Pure-SPM build. Private frameworks resolve through the rpath flags +
# linkedFramework declarations in Package.swift.
swift build -c release

# Drop the binary at the workspace root so the Makefile / install scripts
# find it where they always have.
cp -f .build/release/Baguette ./Baguette
echo "Build complete: ./Baguette"
