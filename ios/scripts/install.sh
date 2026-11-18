#!/bin/bash
# Builds Zeist Chess and puts it on a connected iPhone. Run from the repo root on the build Mac.
#   The phone is reachable: installed with devicectl, nothing to tap.
#   Otherwise: an install link over Tailscale (https://<this machine>.<tailnet>.ts.net/zeist-chess/), to open on the phone.
# Signing is automatic development signing for the team in project.yml. Xcode on the build Mac isn't signed in
# to an Apple account, so provisioning uses an App Store Connect API key, read from ios/scripts/signing.local.sh
# (git-ignored), which sets ASC_KEY_PATH, ASC_KEY_ID and ASC_ISSUER_ID. Nothing is uploaded anywhere.
# Packs: Release builds read engines from https://engines.zei.st (Config.xcconfig). No Tailscale is needed on the phone.
set -euo pipefail
cd "$(dirname "$0")/.."
# A PHONE given on the command line wins over the one in signing.local.sh. LINK_ONLY=1 never touches a phone:
# it only publishes the install link.
ASKED=${PHONE:-}
[ -f scripts/signing.local.sh ] && source scripts/signing.local.sh
PHONE=${ASKED:-${PHONE:?Set PHONE to the identifier from xcrun devicectl list devices}}
O=build/device
AUTH=()
if [ -n "${ASC_KEY_PATH:-}" ]; then
  AUTH=(-allowProvisioningUpdates -authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
else
  AUTH=(-allowProvisioningUpdates)
fi
xcodegen generate >/dev/null
xcodebuild -project ZeistChess.xcodeproj -scheme ZeistChess -configuration Release -destination 'generic/platform=iOS' \
  -archivePath $O/ZeistChess.xcarchive "${AUTH[@]}" archive -quiet
rm -rf $O/export
cat > $O/export.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>method</key><string>debugging</string>
<key>signingStyle</key><string>automatic</string>
<key>thinning</key><string>&lt;none&gt;</string>
${MANIFEST:-}
</dict></plist>
PLIST
HOST=$(tailscale status --json 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["Self"]["DNSName"].rstrip("."))' || true)
if [ -n "$HOST" ]; then
  BASE="https://$HOST/zeist-chess"
  sed -i '' "s#^\$#<key>manifest</key><dict><key>appURL</key><string>$BASE/ZeistChess.ipa</string><key>displayImageURL</key><string>$BASE/icon-57.png</string><key>fullSizeImageURL</key><string>$BASE/icon-512.png</string></dict>#" $O/export.plist
fi
xcodebuild -exportArchive -archivePath $O/ZeistChess.xcarchive -exportOptionsPlist $O/export.plist -exportPath $O/export "${AUTH[@]}" -quiet
if [ -z "${LINK_ONLY:-}" ] && xcrun devicectl list devices 2>/dev/null | grep "$PHONE" | grep -v unavailable | grep -Eq "available|connected"; then
  if xcrun devicectl device install app --device "$PHONE" $O/export/ZeistChess.ipa; then echo "install ok: on the iPhone"; exit 0; fi
  echo "The direct install failed; publishing the link."
fi
[ -n "$HOST" ] || { echo "No Tailscale, no link."; exit 1; }
# The link: a local server on 8797, with Tailscale forwarding HTTPS to it under /zeist-chess.
W=$O/www; mkdir -p $W
cp $O/export/ZeistChess.ipa $O/export/manifest.plist $W/
A=ZeistChess/Assets.xcassets/AppIcon.appiconset/icon.png
sips -Z 57 $A --out $W/icon-57.png >/dev/null; sips -Z 512 $A --out $W/icon-512.png >/dev/null
cat > $W/index.html <<HTML
<!doctype html><meta name="viewport" content="width=device-width"><title>Zeist Chess</title>
<body style="background:#12110e;color:#f4f1ea;font:18px -apple-system;padding:40px">
<p>Zeist Chess, built $(date '+%-d %B, %H:%M').</p>
<p><a style="color:#f4f1ea" href="itms-services://?action=download-manifest&url=$BASE/manifest.plist">Install</a></p></body>
HTML
curl -s -o /dev/null http://127.0.0.1:8797/ || (cd $W && nohup python3 -m http.server 8797 --bind 127.0.0.1 >/dev/null 2>&1 &)
tailscale serve --bg --set-path /zeist-chess http://127.0.0.1:8797 >/dev/null
echo "install ok: open $BASE/ on the iPhone with Tailscale on"
