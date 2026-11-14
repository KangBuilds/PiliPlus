#!/usr/bin/env bash
# Build PiliPlus for iOS on this Mac and install it on a connected iPhone or
# iPad, signed with your own Apple Development certificate, or upload it to
# TestFlight for internal testing (--testflight).
#
# Uses the Flutter version pubspec.yaml asks for and the Xcode selected with
# xcode-select. Xcode signs automatically for your team and may register a
# new device with it (-allowProvisioningDeviceRegistration).
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: lib/scripts/build_install_ios.sh [options]

  --device <udid|name>  Device to install on (default: the only connected one)
  --team <id>           Apple developer team (default: from your profiles)
  --flutter <path>      Flutter executable (default: matching pubspec.yaml)
  --testflight          Archive and upload to TestFlight (internal testing only)
                        instead of installing on a device
  --no-install          Build only
  --no-launch           Install without launching the app
  -h, --help            Show this help

Set FLUTTER_ROOTS to a colon-separated list of directories holding Flutter
SDKs named flutter-<version> (default: ~/development).
EOF
}

device=""
team=""
flutter=""
install=1
launch=1
testflight=0

while (($#)); do
  case "$1" in
    --device) device="$2"; shift 2 ;;
    --team) team="$2"; shift 2 ;;
    --flutter) flutter="$2"; shift 2 ;;
    --testflight) testflight=1; shift ;;
    --no-install) install=0; shift ;;
    --no-launch) launch=0; shift ;;
    -h | --help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

for tool in git xcrun xcodebuild security python3; do
  command -v "$tool" >/dev/null || { echo "Missing required tool: $tool" >&2; exit 1; }
done

root="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
cd "$root"
out="$root/build/ios-local"
mkdir -p "$out"

# --- Flutter --------------------------------------------------------------
want="$(sed -nE 's/^  flutter: *"?([0-9.]+)"?$/\1/p' pubspec.yaml | head -1)"
[[ -n "$want" ]] || { echo "pubspec.yaml has no environment flutter version." >&2; exit 1; }
flutter_version() { "$1" --version --machine 2>/dev/null | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["frameworkVersion"])'; }
if [[ -z "$flutter" ]]; then
  candidates=()
  command -v flutter >/dev/null && candidates+=("$(command -v flutter)")
  IFS=: read -r -a roots <<<"${FLUTTER_ROOTS:-$HOME/development}"
  for dir in "${roots[@]}"; do candidates+=("$dir/flutter-$want/bin/flutter"); done
  for candidate in "${candidates[@]}"; do
    if [[ -x "$candidate" && "$(flutter_version "$candidate")" == "$want" ]]; then
      flutter="$candidate"
      break
    fi
  done
  if [[ -z "$flutter" ]]; then
    cat >&2 <<EOF
No Flutter $want found on PATH or in ${FLUTTER_ROOTS:-$HOME/development}/flutter-$want.
Install it with:
  git clone --depth 1 -b $want https://github.com/flutter/flutter.git ~/development/flutter-$want
EOF
    exit 1
  fi
elif [[ "$(flutter_version "$flutter")" != "$want" ]]; then
  echo "$flutter is not Flutter $want (pubspec.yaml)." >&2
  exit 1
fi
echo "Flutter $want: $flutter"
echo "$(xcodebuild -version | head -1)"

# --- Device ---------------------------------------------------------------
if ((!testflight)); then
xcrun devicectl list devices --json-output "$out/devices.json" >/dev/null
device="$(python3 -I - "$out/devices.json" "$device" <<'PY'
import json, sys
devices = json.load(open(sys.argv[1]))["result"]["devices"]
wanted = sys.argv[2]
physical = [
    d for d in devices
    if d["hardwareProperties"].get("reality") == "physical"
    and d["connectionProperties"].get("tunnelState") == "connected"
]
if wanted:
    match = [
        d for d in devices
        if wanted in (d["hardwareProperties"].get("udid"), d["deviceProperties"].get("name"))
    ]
    if not match:
        sys.exit(f"No device named or identified as {wanted!r}.")
    print(match[0]["hardwareProperties"]["udid"])
elif len(physical) == 1:
    print(physical[0]["hardwareProperties"]["udid"])
else:
    names = ", ".join(d["deviceProperties"]["name"] for d in physical) or "none"
    sys.exit(f"Pass --device: connected devices: {names}.")
PY
)"
echo "Device: $device"
fi

# --- Team -----------------------------------------------------------------
if [[ -z "$team" ]]; then
  security find-identity -v -p codesigning >"$out/identities.txt"
  team="$(python3 -I - "$out/identities.txt" <<'PY'
