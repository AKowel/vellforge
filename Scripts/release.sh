#!/usr/bin/env bash
# Build a release: the zip, its Sparkle signature, and the appcast.
#
#   ./Scripts/release.sh
#
# Publishes nothing. It prints the `gh release create` command to run once
# you're happy. The version is the VERSION file.
#
# Once, before the first release:
#   .build/artifacts/sparkle/Sparkle/bin/generate_keys
# stores the update-signing key in your login keychain and prints the public
# key; put that in Resources/sparkle-public-key.txt and commit it. Keep the
# private key safe: losing it means existing installs can't verify updates.
#
# How updates reach people: the app checks https://vellforge.com/appcast.xml,
# which the site redirects to the newest GitHub release's appcast.xml. So a
# release is just these three files attached to a GitHub release.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="$(tr -d '[:space:]' < VERSION)"
REPO="AKowel/vellforge"
OUT="$ROOT/build/release"
SIGN_UPDATE="$ROOT/.build/artifacts/sparkle/Sparkle/bin/sign_update"

die() { echo "error: $*" >&2; exit 1; }

[[ -f Resources/sparkle-public-key.txt ]] \
  || die "Resources/sparkle-public-key.txt is missing. Run generate_keys first (see the top of this script)."
[[ -z "$(git status --porcelain)" ]] \
  || die "uncommitted changes. A release must match a commit."
git rev-parse "v$VERSION" >/dev/null 2>&1 \
  && die "tag v$VERSION already exists. Bump VERSION first."

[[ -x "$SIGN_UPDATE" ]] || swift package resolve
"$ROOT/Scripts/bundle.sh" --release

APP="$ROOT/build/Vellforge.app"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
ARCHS="$(lipo -archs "$APP/Contents/MacOS/Vellforge")"
[[ "$ARCHS" == *arm64* && "$ARCHS" == *x86_64* ]] || die "not universal: $ARCHS"

rm -rf "$OUT"
mkdir -p "$OUT"
ZIP="Vellforge-$VERSION.zip"
echo "==> Zipping $ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT/$ZIP"
# A stable name too, so the website's download button never needs editing.
cp "$OUT/$ZIP" "$OUT/Vellforge.zip"

echo "==> Signing the update"
# Prints: sparkle:edSignature="…" length="…"
SIGNATURE="$("$SIGN_UPDATE" "$OUT/$ZIP")"
[[ "$SIGNATURE" == *edSignature* ]] || die "sign_update failed: $SIGNATURE"

PUB_DATE="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"
cat > "$OUT/appcast.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Vellforge</title>
    <link>https://vellforge.com</link>
    <description>Updates for Vellforge</description>
    <language>en</language>
    <item>
      <title>Vellforge $VERSION</title>
      <pubDate>$PUB_DATE</pubDate>
      <link>https://github.com/$REPO/releases/tag/v$VERSION</link>
      <sparkle:version>$BUILD_NUMBER</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <description><![CDATA[<p>What's new: <a href="https://github.com/$REPO/releases/tag/v$VERSION">release notes on GitHub</a>.</p>]]></description>
      <enclosure url="https://github.com/$REPO/releases/download/v$VERSION/$ZIP"
                 $SIGNATURE
                 type="application/octet-stream"/>
    </item>
  </channel>
</rss>
XML

echo
echo "Release files in $OUT:"
ls -lh "$OUT" | sed 's/^/    /'
cat <<NEXT

To publish (check the notes first):

  git tag v$VERSION && git push origin main v$VERSION
  gh release create v$VERSION --repo $REPO --title "Vellforge $VERSION" --notes-file <notes.md> \\
      "$OUT/$ZIP" "$OUT/Vellforge.zip" "$OUT/appcast.xml"

Existing installs see it at their next check, through vellforge.com/appcast.xml.
NEXT
