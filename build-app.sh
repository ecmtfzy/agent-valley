#!/bin/bash
# Builds AgentValley.app, a double-clickable bundle with no Dock icon, in build/ or in the
# folder named first (Homebrew's formula names its own).
set -euo pipefail
cd "$(dirname "$0")"
DEST="${1:-build}"

# Since the macOS 27 SDK, SwiftUI's @State is a macro, and the plugin that expands it comes with
# Xcode, not with the Command Line Tools. Without it, build against the newest older SDK at hand.
SDK="${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}"
if [ ! -e "$SDK/../../usr/lib/swift/host/plugins/libSwiftUIMacros.dylib" ]; then
    shopt -s nullglob
    # In name order, MacOSX26.sdk (the link to the newest 26) comes after MacOSX26.5.sdk.
    for older in "$SDK"/../MacOSX1[0-9]*.sdk "$SDK"/../MacOSX2[0-6]*.sdk; do export SDKROOT="$older"; done
    shopt -u nullglob
fi

# Homebrew builds inside a sandbox of its own, and macOS will not start SwiftPM's inside it.
# The package has no dependencies or plugins for SwiftPM's sandbox to hold in.
swift build -c release --disable-sandbox

APP="$DEST/AgentValley.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/AgentValley "$APP/Contents/MacOS/AgentValley"

# The Claude Code plugin the person installs themselves, from the path the settings view shows.
mkdir -p "$APP/Contents/Resources"
cp -R plugin "$APP/Contents/Resources/claude-plugin"
# The icon Finder shows; testing/site.sh icon makes it from the website's crew mark.
cp AppIcon.icns "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>AgentValley</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleIdentifier</key>
	<string>com.morsechimwai.agent-valley</string>
	<key>CFBundleName</key>
	<string>AgentValley</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>0.1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>15.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSAppleEventsUsageDescription</key>
	<string>Shows the tab of the session you clicked, in your terminal.</string>
</dict>
</plist>
PLIST

# The person can give this app leave to tell a terminal what to do, and it reads their Claude
# Code login when they turn Plan limits on. Signed with the hardened runtime, no other program
# can load code into its process and borrow either. That runtime in turn wants the request to
# tell another app what to do named here.
ENTITLEMENTS=".build/entitlements.plist"
cat > "$ENTITLEMENTS" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.automation.apple-events</key>
	<true/>
</dict>
</plist>
PLIST

codesign --force --options runtime --entitlements "$ENTITLEMENTS" --sign - "$APP"
echo "Built $APP"
