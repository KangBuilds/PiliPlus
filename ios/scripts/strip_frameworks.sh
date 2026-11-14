#!/bin/sh
# Strips local and debugging symbols from the frameworks embedded in Runner.app
# for Release and Profile builds, then re-signs the ones it changed.
#
# CocoaPods copies vendored binaries (mpv, FFmpeg, libass and friends) as they
# are, and Xcode only strips Runner's own executable, so roughly 5 MB of
# symbol tables would otherwise ship. Global symbols are kept, so dynamic
# linking is unaffected. Frameworks built from source have their dSYMs
# written before this runs, so their crash reports still symbolicate.
set -eu

[ "$CONFIGURATION" = Debug ] && exit 0

frameworks="$TARGET_BUILD_DIR/$FRAMEWORKS_FOLDER_PATH"
[ -d "$frameworks" ] || exit 0

for framework in "$frameworks"/*.framework; do
  name="$(basename "$framework" .framework)"
  # Flutter builds and strips these two itself.
  case "$name" in App | Flutter) continue ;; esac

  binary="$framework/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$framework/Info.plist" 2>/dev/null || echo "$name")"
  [ -f "$binary" ] || continue

  before="$(stat -f %z "$binary")"
  xcrun strip -x -S "$binary" 2>/dev/null
  after="$(stat -f %z "$binary")"
  [ "$before" = "$after" ] && continue
  echo "Stripped $name: $((before / 1024)) KB -> $((after / 1024)) KB"

  if [ "${CODE_SIGNING_ALLOWED:-NO}" = YES ] && [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]; then
    # Same signing command CocoaPods uses when it embeds the framework.
    # shellcheck disable=SC2086
    /usr/bin/codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" ${OTHER_CODE_SIGN_FLAGS:-} \
      --preserve-metadata=identifier,entitlements "$framework"
  fi
done
