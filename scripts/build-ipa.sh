#!/usr/bin/env bash
set -e

# Panovault iOS Sideload Package Builder
# Builds unsigned IPA for AltStore, SideStore, TrollStore, and Sideloadly

echo "⚡ [Panovault iOS] Building release bundle for iOS (No Code Sign)..."
flutter build ios --no-codesign --release

OUTPUT_DIR="build/ios/ipa"
PAYLOAD_DIR="$OUTPUT_DIR/Payload"

echo "📦 [Panovault iOS] Packaging into IPA payload structure..."
rm -rf "$OUTPUT_DIR"
mkdir -p "$PAYLOAD_DIR"

# Copy compiled Runner.app into Payload
cp -r "build/ios/iphoneos/Runner.app" "$PAYLOAD_DIR/Panovault.app"

# Create IPA archive
cd "$OUTPUT_DIR"
zip -r -q "Panovault.ipa" "Payload"
rm -rf "Payload"
cd - > /dev/null

echo "✓ [Panovault iOS] Successfully created sideloadable IPA at:"
echo "  → $(pwd)/$OUTPUT_DIR/Panovault.ipa"
echo ""
echo "How to install on iOS without App Store:"
echo "  1. AltStore / SideStore: Share Panovault.ipa to AltStore / SideStore app on your device."
echo "  2. TrollStore (iOS 14 - 17.0): Open Panovault.ipa directly in TrollStore."
echo "  3. Sideloadly: Drag Panovault.ipa into Sideloadly on Mac/PC and install via USB/Wi-Fi."
