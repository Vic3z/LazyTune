#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

SDK="$(xcrun --show-sdk-path)"
BUILD_DIR="$ROOT_DIR/.build_direct"
MODULES_DIR="$BUILD_DIR/modules"
STAGED_DIR="$BUILD_DIR/staged_sources"
APP_BUNDLE="$ROOT_DIR/build/LazyTune.app"

mkdir -p "$MODULES_DIR" "$STAGED_DIR" "$ROOT_DIR/build"

echo "==> [1/5] Ensuring dependency modules (FluidMenuBarExtra & KeyboardShortcuts)..."
if [ ! -f "$MODULES_DIR/libFluidMenuBarExtra.dylib" ]; then
    xcrun swiftc -emit-library -emit-module \
        -module-name FluidMenuBarExtra \
        -target arm64-apple-macos14.0 \
        -sdk "$SDK" \
        -O \
        -Xlinker -install_name -Xlinker @rpath/libFluidMenuBarExtra.dylib \
        -emit-module-path "$MODULES_DIR/FluidMenuBarExtra.swiftmodule" \
        -o "$MODULES_DIR/libFluidMenuBarExtra.dylib" \
        $(find "$ROOT_DIR/.deps/FluidMenuBarExtra/Sources/FluidMenuBarExtra" -name "*.swift")
fi

if [ ! -f "$MODULES_DIR/libKeyboardShortcuts.dylib" ]; then
    xcrun swiftc -emit-library -emit-module \
        -module-name KeyboardShortcuts \
        -target arm64-apple-macos14.0 \
        -sdk "$SDK" \
        -O \
        -Xlinker -install_name -Xlinker @rpath/libKeyboardShortcuts.dylib \
        -emit-module-path "$MODULES_DIR/KeyboardShortcuts.swiftmodule" \
        -o "$MODULES_DIR/libKeyboardShortcuts.dylib" \
        $(find "$ROOT_DIR/.deps/KeyboardShortcuts/Sources/KeyboardShortcuts" -name "*.swift") \
        "$ROOT_DIR/.deps/KeyboardShortcuts_BundleAccessor.swift"
fi

echo "==> [2/5] Staging Swift sources for CommandLineTools swiftc..."
rm -rf "$STAGED_DIR"
mkdir -p "$STAGED_DIR"

python3 - "$ROOT_DIR/FineTune" "$STAGED_DIR" <<'PY'
import os, sys

src_root = sys.argv[1]
dst_root = sys.argv[2]

def strip_previews(code: str) -> str:
    idx = 0
    out = []
    n = len(code)
    while idx < n:
        pos = code.find("#Preview", idx)
        if pos == -1:
            out.append(code[idx:])
            break
        out.append(code[idx:pos])
        brace_start = code.find("{", pos)
        if brace_start == -1:
            break
        depth = 0
        i = brace_start
        in_str = False
        escape = False
        while i < n:
            ch = code[i]
            if escape:
                escape = False
            elif ch == "\\":
                escape = True
            elif ch == '"':
                in_str = not in_str
            elif not in_str:
                if ch == "{":
                    depth += 1
                elif ch == "}":
                    depth -= 1
                    if depth == 0:
                        i += 1
                        break
            i += 1
        idx = i
    return "".join(out)

for root, _, files in os.walk(src_root):
    for f in files:
        if not f.endswith(".swift"):
            continue
        full = os.path.join(root, f)
        rel = os.path.relpath(full, src_root)
        dest = os.path.join(dst_root, rel)
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        with open(full, "r", encoding="utf-8") as fh:
            content = fh.read()
        cleaned = strip_previews(content)
        with open(dest, "w", encoding="utf-8") as fh:
            fh.write(cleaned)
PY

echo "==> [3/5] Compiling unified LazyTune (LazyTune) binary..."

