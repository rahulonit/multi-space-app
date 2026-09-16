#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
cd "$project_root"

mkdir -p .cache/clang .cache/swiftpm dist
export CLANG_MODULE_CACHE_PATH="$project_root/.cache/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$project_root/.cache/swiftpm"

build_args=(--disable-sandbox --scratch-path .build)
if [[ -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk && ! -d /Applications/Xcode.app ]]; then
  build_args+=(--sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk)
fi

swift build "${build_args[@]}"

app_path="$project_root/dist/Multispace.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$project_root/.build/out/Products/Debug/Multispace" "$app_path/Contents/MacOS/Multispace"
cp -R "$project_root/.build/out/Products/Debug/Multispace_Multispace.bundle" "$app_path/Contents/Resources/"
cat > "$app_path/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleExecutable</key><string>Multispace</string>
    <key>CFBundleIdentifier</key><string>app.multispace.desktop</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>Multispace</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSMicrophoneUsageDescription</key><string>Multispace requires microphone access for audio calls and voice notes in web portals.</string>
    <key>NSCameraUsageDescription</key><string>Multispace requires camera access for video calls in web portals.</string>
</dict>
</plist>
PLIST
codesign --force --deep --sign - "$app_path"
echo "Built $app_path"
