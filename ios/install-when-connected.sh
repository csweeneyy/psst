#!/bin/bash
# Waits for the iPhone to appear, then installs and launches the current build.
# Exists because devicectl fails outright when the device is unplugged or
# locked, and the fix is just to try again.
set -u

DEVICE="${PSST_DEVICE:-5E701E6D-312F-53BA-B248-33BBEC436BA0}"
BUNDLE="com.connorsweeney.Psst"
DEADLINE=$((SECONDS + 1800))

app_path() {
  find ~/Library/Developer/Xcode/DerivedData -name "Psst.app" \
    -path "*Debug-iphoneos*" -maxdepth 6 2>/dev/null | head -1
}

echo "waiting for device $DEVICE"
while [ $SECONDS -lt $DEADLINE ]; do
  if xcrun devicectl list devices 2>/dev/null | grep -q "$DEVICE.*available"; then
    APP="$(app_path)"
    if [ -z "$APP" ]; then
      echo "no built .app found; run xcodebuild first"
      exit 1
    fi
    echo "device available, installing $APP"
    if xcrun devicectl device install app --device "$DEVICE" "$APP" 2>&1 | grep -q "App installed"; then
      echo "INSTALLED"
      # Launch is best effort: it fails while the phone is locked.
      xcrun devicectl device process launch --device "$DEVICE" \
        --terminate-existing "$BUNDLE" >/dev/null 2>&1 \
        && echo "LAUNCHED" || echo "installed but not launched (device locked) - tap the icon"
      exit 0
    fi
    echo "install attempt failed, retrying"
  fi
  sleep 3
done

echo "timed out waiting for device"
exit 1
