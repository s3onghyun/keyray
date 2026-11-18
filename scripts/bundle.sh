#!/bin/sh
# Build build/CursorProto.app: release binary, Info.plist (LSUIElement menu-bar app), App Sandbox
# entitlement only, signed with the Hardened Runtime (--options runtime) so both are really active.
#
#   SIGN_IDENTITY      codesign identity (default "-", ad hoc)
#   BUNDLE_IDENTIFIER  bundle id (default com.s3onghyun.cursor-proto; codename until there is a name)
#   ARCHS              arm64 (default), x86_64 or universal
#   SWIFT_BUILD_FLAGS  extra `swift build` flags, e.g. "--build-system native"
#
# With Command Line Tools 27.2 and no Xcode:
#   SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk SWIFT_BUILD_FLAGS="--build-system native" scripts/bundle.sh
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
version=$(tr -d '\r\n' < "$root/VERSION")
build=$(git -C "$root" rev-list --count HEAD 2>/dev/null || echo 1)
bundle_identifier=${BUNDLE_IDENTIFIER:-com.s3onghyun.cursor-proto}
sign_identity=${SIGN_IDENTITY:--}
out="$root/build"
app="$out/CursorProto.app"

case ${ARCHS:-arm64} in
  universal) architectures="arm64 x86_64" ;;
  arm64|x86_64) architectures=${ARCHS:-arm64} ;;
  *) echo "ARCHS must be arm64, x86_64, or universal" >&2; exit 2 ;;
esac

bins=""
for architecture in $architectures; do
  scratch="$root/.build/$architecture-release"
  swift build --package-path "$root" --scratch-path "$scratch" -c release \
    --triple "$architecture-apple-macosx14.0" --product CursorProto ${SWIFT_BUILD_FLAGS:-}
  bin_path=$(swift build --package-path "$root" --scratch-path "$scratch" -c release \
    --triple "$architecture-apple-macosx14.0" --show-bin-path ${SWIFT_BUILD_FLAGS:-})
  bins="$bins $bin_path/CursorProto"
done

set -- $bins
mkdir -p "$out"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
if [ "$#" -eq 1 ]; then
  cp "$1" "$app/Contents/MacOS/CursorProto"
else
  lipo -create "$@" -output "$app/Contents/MacOS/CursorProto"
fi

sdk=${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}
sdk_version=$(plutil -extract ProductVersion raw "$sdk/System/Library/CoreServices/SystemVersion.plist")
sdk_build=$(plutil -extract ProductBuildVersion raw "$sdk/System/Library/CoreServices/SystemVersion.plist")

cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>$bundle_identifier</string>
  <key>CFBundleName</key><string>CursorProto</string>
  <key>CFBundleDisplayName</key><string>CursorProto</string>
  <key>CFBundleExecutable</key><string>CursorProto</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>CFBundleVersion</key><string>$build</string>
  <key>CFBundleSupportedPlatforms</key><array><string>MacOSX</string></array>
  <key>DTPlatformName</key><string>macosx</string>
  <key>DTPlatformVersion</key><string>$sdk_version</string>
  <key>DTSDKName</key><string>macosx$sdk_version</string>
  <key>DTSDKBuild</key><string>$sdk_build</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
plutil -lint "$app/Contents/Info.plist" >/dev/null

xattr -cr "$app"
codesign --force --timestamp=none --options runtime --sign "$sign_identity" \
  --entitlements "$root/Resources/CursorProto.entitlements" "$app"
codesign --verify --strict "$app"
printf '%s\n' "$app"
