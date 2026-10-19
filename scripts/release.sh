#!/bin/zsh
# Builds a universal Legato.app and packages it for a GitHub release, in build/release:
#   Legato-<version>.zip, Legato.zip   the app, for scripts/get.sh (~/Library/Input Methods;
#                                          Legato.zip keeps releases/latest/download stable)
#   Legato-<version>.pkg, Legato.pkg   an installer into /Library/Input Methods that registers
#                                          it for the logged-in user (Legato.pkg keeps
#                                          releases/latest/download stable for the website)
#   Seamtype.pkg, Seamtype.zip             the same files under the name before 0.2.0: Seamtype's
#                                          update check (0.1.x) looks for Seamtype.pkg, and the
#                                          get.sh of those versions downloads Seamtype.zip
#
# With a Developer ID, the app and the package are also signed (hardened runtime), notarized and
# stapled:
#   LEGATO_APP_SIGN="Developer ID Application: Name (TEAMID)"
#   LEGATO_PKG_SIGN="Developer ID Installer: Name (TEAMID)"
#   LEGATO_NOTARY_PROFILE=legato   # once: xcrun notarytool store-credentials legato …
# Without them the app is signed ad hoc (still with the hardened runtime, so it is tested the
# way it ships) and the package is unsigned: enough to try the installer on this Mac.
#
#   scripts/release.sh
set -euo pipefail
cd "${0:A:h}/.."

# Signed below either way; ad hoc here unless a Developer ID is given, rather than whatever
# identity build-app.sh would find in the keychain.
LEGATO_ARCHS="arm64 x86_64" LEGATO_APP_SIGN="${LEGATO_APP_SIGN:--}" scripts/build-app.sh
app=build/Legato.app
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
  result=$(xcrun notarytool submit "$1" --keychain-profile "$LEGATO_NOTARY_PROFILE" --wait --output-format json) || true
  id=$(plutil -extract id raw - <<< "$result" 2>/dev/null) || true
  notary_status=$(plutil -extract status raw - <<< "$result" 2>/dev/null) || true
  [[ $notary_status == Accepted ]] && return
  print -r -- "notarization of $1: ${notary_status:-failed}" >&2
  print -r -- "$result" >&2
  [[ -n $id ]] && xcrun notarytool log "$id" --keychain-profile "$LEGATO_NOTARY_PROFILE" >&2
  return 1
}

sign=(--force --options runtime --sign "${LEGATO_APP_SIGN:--}")
[[ -n ${LEGATO_APP_SIGN:-} ]] && sign+=(--timestamp)  # notarization wants a secure timestamp
codesign $sign "$app" 2>/dev/null
codesign --verify --strict "$app"
# The hardened runtime must not stop the bundle from loading its models.
"$app/Contents/MacOS/Legato" --selftest >/dev/null
# Running it registered build/Legato.app with LaunchServices again (build-app.sh had taken it off).
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$app" 2>/dev/null || true

# Notarize the app itself, not only the package, so a Legato.zip downloaded in a browser opens
# too. The stapled ticket travels inside the bundle, into both the zip and the package.
if [[ -n ${LEGATO_NOTARY_PROFILE:-} ]]; then
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
quietly pkgbuild --root $out/root --component-plist $out/component.plist --install-location "/Library/Application Support/Legato/Install" \
  --scripts scripts/pkg --identifier com.nyttastudio.inputmethod.Legato.pkg --version "$version" \
  $out/Legato-component.pkg
pkg=$out/Legato-$version.pkg
# An array: zsh would pass ${…:+--sign "$name"} as one word, which productbuild rejects.
pkgsign=()
[[ -n ${LEGATO_PKG_SIGN:-} ]] && pkgsign=(--sign "$LEGATO_PKG_SIGN" --timestamp)
# The optional clean reinstall (Customize → Reset settings and learned words): scripts only.
quietly pkgbuild --nopayload --scripts scripts/pkg-reset --identifier com.nyttastudio.inputmethod.Legato.reset \
  --version "$version" $out/Legato-reset.pkg
sed "s/@VERSION@/$version/g" scripts/Distribution.xml > $out/Distribution.xml
quietly productbuild --distribution $out/Distribution.xml --package-path $out $pkgsign $pkg
# pkgbuild registered the staged copy with LaunchServices; like build-app.sh, unregister it so
# macOS never picks it when it launches the input method.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$out/root/Legato.app" 2>/dev/null || true
rm -rf $out/root $out/component.plist $out/Legato-component.pkg $out/Legato-reset.pkg $out/Distribution.xml

# The zip keeps the signature and its sealed resources intact (ditto, not zip).
ditto -c -k --keepParent "$app" $out/Legato-$version.zip
cp $out/Legato-$version.zip $out/Legato.zip

if [[ -n ${LEGATO_NOTARY_PROFILE:-} ]]; then
  notarize $pkg
  xcrun stapler staple $pkg
fi
cp $pkg $out/Legato.pkg
cp $out/Legato.pkg $out/Seamtype.pkg
cp $out/Legato.zip $out/Seamtype.zip
[[ -z ${LEGATO_APP_SIGN:-} ]] &&
  echo "warning: ad-hoc app: Gatekeeper rejects it once installed from the pkg (it is selected but never starts); try installs with scripts/install.sh"
echo "built $out/Legato-$version.zip, $out/Legato.zip, $pkg, $out/Legato.pkg (and Seamtype.pkg, Seamtype.zip)"
echo "  (${LEGATO_APP_SIGN:-ad-hoc app}, ${LEGATO_PKG_SIGN:-unsigned pkg}${LEGATO_NOTARY_PROFILE:+, notarized})"
