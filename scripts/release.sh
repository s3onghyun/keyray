#!/bin/sh
# Build build/Keyray.app signed with Developer ID, notarize it, staple the ticket and check that
# Gatekeeper accepts it. A Developer ID signature gives the app a stable designated requirement
# (bundle id + team), so macOS keeps its Input Monitoring grant across updates; an ad hoc build
# (scripts/bundle.sh alone) loses it on every rebuild.
#
#   NOTARY_ISSUER       App Store Connect API issuer id (required)
#   NOTARY_KEY          App Store Connect API key .p8 (default: the only AuthKey_*.p8 in
#                       ~/.local/share/apple-devid); the key id comes from its AuthKey_<id>.p8 name
#   TEAM_ID             default 9Z598JT4VP
#   SIGN_IDENTITY       default "Developer ID Application: Seonghyun Hong ($TEAM_ID)"
#   SIGN_KEYCHAIN       keychain holding that identity (default ~/Library/Keychains/devid-release.keychain-db,
#                       or the search list if that file does not exist)
#   SIGN_KEYCHAIN_PASSWORD_FILE  unlocks SIGN_KEYCHAIN without a prompt
#                       (default ~/.local/share/apple-devid/devid-release.keychain.pass)
#   SDKROOT, SWIFT_BUILD_FLAGS, ARCHS are passed to scripts/bundle.sh.
#
# Output: build/Keyray.app (stapled) and build/Keyray-<version>.zip. Never prints a secret.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
version=$(tr -d '\r\n' < "$root/VERSION")
app="$root/build/Keyray.app"
team=${TEAM_ID:-9Z598JT4VP}
devid=$HOME/.local/share/apple-devid

: "${NOTARY_ISSUER:?set NOTARY_ISSUER to the App Store Connect API issuer id}"
if [ -z "${NOTARY_KEY:-}" ]; then
  set -- "$devid"/AuthKey_*.p8
  [ "$#" -eq 1 ] && [ -f "$1" ] || { echo "set NOTARY_KEY to the AuthKey_<id>.p8 file" >&2; exit 1; }
  NOTARY_KEY=$1
fi
key_id=$(basename "$NOTARY_KEY" .p8 | sed -n 's/^AuthKey_//p')
[ -n "$key_id" ] || { echo "NOTARY_KEY must be named AuthKey_<id>.p8" >&2; exit 1; }

keychain=${SIGN_KEYCHAIN:-$HOME/Library/Keychains/devid-release.keychain-db}
[ -n "${SIGN_KEYCHAIN:-}" ] || [ -f "$keychain" ] || keychain=""
password_file=${SIGN_KEYCHAIN_PASSWORD_FILE:-$devid/devid-release.keychain.pass}
if [ -n "$keychain" ] && [ -f "$password_file" ]; then
  security unlock-keychain -p "$(cat "$password_file")" "$keychain"
fi

SIGN_IDENTITY=${SIGN_IDENTITY:-"Developer ID Application: Seonghyun Hong ($team)"} \
  SIGN_KEYCHAIN=$keychain "$root/scripts/bundle.sh"

codesign --verify --strict --verbose=2 "$app"
signed_team=$(codesign -dv "$app" 2>&1 | sed -n 's/^TeamIdentifier=//p')
[ "$signed_team" = "$team" ] || { echo "signed by team '$signed_team', expected $team" >&2; exit 1; }
codesign -d -r- "$app" 2>&1 | sed -n 's/^designated => /designated requirement: /p'

work=$(mktemp -d "${TMPDIR:-/tmp}/keyray-notarize.XXXXXX")
trap 'rm -rf "$work"' EXIT
ditto -c -k --keepParent "$app" "$work/Keyray.zip"
xcrun notarytool submit "$work/Keyray.zip" --key "$NOTARY_KEY" --key-id "$key_id" \
  --issuer "$NOTARY_ISSUER" --wait --output-format json > "$work/submit.json"
id=$(plutil -extract id raw -o - "$work/submit.json" 2>/dev/null || true)
status=$(plutil -extract status raw -o - "$work/submit.json" 2>/dev/null || true)
echo "notarization $id: $status"
if [ "$status" != Accepted ]; then
  [ -n "$id" ] && xcrun notarytool log "$id" --key "$NOTARY_KEY" --key-id "$key_id" --issuer "$NOTARY_ISSUER" >&2
  exit 1
fi

xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=2 "$app" 2>&1 | tee "$work/spctl.txt"
grep -q "source=Notarized Developer ID" "$work/spctl.txt" \
  || { echo "Gatekeeper does not see a notarized Developer ID app" >&2; exit 1; }

zip="$root/build/Keyray-$version.zip"
rm -f "$zip"
ditto -c -k --keepParent "$app" "$zip"
printf '%s\n%s\n' "$app" "$zip"
