#!/bin/zsh
set -euo pipefail
script_dir="${0:A:h}"
cd "${SRCROOT:?}"
runtime="${TRUNKLINE_DESKTOP_RUNTIME:-Vendor/SunshineRuntime}"
if [[ -n "${TRUNKLINE_DESKTOP_RUNTIME:-}" ]]; then
  # Fail before changing an existing payload. Never silently fall back to Vendor.
  python3 "$script_dir/desktop_candidate.py" "$runtime"
fi
architectures="${ARCHS:-arm64 x86_64}"
for architecture in ${=architectures}; do
  [[ "$architecture" == arm64 || "$architecture" == x86_64 ]] || { print -u2 "Unsupported architecture: $architecture"; exit 1; }
  [[ -x "$runtime/$architecture/Sunshine.app/Contents/MacOS/Sunshine" ]] || { print -u2 "Missing desktop runtime for $architecture. Run ./Scripts/dev.py build."; exit 1; }
done
destination="${TARGET_BUILD_DIR:?}/${CONTENTS_FOLDER_PATH:?}/Helpers/Desktop"
mkdir -p "$destination"
# Remove only obsolete generated payloads from previous builds.
rm -rf "$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Helpers/Sunshine"
rm -f "$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Helpers/TrunklineSunshineSupervisor" "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/TrunklineSunshineSupervisor"
cp "$BUILT_PRODUCTS_DIR/TrunklineDesktopSupervisor" "$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Helpers/TrunklineDesktopSupervisor"
for architecture in ${=architectures}; do
  source="$runtime/$architecture/Sunshine.app"
  [[ -x "$source/Contents/MacOS/Sunshine" ]] || { print -u2 "Missing pinned Sunshine runtime: $architecture"; exit 1; }
  mkdir -p "$destination/$architecture"
  rsync -a --delete "$source/" "$destination/$architecture/TrunklineDesktop.app/"
  mv "$destination/$architecture/TrunklineDesktop.app/Contents/MacOS/Sunshine" "$destination/$architecture/TrunklineDesktop.app/Contents/MacOS/TrunklineDesktop"
  /usr/libexec/PlistBuddy -c 'Set :CFBundleExecutable TrunklineDesktop' "$destination/$architecture/TrunklineDesktop.app/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c 'Set :CFBundleName Trunkline Desktop' "$destination/$architecture/TrunklineDesktop.app/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c 'Add :CFBundleDisplayName string Trunkline Desktop' "$destination/$architecture/TrunklineDesktop.app/Contents/Info.plist" 2>/dev/null || /usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName Trunkline Desktop' "$destination/$architecture/TrunklineDesktop.app/Contents/Info.plist"
  cp "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/AppIcon.icns" "$destination/$architecture/TrunklineDesktop.app/Contents/Resources/Trunkline.icns"
  /usr/libexec/PlistBuddy -c 'Set :CFBundleIconFile Trunkline.icns' "$destination/$architecture/TrunklineDesktop.app/Contents/Info.plist"
  python3 - "$destination/$architecture/TrunklineDesktop.app/Contents/Info.plist" <<'PY'
import pathlib, plistlib, sys
path = pathlib.Path(sys.argv[1])
info = plistlib.loads(path.read_bytes())
info.update({
    'NSMicrophoneUsageDescription': 'Trunkline Desktop uses audio input for remote streaming.',
    'NSAudioCaptureUsageDescription': 'Trunkline Desktop streams your Mac audio to your paired device.',
    'NSScreenCaptureUsageDescription': 'Trunkline Desktop shares your screen with your paired device.',
    'NSLocalNetworkUsageDescription': 'Trunkline Desktop lets your paired devices find this Mac on your local network.',
})
path.write_bytes(plistlib.dumps(info))
PY
done
if [[ -n "${TRUNKLINE_DESKTOP_RUNTIME:-}" ]]; then
  # Helpers is reserved for nested code. Keep provenance/notices in Resources
  # so codesign does not try to interpret source/license files as executables.
  rm -f "$destination/PROVENANCE.json"
  rm -rf "$destination/ThirdParty"
  candidate_notices="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/ThirdParty/DesktopCandidate"
  mkdir -p "$candidate_notices"
  rsync -a --delete "$runtime/ThirdParty/" "$candidate_notices/"
  cp "$runtime/PROVENANCE.json" "$candidate_notices/PROVENANCE.json"
else
  rm -f "$destination/PROVENANCE.json"
  rm -rf "$destination/ThirdParty"
  rm -rf "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/ThirdParty/DesktopCandidate"
fi
if [[ "${CODE_SIGNING_ALLOWED:-NO}" == YES ]]; then
  python3 "$SRCROOT/Scripts/sign-desktop.py" "$destination"
  identity="${EXPANDED_CODE_SIGN_IDENTITY:?A signing identity is required for the supervisor}"
  if [[ "$identity" == - ]]; then
    codesign --force --sign - "$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Helpers/TrunklineDesktopSupervisor"
  else
    timestamp_flag=--timestamp
    [[ "${EXPANDED_CODE_SIGN_IDENTITY_NAME:-}" == "Apple Development:"* ]] && timestamp_flag=--timestamp=none
    codesign --force --options runtime "$timestamp_flag" --sign "$identity" "$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Helpers/TrunklineDesktopSupervisor"
  fi
fi
