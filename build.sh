#!/bin/bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")" && pwd)"
TASK_BUILD="$TASK_ROOT/.build"
TASK_APP="$TASK_ROOT/dist/留白.app"
mkdir -p "$TASK_BUILD/ModuleCache" "$TASK_APP/Contents/MacOS" "$TASK_APP/Contents/Resources"
export CLANG_MODULE_CACHE_PATH="$TASK_BUILD/ModuleCache"
if [[ "${1:-}" == "--test" ]]; then
    xcrun swiftc -swift-version 6 -target arm64-apple-macos14.0 \
        -module-cache-path "$TASK_BUILD/ModuleCache" \
        -D EYE_REST_TESTING -g \
        "$TASK_ROOT"/Sources/*.swift "$TASK_ROOT/Tests/SmokeTests.swift" \
        -o "$TASK_BUILD/EyeRestSmoke"
    "$TASK_BUILD/EyeRestSmoke"
else
    xcrun swiftc -swift-version 6 -target arm64-apple-macos14.0 \
        -module-cache-path "$TASK_BUILD/ModuleCache" -O \
        "$TASK_ROOT"/Sources/*.swift -o "$TASK_APP/Contents/MacOS/EyeRest"
    cp "$TASK_ROOT/Info.plist" "$TASK_APP/Contents/Info.plist"
    codesign --force --sign - "$TASK_APP"
    printf 'Built: %s\n' "$TASK_APP"
fi
