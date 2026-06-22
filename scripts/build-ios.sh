#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

xcodebuild \
  -project "$ROOT/XDVPN-iOS.xcodeproj" \
  -target XDVPNiOS \
  -configuration Debug \
  -sdk iphonesimulator \
  CODE_SIGN_IDENTITY=- \
  ONLY_ACTIVE_ARCH=NO \
  build
