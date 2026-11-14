#!/bin/sh
# Xcode Cloud: prepare the Flutter part of the iOS build after cloning.
# Installs the Flutter version pubspec.yaml asks for, writes the release
# defines (as lib/scripts/build.ps1 and build_install_ios.sh do), and
# generates the iOS configuration and Pods.
set -e

cd "$CI_PRIMARY_REPOSITORY_PATH"

# The commit count is the app's version code; it needs the full history.
if [ "$(git rev-parse --is-shallow-repository)" = "true" ]; then
  git fetch --unshallow --quiet
fi

flutter_version="$(sed -nE 's/^  flutter: *"?([0-9.]+)"?$/\1/p' pubspec.yaml | head -1)"
git clone --quiet --depth 1 -b "$flutter_version" \
  https://github.com/flutter/flutter.git "$HOME/flutter"
export PATH="$PATH:$HOME/flutter/bin"
flutter config --no-analytics >/dev/null
flutter precache --ios

name="$(sed -nE 's/^version: *([0-9.]+).*/\1/p' pubspec.yaml | head -1)"
code="$(git rev-list --count HEAD)"
printf '{"pili.name":"%s","pili.code":%s,"pili.hash":"%s","pili.time":%s}\n' \
  "$name" "$code" "$(git rev-parse HEAD)" "$(date +%s)" >pili_release.json

HOMEBREW_NO_AUTO_UPDATE=1 brew install cocoapods
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 # CocoaPods needs a UTF-8 locale
flutter pub get
# Xcode Cloud sets the final build number (CFBundleVersion) itself.
flutter build ios --release --config-only \
  --build-name="$name" --build-number="$code" \
  --dart-define-from-file=pili_release.json
