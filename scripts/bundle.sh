#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
swift build -c debug
app=".build/CodexGUI.app"
mkdir -p "$app/Contents/MacOS"
cp .build/debug/CodexGUI "$app/Contents/MacOS/CodexGUI"
cp Resources/Info.plist "$app/Contents/Info.plist"
codesign --force --sign - "$app"
print "Built $app"
