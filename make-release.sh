#!/bin/bash
# Builds Nox and packs it into release/Nox.dmg, ready to attach to a GitHub release.
# The disk image holds the app, a shortcut to Applications (drag to install) and first-open help.
set -euo pipefail
cd "$(dirname "$0")"
xcodegen -q
xcodebuild -scheme DarkSwitch -configuration Release -derivedDataPath /tmp/dsbuild build | grep -E "error:|BUILD (SUCCEEDED|FAILED)"

STAGE=$(mktemp -d)
cp -R /tmp/dsbuild/Build/Products/Release/DarkSwitch.app "$STAGE/Nox.app"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/Read me first.txt" <<'TXT'
Installing Nox

1. Drag Nox into the Applications folder.
2. Open Applications, right-click Nox and choose Open, then Open again.
   (macOS asks this once because the app is not from the App Store. If it still refuses,
   go to System Settings > Privacy & Security and click "Open Anyway".)
3. A welcome window opens. Click each button and press Allow on Apple's windows:
   - Switch dark mode (lets Nox change light/dark)
   - Dark websites in Safari (opens Safari's extension settings)
   - Smooth fade (optional, needs Screen Recording)
4. Nox lives in the menu bar: click the switch to flip dark mode,
   right-click it (or Option-click) for options.
TXT
mkdir -p release
rm -f release/Nox.dmg
hdiutil create -quiet -volname "Nox" -srcfolder "$STAGE" -fs HFS+ -format UDZO release/Nox.dmg
rm -rf "$STAGE"
# The build folder copy got registered with macOS when it was built; forget it, or Safari lists
# it as an extra "Nox" extension. (Only unregisters; nothing is deleted.)
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
BUILT=/tmp/dsbuild/Build/Products/Release/DarkSwitch.app
pluginkit -r "$BUILT/Contents/PlugIns/DarkSwitchExtension.appex" 2>/dev/null || true
"$LSREGISTER" -u "$BUILT/Contents/PlugIns/DarkSwitchExtension.appex" 2>/dev/null || true
"$LSREGISTER" -u "$BUILT" 2>/dev/null || true
echo "Made $(pwd)/release/Nox.dmg"
