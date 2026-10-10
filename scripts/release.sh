#!/bin/zsh
# Builds a universal Seamtype.app and packages it for a GitHub release, in build/release:
#   Seamtype-<version>.zip, Seamtype.zip   the app, for scripts/get.sh (~/Library/Input Methods;
#                                          Seamtype.zip keeps releases/latest/download stable)
#   Seamtype-<version>.pkg                 an installer into /Library/Input Methods that registers
#                                          it for the logged-in user
#
# With a Developer ID, it is also signed (hardened runtime), notarized and stapled:
#   SEAMTYPE_APP_SIGN="Developer ID Application: Name (TEAMID)"
#   SEAMTYPE_PKG_SIGN="Developer ID Installer: Name (TEAMID)"
#   SEAMTYPE_NOTARY_PROFILE=seamtype   # once: xcrun notarytool store-credentials seamtype …
# Without them the app is signed ad hoc (still with the hardened runtime, so it is tested the
# way it ships) and the package is unsigned: enough to try the installer on this Mac.
#
#   scripts/release.sh
set -euo pipefail
cd "${0:A:h}/.."

SEAMTYPE_ARCHS="arm64 x86_64" scripts/build-app.sh
app=build/Seamtype.app
version=$(plutil -extract CFBundleShortVersionString raw "$app/Contents/Info.plist")
out=build/release
rm -rf $out
mkdir -p $out/root

sign=(--force --options runtime --sign "${SEAMTYPE_APP_SIGN:--}")
[[ -n ${SEAMTYPE_APP_SIGN:-} ]] && sign+=(--timestamp)  # notarization wants a secure timestamp
codesign $sign "$app" 2>/dev/null
codesign --verify --strict "$app"
# The hardened runtime must not stop the bundle from loading its models.
"$app/Contents/MacOS/Seamtype" --selftest >/dev/null

# Not relocatable: the installer must not "upgrade" a copy it finds elsewhere (a development
# install in ~/Library/Input Methods) instead of installing into /Library/Input Methods.
cp -R "$app" $out/root/
pkgbuild --analyze --root $out/root $out/component.plist | grep -v '^pkgbuild: ' || true
plutil -replace 0.BundleIsRelocatable -bool false $out/component.plist
pkgbuild --root $out/root --component-plist $out/component.plist --install-location "/Library/Input Methods" \
  --scripts scripts/pkg --identifier com.aimdevlee.inputmethod.Seamtype.pkg --version "$version" \
  $out/Seamtype-component.pkg | grep -v '^pkgbuild: ' || true
pkg=$out/Seamtype-$version.pkg
productbuild --package $out/Seamtype-component.pkg ${SEAMTYPE_PKG_SIGN:+--sign "$SEAMTYPE_PKG_SIGN"} $pkg | grep -v '^productbuild: ' || true
# pkgbuild registered the staged copy with LaunchServices; like build-app.sh, unregister it so
# macOS never picks it when it launches the input method.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$out/root/Seamtype.app" 2>/dev/null || true
rm -rf $out/root $out/component.plist $out/Seamtype-component.pkg

# The zip keeps the signature and its sealed resources intact (ditto, not zip).
ditto -c -k --keepParent "$app" $out/Seamtype-$version.zip
cp $out/Seamtype-$version.zip $out/Seamtype.zip

if [[ -n ${SEAMTYPE_NOTARY_PROFILE:-} ]]; then
  xcrun notarytool submit $pkg --keychain-profile "$SEAMTYPE_NOTARY_PROFILE" --wait
  xcrun stapler staple $pkg
fi
echo "built $out/Seamtype-$version.zip, $out/Seamtype.zip, $pkg"
echo "  (${SEAMTYPE_APP_SIGN:-ad-hoc app}, ${SEAMTYPE_PKG_SIGN:-unsigned pkg}${SEAMTYPE_NOTARY_PROFILE:+, notarized})"
