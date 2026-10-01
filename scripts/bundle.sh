#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
configuration="${1:-debug}"
case "$configuration" in
  debug|release) ;;
  *) print -u2 "Usage: $0 [debug|release]"; exit 2 ;;
esac
swift build -c "$configuration"
app=".build/CodexGUI.app"
mkdir -p "$app/Contents/MacOS"
cp ".build/$configuration/CodexGUI" "$app/Contents/MacOS/CodexGUI"
cp Resources/Info.plist "$app/Contents/Info.plist"
codesign --force --sign - "$app"
print "Built $app ($configuration)"
