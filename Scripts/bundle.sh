#!/usr/bin/env bash
# Assemble Vellforge.app from the SwiftPM build product.
#
#   ./Scripts/bundle.sh              debug build
#   ./Scripts/bundle.sh --release    release build, universal (Apple silicon + Intel)
#   ./Scripts/bundle.sh --reset-tcc  also clear the Accessibility and Screen Recording grants
#
# The version comes from the VERSION file; the build number is the commit count,
# which only ever goes up, and that is what Sparkle compares.
#
# Set VELLFORGE_SIGN_IDENTITY to choose a signing identity. Otherwise one is
# picked from the keychain (see the TCC note at the bottom).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="debug"
RESET_TCC=0
BUNDLE_ID="com.vellund.Vellforge"
APP_NAME="Vellforge"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
BUILD_NUMBER="$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)"
FEED_URL="https://vellforge.com/appcast.xml"
KEY_FILE="$ROOT/Resources/sparkle-public-key.txt"

for arg in "$@"; do
  case "$arg" in
    --release)   CONFIG="release" ;;
    --reset-tcc) RESET_TCC=1 ;;
    *) echo "unknown option: $arg" >&2; exit 1 ;;
  esac
done

# Release builds are universal: an Apple-silicon-only release would strand
# every Intel Mac. macOS ships bash 3.2, where expanding an empty array under
# `set -u` is an error, so the flags are a plain string.
ARCH_FLAGS=""
LABEL="$CONFIG"
if [[ "$CONFIG" == "release" ]]; then
  ARCH_FLAGS="--arch arm64 --arch x86_64"
  LABEL="$CONFIG, universal"
fi

echo "==> Building $APP_NAME $VERSION ($BUILD_NUMBER, $LABEL)"
# Unquoted on purpose: these are separate arguments, not one.
swift build -c "$CONFIG" --package-path "$ROOT" $ARCH_FLAGS
BIN_DIR="$(swift build -c "$CONFIG" --package-path "$ROOT" $ARCH_FLAGS --show-bin-path)"

APP="$ROOT/build/$APP_NAME.app"
echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"

# Sparkle. ditto keeps the framework's symlinks intact, which codesign needs.
SPARKLE="$BIN_DIR/Sparkle.framework"
[[ -d "$SPARKLE" ]] || SPARKLE="$ROOT/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
ditto "$SPARKLE" "$APP/Contents/Frameworks/Sparkle.framework"
# The XPC services are only for sandboxed apps. Vellforge isn't sandboxed
# (it can't be: it moves other apps' windows), so they are dead weight.
rm -rf "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices" \
       "$APP/Contents/Frameworks/Sparkle.framework/XPCServices"

# The executable looks for Sparkle next to itself in the build folder; in the
# bundle it lives in Contents/Frameworks.
if ! otool -l "$APP/Contents/MacOS/$APP_NAME" | grep -q "@executable_path/../Frameworks"; then
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/$APP_NAME"
fi

if [[ -f "$ROOT/Resources/$APP_NAME.icns" ]]; then
  cp "$ROOT/Resources/$APP_NAME.icns" "$APP/Contents/Resources/"
else
  echo "    no icon found: run swift Scripts/make-icon.swift"
fi

# Sparkle verifies every update against this public key. Without it the
# updater stays off, which is right for a local build.
PUBLIC_KEY=""
if [[ -f "$KEY_FILE" ]]; then
  PUBLIC_KEY="$(tr -d '[:space:]' < "$KEY_FILE")"
else
  echo "    no Resources/sparkle-public-key.txt: updates are off in this build"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>                 <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>          <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>           <string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key>           <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>          <string>APPL</string>
    <key>CFBundleShortVersionString</key>   <string>$VERSION</string>
    <key>CFBundleVersion</key>              <string>$BUILD_NUMBER</string>
    <key>CFBundleIconFile</key>             <string>$APP_NAME</string>
    <key>LSMinimumSystemVersion</key>       <string>14.0</string>
    <!-- Menu bar agent: no Dock icon, no app switcher entry. -->
    <key>LSUIElement</key>                  <true/>
    <key>NSHumanReadableCopyright</key>     <string>© Vellund. MIT licence.</string>
    <key>SUFeedURL</key>                    <string>$FEED_URL</string>
    <key>SUPublicEDKey</key>                <string>$PUBLIC_KEY</string>
    <!-- Sparkle only ever fetches the feed. Never send a system profile. -->
    <key>SUEnableSystemProfiling</key>      <false/>
</dict>
</plist>
PLIST

# Pick a signing identity. A real certificate matters more than it sounds: it
# makes the *designated requirement* certificate-based rather than hash-based,
# so the Accessibility grant survives every rebuild and every update.
IDENTITY="${VELLFORGE_SIGN_IDENTITY:-${VELLSNAP_SIGN_IDENTITY:-}}"
if [[ -z "$IDENTITY" ]]; then
  for pattern in "Developer ID Application" "Apple Development" "Mac Developer"; do
    # `|| true`: under `set -e` + `pipefail`, a grep that finds nothing would
    # abort the script rather than trying the next pattern.
    found=$(security find-identity -v -p codesigning 2>/dev/null \
            | grep -m1 "$pattern" | sed -E 's/.*"(.*)".*/\1/' || true)
    if [[ -n "$found" ]]; then
      IDENTITY="$found"
      echo "==> Auto-selected signing identity: $IDENTITY"
      break
    fi
  done
fi

# Inside out: Sparkle's helpers, then the framework, then the app.
FW="$APP/Contents/Frameworks/Sparkle.framework"
NESTED=("$FW/Versions/B/Autoupdate" "$FW/Versions/B/Updater.app" "$FW")

echo "==> Signing"
if [[ -n "$IDENTITY" ]]; then
  TIMESTAMP="--timestamp=none"
  [[ "$CONFIG" == "release" ]] && TIMESTAMP="--timestamp"
  for item in "${NESTED[@]}"; do
    codesign --force --options runtime $TIMESTAMP --sign "$IDENTITY" "$item"
  done
  codesign --force --options runtime $TIMESTAMP --sign "$IDENTITY" "$APP"
  echo "    signed as: $IDENTITY"
else
  for item in "${NESTED[@]}"; do codesign --force --sign - "$item"; done
  codesign --force --sign - "$APP"
  echo "    ad-hoc signed (see TCC note below)"
fi
codesign --verify --deep --strict "$APP"

if [[ $RESET_TCC -eq 1 ]]; then
  echo "==> Resetting permission grants for $BUNDLE_ID"
  tccutil reset Accessibility "$BUNDLE_ID" || true
  tccutil reset ScreenCapture "$BUNDLE_ID" || true
fi

echo
echo "Built: $APP"
echo "    version:       $VERSION ($BUILD_NUMBER)"
echo "    architectures: $(lipo -archs "$APP/Contents/MacOS/$APP_NAME")"
codesign -dv "$APP" 2>&1 | grep -E "Identifier|Authority=|TeamIdentifier|Runtime" | sed 's/^/    /'

cat <<'NOTE'

TCC note
--------
macOS identifies an app for permissions by its code signature. Signed with a
real certificate, the designated requirement is certificate-based, so the
Accessibility grant survives rebuilds and updates and you only grant it once.

Ad-hoc signed (no identity found), every rebuild looks like a new app and the
grant silently stops working: windows refuse to move, scrolling isn't flipped,
with no error. Either install an Apple Development certificate (Xcode >
Settings > Accounts), or re-grant each time with ./Scripts/bundle.sh --reset-tcc
NOTE
