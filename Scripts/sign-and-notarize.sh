#!/bin/zsh
# Builds Proteus.app, signs it with Developer ID (hardened runtime),
# notarizes it with Apple and staples the ticket.
set -euo pipefail
cd "${0:A:h}/.."

readonly APPLE_TEAM_ID="TN899J6HRF"
readonly SIGN_ID="Developer ID Application: CHARALAMPOS TSEVIS (${APPLE_TEAM_ID})"
readonly NOTARY_PROFILE="crewlistr-notary"
readonly APP="Proteus.app"
readonly ZIP=".build/Proteus-notarize.zip"

die() { echo "error: $*" >&2; exit 1; }

security find-identity -v -p codesigning | grep -qF "$SIGN_ID" \
  || die "signing identity not found in keychain: $SIGN_ID"
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
  || die "notary profile '$NOTARY_PROFILE' missing; run notarytool store-credentials"

./build_app.sh
codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$APP"
codesign --verify --strict --verbose=2 "$APP"

rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
result=$(xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait --timeout 15m)
echo "$result"
[[ "$result" == *"status: Accepted"* ]] \
  || die "notarization failed; run: xcrun notarytool log <submission-id> --keychain-profile $NOTARY_PROFILE"

xcrun stapler staple "$APP"
spctl --assess --type execute --verbose=2 "$APP"
echo "Notarized $PWD/$APP"
