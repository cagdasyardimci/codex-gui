#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
configuration="${1:-debug}"
case "$configuration" in
  debug|release) ;;
  *) print -u2 "Usage: $0 [debug|release]"; exit 2 ;;
esac

configured_identity="${CODEX_GUI_SIGNING_IDENTITY:-}"
signing_identity="-"
if [[ "$configured_identity" != "-" ]]; then
  identity_output=$(security find-identity -v -p codesigning)
  available_identities=$(print -r -- "$identity_output" | sed -nE \
    's/^[[:space:]]*[0-9]+\) ([[:xdigit:]]{40}) "([^"]+)".*/\1\t\2/p')
  if [[ -n "$configured_identity" ]]; then
    matching_identities=$(print -r -- "$available_identities" | awk -F '\t' \
      -v identity="$configured_identity" '$1 == identity || $2 == identity')
  else
    matching_identities=$(print -r -- "$available_identities" | awk -F '\t' \
      '$2 ~ /^Apple Development:/')
  fi
  identity_count=$(print -r -- "$matching_identities" | awk 'NF { count++ } END { print count + 0 }')
  if (( identity_count == 0 )) && [[ -n "$configured_identity" ]]; then
    print -u2 "No valid code-signing identity matches CODEX_GUI_SIGNING_IDENTITY."
    print -u2 "Available identities are listed by: security find-identity -v -p codesigning"
    print -u2 "Set CODEX_GUI_SIGNING_IDENTITY=- to use ad hoc signing without a certificate."
    exit 1
  fi
  if (( identity_count > 1 )); then
    print -u2 "Multiple code-signing identities match the requested selection."
    print -u2 "Set CODEX_GUI_SIGNING_IDENTITY to an exact identity name or SHA-1 hash."
    print -u2 "Available identities are listed by: security find-identity -v -p codesigning"
    print -u2 "Set CODEX_GUI_SIGNING_IDENTITY=- to use ad hoc signing without a certificate."
    exit 1
  fi
  if (( identity_count == 1 )); then
    signing_identity=$(print -r -- "$matching_identities" | awk -F '\t' 'NF { print $1 }')
  fi
fi
if [[ "$signing_identity" == "-" ]]; then
  print "Using ad hoc signing (no Apple Development certificate required)."
else
  print "Using the selected code-signing certificate."
fi

# Swift Build resolves package resources from Contents/Resources in a signed macOS app.
swift build --build-system swiftbuild -c "$configuration"
product_directory=$(swift build --build-system swiftbuild -c "$configuration" --show-bin-path)
app=".build/CodexGUI.app"
mkdir -p "$app/Contents/MacOS"
mkdir -p "$app/Contents/Resources"
cp "$product_directory/CodexGUI" "$app/Contents/MacOS/CodexGUI"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Sources/CodexGUI/Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
for resource_bundle in "$product_directory"/*.bundle(N); do
  resource_destination="$app/Contents/Resources/${resource_bundle:t}"
  rm -rf "$resource_destination"
  ditto "$resource_bundle" "$resource_destination"
done
markdown_licenses="$app/Contents/Resources/ThirdPartyLicenses/swift-markdown"
cmark_licenses="$app/Contents/Resources/ThirdPartyLicenses/swift-cmark"
mkdir -p "$markdown_licenses" "$cmark_licenses"
cp -f .build/checkouts/swift-markdown/LICENSE.txt "$markdown_licenses/LICENSE.txt"
cp -f .build/checkouts/swift-markdown/NOTICE.txt "$markdown_licenses/NOTICE.txt"
cp -f .build/checkouts/swift-cmark/COPYING "$cmark_licenses/COPYING"
highlighter_licenses="$app/Contents/Resources/ThirdPartyLicenses/HighlighterSwift"
math_licenses="$app/Contents/Resources/ThirdPartyLicenses/SwiftMath"
mermaid_licenses="$app/Contents/Resources/ThirdPartyLicenses/swift-mermaid"
mkdir -p "$highlighter_licenses/Sources/Assets" \
  "$math_licenses/Sources/SwiftMath/mathFonts.bundle" \
  "$mermaid_licenses/Vendor/MermaidLayoutDagre"
cp -f .build/checkouts/HighlighterSwift/LICENCE.md "$highlighter_licenses/LICENCE.md"
cp -f .build/checkouts/HighlighterSwift/Sources/Assets/LICENCE \
  "$highlighter_licenses/Sources/Assets/LICENCE"
cp -f .build/checkouts/SwiftMath/LICENSE "$math_licenses/LICENSE"
cp -f .build/checkouts/SwiftMath/Sources/SwiftMath/mathFonts.bundle/LICENSE \
  "$math_licenses/Sources/SwiftMath/mathFonts.bundle/LICENSE"
cp -f .build/checkouts/SwiftMath/Sources/SwiftMath/mathFonts.bundle/GUST-FONT-LICENSE.txt \
  "$math_licenses/Sources/SwiftMath/mathFonts.bundle/GUST-FONT-LICENSE.txt"
cp -f .build/checkouts/swift-mermaid/LICENSE "$mermaid_licenses/LICENSE"
cp -f .build/checkouts/swift-mermaid/THIRD-PARTY-NOTICES.md \
  "$mermaid_licenses/THIRD-PARTY-NOTICES.md"
cp -f .build/checkouts/swift-mermaid/Vendor/MermaidLayoutDagre/LICENSE \
  "$mermaid_licenses/Vendor/MermaidLayoutDagre/LICENSE"
codesign --force --sign "$signing_identity" "$app"
print "Built $app ($configuration)"
