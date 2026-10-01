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
mkdir -p "$app/Contents/Resources"
cp ".build/$configuration/CodexGUI" "$app/Contents/MacOS/CodexGUI"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Sources/CodexGUI/Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
for resource_bundle in .build/$configuration/*.bundle(N); do
  ditto "$resource_bundle" "$app/Contents/Resources/${resource_bundle:t}"
done
codesign --force --sign - "$app"
print "Built $app ($configuration)"