import datetime, hashlib, pathlib, plistlib, subprocess, sys
identities = pathlib.Path(sys.argv[1]).read_text()
dirs = [
    pathlib.Path.home() / "Library/Developer/Xcode/UserData/Provisioning Profiles",
    pathlib.Path.home() / "Library/MobileDevice/Provisioning Profiles",
]
now = datetime.datetime.now(datetime.timezone.utc)
teams = set()
for path in (p for d in dirs if d.is_dir() for p in d.glob("*.mobileprovision")):
    raw = subprocess.run(["security", "cms", "-D", "-i", str(path)], capture_output=True).stdout
    if not raw:
        continue
    profile = plistlib.loads(raw)
    if profile["ExpirationDate"].replace(tzinfo=datetime.timezone.utc) <= now:
        continue
    if not profile["Entitlements"].get("get-task-allow"):
        continue
    if any(hashlib.sha1(c).hexdigest().upper() in identities
           for c in profile.get("DeveloperCertificates", [])):
        teams.add(profile["TeamIdentifier"][0])
if len(teams) != 1:
    found = ", ".join(sorted(teams)) or "none"
    sys.exit(f"Pass --team: development teams with a certificate here: {found}.")
print(teams.pop())
PY
)"
fi
echo "Team: $team"

# --- Version (as lib/scripts/build.ps1 does on CI) -------------------------
name="$(sed -nE 's/^version: *([0-9.]+).*/\1/p' pubspec.yaml | head -1)"
code="$(git rev-list --count HEAD)"
printf '{"pili.name":"%s","pili.code":%s,"pili.hash":"%s","pili.time":%s}\n' \
  "$name" "$code" "$(git rev-parse HEAD)" "$(date +%s)" >pili_release.json
echo "Version: $name ($code)"

# --- Build ----------------------------------------------------------------
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 # CocoaPods needs a UTF-8 locale
"$flutter" pub get >/dev/null
"$flutter" build ios --release --config-only \
  --build-name="$name" --build-number="$code" \
  --dart-define-from-file=pili_release.json
if ((testflight)); then
  archive="$out/PiliPlus.xcarchive"
  rm -rf "$archive" "$out/export"
  echo "Archiving with Xcode (log: $out/xcodebuild.log)..."
  if ! xcodebuild archive -workspace ios/Runner.xcworkspace -scheme Runner \
    -configuration Release -destination generic/platform=iOS \
    -archivePath "$archive" -derivedDataPath "$out/DerivedData" \
    -allowProvisioningUpdates DEVELOPMENT_TEAM="$team" CODE_SIGN_STYLE=Automatic \
    >"$out/xcodebuild.log" 2>&1; then
    grep -E "error:|ARCHIVE FAILED" "$out/xcodebuild.log" | head -20 >&2
    exit 1
  fi
  cat >"$out/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>teamID</key><string>$team</string>
  <key>signingStyle</key><string>automatic</string>
  <key>testFlightInternalTestingOnly</key><true/>
  <key>manageAppVersionAndBuildNumber</key><false/>
  <key>uploadSymbols</key><true/>
</dict>
</plist>
EOF
  echo "Uploading to App Store Connect (log: $out/upload.log)..."
  if ! xcodebuild -exportArchive -archivePath "$archive" \
    -exportOptionsPlist "$out/ExportOptions.plist" -exportPath "$out/export" \
    -allowProvisioningUpdates >"$out/upload.log" 2>&1; then
    grep -iE "error|fail" "$out/upload.log" | head -20 >&2
    exit 1
  fi
  rm -rf "$archive"
  echo "Uploaded PiliPlus $name ($code). It appears in TestFlight once App Store Connect finishes processing it."
  exit 0
fi
echo "Building with Xcode (log: $out/xcodebuild.log)..."
if ! xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner \
  -configuration Release -destination "id=$device" \
  -derivedDataPath "$out/DerivedData" \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
  DEVELOPMENT_TEAM="$team" CODE_SIGN_STYLE=Automatic \
  CODE_SIGN_IDENTITY="Apple Development" \
  build >"$out/xcodebuild.log" 2>&1; then
  grep -E "error:|BUILD FAILED" "$out/xcodebuild.log" | head -20 >&2
  exit 1
fi
app="$out/DerivedData/Build/Products/Release-iphoneos/Runner.app"
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Info.plist")"
echo "Built $bundle_id: $app"
((install)) || exit 0

# --- Install --------------------------------------------------------------
if ! xcrun devicectl device install app --device "$device" "$app" >"$out/install.log" 2>&1; then
  cat "$out/install.log" >&2
  if grep -q MismatchedApplicationIdentifierEntitlement "$out/install.log"; then
    cat >&2 <<EOF

$bundle_id is already installed with a different signature (for example by
a sideloading app). Export your login in PiliPlus first (关于 → 导入/导出登录信息),
then remove it (this deletes its data):
  xcrun devicectl device uninstall app --device $device $bundle_id
EOF
  fi
  exit 1
fi
if ((launch)); then
  xcrun devicectl device process launch --device "$device" --terminate-existing "$bundle_id" >/dev/null
  echo "Installed and launched PiliPlus $name ($code)."
else
  echo "Installed PiliPlus $name ($code)."
fi
