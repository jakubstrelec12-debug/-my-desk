#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "MY DESK vyžaduje pro sestavení macOS 13+ a Xcode 15+." >&2
  exit 1
fi
if ! xcrun --find swift >/dev/null 2>&1; then
  echo "Nainstalujte Xcode a spusťte jej pro dokončení instalace nástrojů." >&2
  exit 1
fi
# No deletion of external paths. All build output is beneath this project.
export MACOSX_DEPLOYMENT_TARGET=13.0
swift test
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="$PWD/dist/MY DESK.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/MyDesk" "$APP/Contents/MacOS/MyDesk"
for resource in "$BIN_DIR"/*.bundle; do
  if [[ -d "$resource" ]]; then
    # SPM locates its resource bundle next to the executable or in Bundle.main.resourceURL.
    ditto "$resource" "$APP/Contents/Resources/$(basename "$resource")"
  fi
done
cp packaging/Info.plist "$APP/Contents/Info.plist"
if [[ -f packaging/MyDesk.icns ]]; then cp packaging/MyDesk.icns "$APP/Contents/Resources/MyDesk.icns"; fi
if [[ -n "${MYDESK_SIGN_IDENTITY:-}" ]]; then
  codesign --force --options runtime --timestamp --sign "$MYDESK_SIGN_IDENTITY" "$APP"
else
  codesign --force --sign - "$APP"
fi
codesign --verify --strict --verbose=2 "$APP"
if [[ -n "${MYDESK_NOTARY_PROFILE:-}" ]]; then
  if [[ -z "${MYDESK_SIGN_IDENTITY:-}" ]]; then echo "Notarizace vyžaduje MYDESK_SIGN_IDENTITY." >&2; exit 1; fi
  ditto -c -k --keepParent "$APP" "$PWD/dist/MyDesk-notarization.zip"
  xcrun notarytool submit "$PWD/dist/MyDesk-notarization.zip" --keychain-profile "$MYDESK_NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
fi
STAGE="$(mktemp -d "$PWD/dist/dmg-stage.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/MY DESK.app"
ln -s /Applications "$STAGE/Applications"
cp README-CS.md "$STAGE/Instalace.txt"
hdiutil create -volname "MY DESK" -srcfolder "$STAGE" -ov -format UDZO "$PWD/dist/MyDesk.dmg"
echo "Hotovo: $PWD/dist/MY DESK.app a $PWD/dist/MyDesk.dmg"
