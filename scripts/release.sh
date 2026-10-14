#!/bin/zsh
# Builds a universal Seamtype.app and packages it for a GitHub release, in build/release:
#   Seamtype-<version>.zip, Seamtype.zip   the app, for scripts/get.sh (~/Library/Input Methods;
#                                          Seamtype.zip keeps releases/latest/download stable)
#   Seamtype-<version>.pkg, Seamtype.pkg   an installer into /Library/Input Methods that registers
#                                          it for the logged-in user (Seamtype.pkg keeps
#                                          releases/latest/download stable for the website)
#
# With a Developer ID, the app and the package are also signed (hardened runtime), notarized and
# stapled:
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

# pkgbuild and productbuild narrate every step; show their output only when they fail, and any
# warning when they don't.
quietly() {
  local log
  log=$("$@" 2>&1) || { print -r -- "$log" >&2; return 1; }
  print -r -- "$log" | grep -i 'warning' >&2 || true
}
# notarytool submit --wait can end without an error when Apple rejects the upload: check the
# status, and print Apple's log of what it found when it isn't Accepted.
notarize() {
  local result id notary_status
  result=$(xcrun notarytool submit "$1" --keychain-profile "$SEAMTYPE_NOTARY_PROFILE" --wait --output-format json) || true
  id=$(plutil -extract id raw - <<< "$result" 2>/dev/null) || true
  notary_status=$(plutil -extract status raw - <<< "$result" 2>/dev/null) || true
  [[ $notary_status == Accepted ]] && return
  print -r -- "notarization of $1: ${notary_status:-failed}" >&2
  print -r -- "$result" >&2
  [[ -n $id ]] && xcrun notarytool log "$id" --keychain-profile "$SEAMTYPE_NOTARY_PROFILE" >&2
  return 1
}

sign=(--force --options runtime --sign "${SEAMTYPE_APP_SIGN:--}")
[[ -n ${SEAMTYPE_APP_SIGN:-} ]] && sign+=(--timestamp)  # notarization wants a secure timestamp
codesign $sign "$app" 2>/dev/null
codesign --verify --strict "$app"
# The hardened runtime must not stop the bundle from loading its models.
"$app/Contents/MacOS/Seamtype" --selftest >/dev/null
# Running it registered build/Seamtype.app with LaunchServices again (build-app.sh had taken it off).
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$app" 2>/dev/null || true

# Notarize the app itself, not only the package, so a Seamtype.zip downloaded in a browser opens
# too. The stapled ticket travels inside the bundle, into both the zip and the package.
if [[ -n ${SEAMTYPE_NOTARY_PROFILE:-} ]]; then
  ditto -c -k --keepParent "$app" $out/notarize.zip
  notarize $out/notarize.zip
  xcrun stapler staple "$app"
  rm $out/notarize.zip
fi

# The payload goes to a staging folder and the postinstall syncs it into /Library/Input Methods:
# PackageKit would swap the bundle for a new folder, which imklaunchagent can't launch from until
# the user logs out. Not relocatable: the installer must not "upgrade" a copy it finds elsewhere
# (the installed one, or a development install in ~/Library/Input Methods) in place.
cp -R "$app" $out/root/
quietly pkgbuild --analyze --root $out/root $out/component.plist
plutil -replace 0.BundleIsRelocatable -bool false $out/component.plist
quietly pkgbuild --root $out/root --component-plist $out/component.plist --install-location "/Library/Application Support/Seamtype/Install" \
  --scripts scripts/pkg --identifier com.aimdevlee.inputmethod.Seamtype.pkg --version "$version" \
  $out/Seamtype-component.pkg
pkg=$out/Seamtype-$version.pkg
# An array: zsh would pass ${…:+--sign "$name"} as one word, which productbuild rejects.
pkgsign=()
[[ -n ${SEAMTYPE_PKG_SIGN:-} ]] && pkgsign=(--sign "$SEAMTYPE_PKG_SIGN" --timestamp)
# The optional clean reinstall (Customize → Reset settings and learned words): scripts only.
quietly pkgbuild --nopayload --scripts scripts/pkg-reset --identifier com.aimdevlee.inputmethod.Seamtype.reset \
  --version "$version" $out/Seamtype-reset.pkg
sed "s/@VERSION@/$version/g" scripts/Distribution.xml > $out/Distribution.xml
quietly productbuild --distribution $out/Distribution.xml --package-path $out $pkgsign $pkg
# pkgbuild registered the staged copy with LaunchServices; like build-app.sh, unregister it so
# macOS never picks it when it launches the input method.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$out/root/Seamtype.app" 2>/dev/null || true
rm -rf $out/root $out/component.plist $out/Seamtype-component.pkg $out/Seamtype-reset.pkg $out/Distribution.xml

# The zip keeps the signature and its sealed resources intact (ditto, not zip).
ditto -c -k --keepParent "$app" $out/Seamtype-$version.zip
cp $out/Seamtype-$version.zip $out/Seamtype.zip

if [[ -n ${SEAMTYPE_NOTARY_PROFILE:-} ]]; then
  notarize $pkg
  xcrun stapler staple $pkg
fi
cp $pkg $out/Seamtype.pkg
[[ -z ${SEAMTYPE_APP_SIGN:-} ]] &&
  echo "warning: ad-hoc app: Gatekeeper rejects it once installed from the pkg (it is selected but never starts); try installs with scripts/install.sh"
echo "built $out/Seamtype-$version.zip, $out/Seamtype.zip, $pkg, $out/Seamtype.pkg"
echo "  (${SEAMTYPE_APP_SIGN:-ad-hoc app}, ${SEAMTYPE_PKG_SIGN:-unsigned pkg}${SEAMTYPE_NOTARY_PROFILE:+, notarized})"
