#!/bin/bash
# Archives Zeist Chess and uploads it to App Store Connect for TestFlight. Build numbers are set at upload.
# Run from anywhere on the build Mac: bash ios/scripts/testflight.sh
# The archive is signed for development with the App Store Connect API key in ios/scripts/signing.local.sh
# (git-ignored; sets ASC_KEY_PATH, ASC_KEY_ID, ASC_ISSUER_ID). The build is then signed for distribution by hand:
# the team's Apple Distribution certificate must be in the keychain and the App Store provisioning profile named
# in ExportOptions-appstore.plist must be installed on the build Mac. No Xcode account is needed.
# The signed build is uploaded with the API key.
# The build number must be higher than the last one uploaded: set BUILD, or it uses the time.
# The team comes from project.yml. Uploading shares the app outside this Mac: the repository's rule is that the
# source is public by the time anyone else receives a build.
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f scripts/signing.local.sh ] && source scripts/signing.local.sh
: "${ASC_KEY_PATH:?Set ASC_KEY_PATH, ASC_KEY_ID and ASC_ISSUER_ID (ios/scripts/signing.local.sh)}"
O=build/tf
mkdir -p $O
xcodegen generate >/dev/null
xcodebuild -project ZeistChess.xcodeproj -scheme ZeistChess -configuration Release -destination 'generic/platform=iOS' \
  -archivePath $O/ZeistChess.xcarchive -allowProvisioningUpdates CURRENT_PROJECT_VERSION="${BUILD:-$(date +%Y%m%d%H%M)}" \
  -authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID" archive -quiet
rm -rf $O/ipa
# Signed by hand with the team's distribution certificate and the App Store
# profile named in ExportOptions-appstore.plist, so no Xcode account is needed.
xcodebuild -exportArchive -archivePath $O/ZeistChess.xcarchive -exportOptionsPlist ExportOptions-appstore.plist \
  -exportPath $O/ipa -quiet
xcrun altool --upload-app -f $O/ipa/ZeistChess.ipa -t ios --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID" \
  --p8-file-path "$ASC_KEY_PATH" 2>&1 | grep -E "UPLOAD SUCCEEDED|ERROR|error" || { echo "upload failed"; exit 1; }
echo "testflight ok: processing in App Store Connect, then it appears under TestFlight"
