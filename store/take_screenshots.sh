#!/usr/bin/env bash
# Builds the game for the simulator and takes the App Store screenshots (iPhone and 13-inch iPad)
# into shots/iphone and shots/ipad. Used by the truck-sim-screenshots and truck-sim-release workflows.
set -e
brew install xcodegen
xcodegen generate
xcodebuild -project TruckSim.xcodeproj -scheme TruckSim -configuration Debug \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build | tail -5

# shoot KIND PATTERN: picks the newest iOS that has a device whose name contains PATTERN
# (the biggest iPhone or iPad Apple asks for), and takes the five screenshots into shots/KIND.
shoot() {
  KIND=$1; PATTERN=$2
  read RUNTIME TYPE <<< "$(PATTERN="$PATTERN" xcrun simctl list runtimes -j | PATTERN="$PATTERN" python3 -c '
import json, os, re, sys
want = os.environ["PATTERN"]
rts = [r for r in json.load(sys.stdin)["runtimes"] if r["platform"] == "iOS" and r["isAvailable"]]
def num(t):
    m = re.findall(r"\d+", t["name"])
    return [int(x) for x in m]
for rt in reversed(rts):
    found = [t for t in rt.get("supportedDeviceTypes", []) if want in t["name"]]
    if found:
        print(rt["identifier"], max(found, key=num)["identifier"]); break')"
  echo "=== $KIND: device $TYPE on $RUNTIME"
  UDID=$(xcrun simctl create "Screenshots $KIND" "$TYPE" "$RUNTIME")
  xcrun simctl boot "$UDID"
  xcrun simctl bootstatus "$UDID" -b
  xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3 || true
  xcrun simctl install "$UDID" build/Build/Products/Debug-iphonesimulator/TruckSim.app
  mkdir -p "shots/$KIND"
  n=1
  for SCREEN in drive jobs garage company menu; do
    xcrun simctl launch --terminate-running-process "$UDID" com.accessibletrucksim.TruckSim -screenshot $SCREEN
    if [ "$SCREEN" = "drive" ]; then sleep 25; else sleep 6; fi
    xcrun simctl io "$UDID" screenshot "shots/$KIND/raw_${n}_${SCREEN}.png"
    n=$((n+1))
  done
  xcrun simctl shutdown "$UDID" || true
  # The app is landscape-only; the simulator captures the portrait framebuffer. Turn each picture.
  for f in shots/$KIND/raw_*.png; do
    out="shots/$KIND/$(basename "$f" | sed 's/raw_//')"
    w=$(sips -g pixelWidth "$f" | awk '/pixelWidth/{print $2}')
    h=$(sips -g pixelHeight "$f" | awk '/pixelHeight/{print $2}')
    if [ "$h" -gt "$w" ]; then sips -r ${ROTATE:-270} "$f" --out "$out" >/dev/null; else cp "$f" "$out"; fi
    sips -g pixelWidth -g pixelHeight "$out" | tail -2
  done
  rm shots/$KIND/raw_*.png
}
shoot iphone "Pro Max"
shoot ipad "iPad Pro 13"
# If the app crashed, show why.
for r in ~/Library/Logs/DiagnosticReports/TruckSim*; do
  [ -f "$r" ] || continue
  echo "=== Crash report $r"; head -c 6000 "$r"; cp "$r" shots/ || true
done