xcrun swiftc \
    -target arm64-apple-macos15.4 \
    -sdk "$SDK" \
    -O -whole-module-optimization \
    -swift-version 6 \
    -D ENABLE_TCC_SPI \
    -enable-upcoming-feature InferIsolatedConformances \
    -enable-upcoming-feature NonisolatedNonsendingByDefault \
    -enable-upcoming-feature MemberImportVisibility \
    -I "$MODULES_DIR" \
    -L "$MODULES_DIR" \
    -lFluidMenuBarExtra \
    -lKeyboardShortcuts \
    -framework AppKit \
    -framework SwiftUI \
    -framework AudioToolbox \
    -framework CoreAudio \
    -framework Accelerate \
    -framework CoreGraphics \
    -framework IOKit \
    -framework IOBluetooth \
    -framework ServiceManagement \
    -framework UserNotifications \
    -framework UniformTypeIdentifiers \
    -framework Carbon \
    -framework MediaPlayer \
    -F /System/Library/PrivateFrameworks \
    -framework TCC \
    -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
    -o "$BUILD_DIR/LazyTune" \
    $(find "$STAGED_DIR" -name "*.swift" | sort)

echo "==> [4/5] Assembling LazyTune.app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Frameworks"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/LazyTune" "$APP_BUNDLE/Contents/MacOS/LazyTune"
chmod +x "$APP_BUNDLE/Contents/MacOS/LazyTune"

cp "$MODULES_DIR/libFluidMenuBarExtra.dylib" "$APP_BUNDLE/Contents/Frameworks/"
cp "$MODULES_DIR/libKeyboardShortcuts.dylib" "$APP_BUNDLE/Contents/Frameworks/"

mkdir -p "$APP_BUNDLE/Contents/Resources/KeyboardShortcuts_KeyboardShortcuts.bundle"
cp -R "$ROOT_DIR/.deps/KeyboardShortcuts/Sources/KeyboardShortcuts/Resources/"* \
    "$APP_BUNDLE/Contents/Resources/KeyboardShortcuts_KeyboardShortcuts.bundle/" 2>/dev/null || true

cp "$ROOT_DIR/FineTune/Resources/MediaStrategies.json" "$APP_BUNDLE/Contents/Resources/MediaStrategies.json"
cp "$ROOT_DIR/FineTune/Assets.xcassets/MenuBarIcon.imageset/MenuBarIcon.pdf" "$APP_BUNDLE/Contents/Resources/MenuBarIcon.pdf"

ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"
cp "$ROOT_DIR/FineTune/Assets.xcassets/fineTuneIcon.appiconset/icon_"*.png "$ICONSET_DIR/"
iconutil -c icns "$ICONSET_DIR" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

cat > "$APP_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>LazyTune</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleIconName</key>
	<string>AppIcon</string>
	<key>CFBundleIdentifier</key>
	<string>com.finetuneapp.FineTune</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>LazyTune</string>
	<key>CFBundleDisplayName</key>
	<string>Lazy Tune</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>2.0.0-LazyTune</string>
	<key>CFBundleVersion</key>
	<string>210</string>
	<key>LSMinimumSystemVersion</key>
	<string>15.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSAudioCaptureUsageDescription</key>
	<string>LazyTune needs access to control volume levels for individual applications.</string>
	<key>NSMicrophoneUsageDescription</key>
	<string>LazyTune needs microphone access to capture audio from apps using input-capable devices.</string>
	<key>NSBluetoothAlwaysUsageDescription</key>
	<string>LazyTune uses Bluetooth to connect paired audio devices from the menu bar.</string>
	<key>NSAppleEventsUsageDescription</key>
	<string>LazyTune uses Apple Events to control playback and read track information from web browsers and media players (universal media control).</string>
	<key>CFBundleURLTypes</key>
	<array>
		<dict>
			<key>CFBundleURLSchemes</key>
			<array>
				<string>finetune</string>
				<string>lazytune</string>
			</array>
			<key>CFBundleURLName</key>
			<string>com.finetuneapp.FineTune</string>
		</dict>
	</array>
</dict>
</plist>
PLIST

echo "==> [5/5] Codesigning LazyTune.app..."
codesign --force --deep --sign - --entitlements "$ROOT_DIR/FineTune/FineTune.entitlements" "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"

echo "==> Build succeeded! Bundle created at: $APP_BUNDLE"
