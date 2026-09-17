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

logo_file="$project_root/Sources/Multispace/Resources/app-logo.png"
icns_file="$project_root/Sources/Multispace/Resources/AppIcon.icns"
if [[ -f "$logo_file" ]]; then
  if [[ ! -f "$icns_file" || "$logo_file" -nt "$icns_file" ]]; then
    echo "Generating AppIcon.icns from app-logo.png..."
    iconset_dir=$(mktemp -d /tmp/pinggo_icon.XXXXXX.iconset)
    sips -z 16 16     "$logo_file" --out "$iconset_dir/icon_16x16.png" > /dev/null
    sips -z 32 32     "$logo_file" --out "$iconset_dir/icon_16x16@2x.png" > /dev/null
    sips -z 32 32     "$logo_file" --out "$iconset_dir/icon_32x32.png" > /dev/null
    sips -z 64 64     "$logo_file" --out "$iconset_dir/icon_32x32@2x.png" > /dev/null
    sips -z 128 128   "$logo_file" --out "$iconset_dir/icon_128x128.png" > /dev/null
    sips -z 256 256   "$logo_file" --out "$iconset_dir/icon_128x128@2x.png" > /dev/null
    sips -z 256 256   "$logo_file" --out "$iconset_dir/icon_256x256.png" > /dev/null
    sips -z 512 512   "$logo_file" --out "$iconset_dir/icon_256x256@2x.png" > /dev/null
    sips -z 512 512   "$logo_file" --out "$iconset_dir/icon_512x512.png" > /dev/null
    sips -z 1024 1024 "$logo_file" --out "$iconset_dir/icon_512x512@2x.png" > /dev/null
    iconutil -c icns "$iconset_dir" -o "$icns_file"
    rm -rf "$iconset_dir"
  fi
fi

app_path="$project_root/dist/PINGGO.app"
rm -rf "$app_path"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"

# Locate the compiled binary
bin_source=""
for candidate in "$project_root/.build/out/Products/Debug/PINGGO" "$project_root/.build/arm64-apple-macosx/debug/PINGGO" "$project_root/.build/debug/PINGGO"; do
  if [[ -f "$candidate" ]]; then
    bin_source="$candidate"
    break
  fi
done

if [[ -z "$bin_source" ]]; then
  echo "Error: PINGGO binary not found in build directory" >&2
  exit 1
fi

cp "$bin_source" "$app_path/Contents/MacOS/PINGGO"

# Locate and copy resource bundle
for bundle in "$project_root/.build/out/Products/Debug/"*.bundle(N) "$project_root/.build/arm64-apple-macosx/debug/"*.bundle(N); do
  if [[ -d "$bundle" ]]; then
    cp -R "$bundle" "$app_path/Contents/Resources/"
  fi
done

if [[ -f "$icns_file" ]]; then
  cp "$icns_file" "$app_path/Contents/Resources/AppIcon.icns"
fi
cat > "$app_path/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleExecutable</key><string>PINGGO</string>
    <key>CFBundleIdentifier</key><string>app.pinggo.desktop</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>PINGGO</string>
    <key>CFBundleDisplayName</key><string>PINGGO</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIconName</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSMicrophoneUsageDescription</key><string>PINGGO requires microphone access for audio calls and voice notes in web portals.</string>
    <key>NSCameraUsageDescription</key><string>PINGGO requires camera access for video calls in web portals.</string>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key><string>app.pinggo.desktop</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>pinggo</string>
                <string>multispace</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
PLIST
entitlements_file="$project_root/Sources/Multispace/Resources/Multispace.entitlements"
if [[ -f "$entitlements_file" ]]; then
  codesign --force --deep --sign - --entitlements "$entitlements_file" "$app_path"
else
  codesign --force --deep --sign - "$app_path"
fi

# Backward-compatible symlink so any references to Multispace.app continue working
rm -rf "$project_root/dist/Multispace.app"
ln -s "PINGGO.app" "$project_root/dist/Multispace.app"

echo "Built $app_path"
