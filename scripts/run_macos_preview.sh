#!/bin/sh
set -eu

exec flutter run -d macos \
  --dart-define=DESKTOP_VISUAL_PREVIEW=true \
  --dart-define=AMAZON_APPSTORE_BUILD=true
