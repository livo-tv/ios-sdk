#!/usr/bin/env bash
# Quality gate for ios-sdk: LivoStudioAPI tests (no camera) plus a LivoStudioKit compile.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if ! command -v xcodebuild >/dev/null 2>&1 || ! xcodebuild -version >/dev/null 2>&1; then
	if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
		export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
		export PATH="/Applications/Xcode.app/Contents/Developer/usr/bin:${PATH}"
	else
		echo "xcodebuild is not available and /Applications/Xcode.app is missing" >&2
		exit 1
	fi
fi

pick_simulator() {
	xcrun simctl list devices available --json | /usr/bin/python3 -c '
import json, sys
data = json.load(sys.stdin)
iphones = []
for runtime, devices in data.get("devices", {}).items():
    if "iOS" not in runtime and "ios" not in runtime.lower():
        continue
    for device in devices:
        name = device.get("name") or ""
        if not name.startswith("iPhone"):
            continue
        if not device.get("isAvailable", True):
            continue
        numbered = 0
        digits = "".join(ch if ch.isdigit() else " " for ch in name).split()
        if digits:
            numbered = int(digits[0])
        iphones.append((
            device.get("state") == "Booted",
            numbered,
            name,
        ))
if not iphones:
    sys.stderr.write("no available iPhone simulator\n")
    sys.exit(1)
iphones.sort(key=lambda item: (item[0], item[1], item[2]), reverse=True)
print(iphones[0][2])
'
}

SIM="${LIVO_SIM:-$(pick_simulator)}"
echo "Using iPhone simulator: ${SIM}"

xcodebuild test \
	-scheme ios-sdk-Package \
	-destination "platform=iOS Simulator,name=${SIM}" \
	-quiet

if [[ -d Examples/StudioExample/StudioExample.xcodeproj ]]; then
	xcodebuild build \
		-project Examples/StudioExample/StudioExample.xcodeproj \
		-scheme StudioExample \
		-destination "platform=iOS Simulator,name=${SIM}" \
		-quiet
fi
