#!/bin/bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")" && pwd)"
TASK_BUILD="$TASK_ROOT/.build"
TASK_APP="$TASK_ROOT/dist/EyeFriend.app"
mkdir -p "$TASK_BUILD/ModuleCache" "$TASK_APP/Contents/MacOS" "$TASK_APP/Contents/Resources"
export CLANG_MODULE_CACHE_PATH="$TASK_BUILD/ModuleCache"
if [[ "${1:-}" == "--test" || "${1:-}" == "--compile-tests" ]]; then
    xcrun swiftc -swift-version 6 -target arm64-apple-macos14.0 \
        -module-cache-path "$TASK_BUILD/ModuleCache" \
        -D EYE_REST_TESTING -g \
        "$TASK_ROOT"/Sources/*.swift "$TASK_ROOT"/Tests/*.swift \
        -o "$TASK_BUILD/EyeRestSmoke"
    if [[ "${1:-}" == "--test" ]]; then "$TASK_BUILD/EyeRestSmoke"; fi
else
    xcrun swiftc -swift-version 6 -target arm64-apple-macos14.0 \
        -module-cache-path "$TASK_BUILD/ModuleCache" -O \
        "$TASK_ROOT"/Sources/*.swift -o "$TASK_APP/Contents/MacOS/EyeFriend"
    cp "$TASK_ROOT/Info.plist" "$TASK_APP/Contents/Info.plist"
    cp "$TASK_ROOT"/Resources/*.icns "$TASK_ROOT"/Resources/*.png "$TASK_APP/Contents/Resources/"
    codesign --force --sign - "$TASK_APP"
    printf 'Built: %s\n' "$TASK_APP"
fi
